// 传输队列：串行执行、进度、失败自动重试、取消。
//
// 队列与 RemoteStorageService 解耦（runner 闭包注入），便于单测；
// 页面共享同一个 TransferQueue 实例（见 remote_storage_service.dart 的运行时单例）。

import 'dart:async';

import 'package:box/utils/app_logger.dart';
import 'package:box/utils/log_channels.dart';
import 'package:flutter/foundation.dart';

import '../domain/remote_storage_models.dart';

enum TransferKind { download, upload }

enum TransferStatus { queued, running, done, failed, canceled }

/// 单个传输任务。UI 直接监听 [TransferQueue] 的 ChangeNotifier 刷新。
class TransferTask {
  TransferTask._({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.totalBytes,
  });

  final String id;
  final TransferKind kind;

  /// 展示名（文件名）。
  final String title;

  /// 副标题（账户 / 目录 / 远端路径）。
  final String subtitle;

  /// 总字节；-1 表示未知（服务器未给 content-length）。
  int totalBytes;

  int receivedBytes = 0;
  TransferStatus status = TransferStatus.queued;
  String? errorMessage;

  /// 当前处于第几次重试（0 = 未在重试）；UI 用来区分"重试中"与"卡住了"。
  int retryAttempt = 0;

  /// 完成后产物：下载任务为本地文件路径（String）。
  Object? result;

  final TransferCancelToken cancelToken = TransferCancelToken();

  /// 由队列在入队时填充；对 UI 无意义。
  TransferRunner? runner;
  void Function(TransferTask task)? onFinished;

  double get progress {
    if (totalBytes <= 0) return 0;
    return (receivedBytes / totalBytes).clamp(0.0, 1.0);
  }

  bool get isActive =>
      status == TransferStatus.queued || status == TransferStatus.running;

  void requestCancel() {
    if (isActive) cancelToken.cancel();
  }
}

/// 执行体：返回产物（下载为本地路径 String）；进度通过 onProgress 上报。
typedef TransferRunner = Future<Object?> Function(
  TransferCancelToken cancel,
  void Function(int received, int total) onProgress,
);

/// 有界并发的传输队列（默认 [kMaxConcurrentTransfers] 个任务同时在跑）。
class TransferQueue extends ChangeNotifier {
  TransferQueue({this.retryDelay, int? maxConcurrent})
      : maxConcurrent = maxConcurrent ?? kMaxConcurrentTransfers,
        assert((maxConcurrent ?? kMaxConcurrentTransfers) >= 1,
            '并发数至少为 1');

  /// 固定重试等待（测试传 Duration.zero 让退避不占用测试时间）。
  ///
  /// null（生产默认）时按 [kTransferRetryDelays] 退避，并尊重服务端的
  /// `Retry-After`；给了值则一律用该值（但 `Retry-After` 更长时仍取更长）。
  final Duration? retryDelay;

  /// 同时最多在跑的任务数（见 [kMaxConcurrentTransfers]）。
  final int maxConcurrent;

  final List<TransferTask> _tasks = [];
  int _running = 0;
  int _seq = 0;
  DateTime _lastProgressNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// 新的在前。
  List<TransferTask> get tasks => List.unmodifiable(_tasks);

  int get activeCount => _tasks.where((t) => t.isActive).length;

  /// 入队并立即尝试执行（受并发上限约束）。返回任务对象用于展示。
  TransferTask enqueue({
    required TransferKind kind,
    required String title,
    required String subtitle,
    int totalBytes = -1,
    required TransferRunner runner,
    void Function(TransferTask task)? onFinished,
  }) {
    _seq += 1;
    final task = TransferTask._(
      id: 't${DateTime.now().microsecondsSinceEpoch}_$_seq',
      kind: kind,
      title: title,
      subtitle: subtitle,
      totalBytes: totalBytes,
    );
    task.runner = runner;
    task.onFinished = onFinished;
    _tasks.insert(0, task);
    notifyListeners();
    _pump();
    return task;
  }

  void clearFinished() {
    _tasks.removeWhere((t) => !t.isActive);
    notifyListeners();
  }

  /// 重跑一个**失败**的任务（283 D4）。
  ///
  /// 为什么需要：弱网/弱 NAS 上偶发失败很常见。以前只能回列表重新发起一次操作
  /// （上传还得重新选一遍文件），而 runner 闭包一直在任务对象上，重跑的成本只是
  /// 复位状态。
  ///
  /// 只接受"已失败"的任务：跑着的（该用取消）、已完成的（结果有效，重跑会覆盖）、
  /// 已取消的（用户主动放弃）都不给重试。返回是否真的重新入队。
  bool retry(TransferTask task) {
    if (!_tasks.contains(task)) return false;
    if (task.status != TransferStatus.failed) return false;
    task.status = TransferStatus.queued;
    task.receivedBytes = 0;
    task.errorMessage = null;
    task.retryAttempt = 0;
    task.result = null;
    task.cancelToken.reset(); // token 一次性：不复位会被立刻判成取消
    notifyListeners();
    _pump();
    return true;
  }

  /// 第 [attempt] 次重试前的等待：固定值（测试注入）优先，服务端 `Retry-After`
  /// 更长时取更长；生产默认走 [kTransferRetryDelays] 退避。
  Duration _delayFor(int attempt, Object error) {
    final serverWait =
        error is RemoteStorageException ? error.retryAfter : null;
    final fixed = retryDelay;
    if (fixed != null) {
      if (serverWait != null && serverWait > fixed) return serverWait;
      return fixed;
    }
    return retryDelayFor(attempt, retryAfter: serverWait);
  }

  /// 拉起能跑的任务，直到达到并发上限。
  ///
  /// 本方法**不含 await**（[TransferTask.runner] 的等待在 [_run] 里），所以不存在
  /// 重入；任务结束时由完成回调再调一次，把腾出来的位置补上——不需要"是否正在
  /// pump"的开关（原来那个开关只能表达"串行"）。
  void _pump() {
    while (_running < maxConcurrent) {
      final next = _nextQueued();
      if (next == null) return;

      if (next.cancelToken.isCanceled) {
        next.status = TransferStatus.canceled;
        notifyListeners();
        next.onFinished?.call(next);
        continue;
      }

      next.status = TransferStatus.running;
      _running += 1;
      notifyListeners();
      unawaited(
        _run(next).whenComplete(() {
          _running -= 1;
          _pump();
        }),
      );
    }
  }

  TransferTask? _nextQueued() {
    for (final t in _tasks.reversed) {
      if (t.status == TransferStatus.queued) return t;
    }
    return null;
  }

  /// 跑一个任务（含重试与状态落定）；并发度由 [_pump] 控制。
  Future<void> _run(TransferTask current) async {
    var attempt = 0;
    while (true) {
      try {
        final result = await current.runner!(
          current.cancelToken,
          (received, total) {
            current.receivedBytes = received;
            if (total > 0) current.totalBytes = total;
            final now = DateTime.now();
            if (now.difference(_lastProgressNotify).inMilliseconds >=
                150) {
              _lastProgressNotify = now;
              notifyListeners();
            }
          },
        );
        current.result = result;
        current.status = TransferStatus.done;
        break;
      } on TransferCanceledException {
        current.status = TransferStatus.canceled;
        break;
      } catch (e) {
        if (current.cancelToken.isCanceled) {
          current.status = TransferStatus.canceled;
          break;
        }
        current.errorMessage =
            e is RemoteStorageException ? e.message : '$e';
        // 分类：凭证/权限/路径/空间/协议不支持类错误重试多少次都一样，
        // 直接失败——否则用户会因为密码错白等两个退避周期。
        final retryable = isRetryableTransferError(e);
        attempt += 1;
        if (!retryable || attempt > kTransferRetries) {
          current.status = TransferStatus.failed;
          current.retryAttempt = 0;
          AppLogger.instance.logTo(
            LogChannel.storage,
            retryable
                ? '传输失败（已重试 $kTransferRetries 次）: $e'
                : '传输失败（该错误不重试）: $e',
            level: LogLevel.error,
          );
          break;
        }
        current.retryAttempt = attempt;
        notifyListeners();
        await Future<void>.delayed(_delayFor(attempt, e));
        current.retryAttempt = 0;
        notifyListeners();
      }
    }
    notifyListeners();
    current.onFinished?.call(current);
  }
}