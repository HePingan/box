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

/// 串行传输队列。
class TransferQueue extends ChangeNotifier {
  TransferQueue({this.retryDelay = const Duration(milliseconds: 800)});

  /// 重试前的等待（测试传 Duration.zero）。
  final Duration retryDelay;

  final List<TransferTask> _tasks = [];
  bool _pumping = false;
  int _seq = 0;
  DateTime _lastProgressNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// 新的在前。
  List<TransferTask> get tasks => List.unmodifiable(_tasks);

  int get activeCount => _tasks.where((t) => t.isActive).length;

  /// 入队并立即尝试执行（串行）。返回任务对象用于展示。
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
    unawaited(_pump());
    return task;
  }

  void clearFinished() {
    _tasks.removeWhere((t) => !t.isActive);
    notifyListeners();
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (true) {
        TransferTask? next;
        for (final t in _tasks.reversed) {
          if (t.status == TransferStatus.queued) {
            next = t;
            break;
          }
        }
        if (next == null) break;

        if (next.cancelToken.isCanceled) {
          next.status = TransferStatus.canceled;
          notifyListeners();
          next.onFinished?.call(next);
          continue;
        }

        // final 局部别名：闭包内不可用提升后的可空局部变量。
        final current = next;
        current.status = TransferStatus.running;
        notifyListeners();

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
            attempt += 1;
            if (attempt > kTransferRetries) {
              current.status = TransferStatus.failed;
              current.errorMessage =
                  e is RemoteStorageException ? e.message : '$e';
              AppLogger.instance.logTo(
                LogChannel.storage,
                '传输失败（已重试 $kTransferRetries 次）: $e',
                level: LogLevel.error,
              );
              break;
            }
            await Future<void>.delayed(retryDelay);
          }
        }
        notifyListeners();
        current.onFinished?.call(current);
      }
    } finally {
      _pumping = false;
    }
  }
}
