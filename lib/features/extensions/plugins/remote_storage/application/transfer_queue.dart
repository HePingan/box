// 传输队列：串行执行、进度、失败自动重试、取消。
//
// 队列与 RemoteStorageService 解耦（runner 闭包注入），便于单测；
// 页面共享同一个 TransferQueue 实例（见 remote_storage_service.dart 的运行时单例）。

import 'dart:async';

import 'package:box/utils/app_logger.dart';
import 'package:box/utils/log_channels.dart';
import 'package:flutter/foundation.dart';

import '../data/transfer_keepalive.dart';
import '../data/transfer_queue_store.dart';
import '../domain/network_policy.dart';
import '../domain/remote_storage_models.dart';

enum TransferKind { download, upload }

/// 一个任务的**可恢复描述**（284 P1）。
///
/// 只放"重建 runner 需要的字段"：runner 闭包、`onFinished` 回调、UI 文案都不入库。
/// 字段刻意与 service 的两条入口对齐：
/// - 上传：[remotePath] = 远端目标目录，[localPath] = 本地源文件；
/// - 下载：[remotePath] = 远端文件，[subDir] = 保留目录结构时用的子目录名
///   （本地落点由 service 按账户/子目录重新解析，所以不入库 —— 下载断点是按
///   "账户 + 远端路径"归属的，重算落点后 `.part` 照样能续）。
class TransferRestoreSpec {
  const TransferRestoreSpec({
    required this.kind,
    required this.accountId,
    required this.remotePath,
    this.localPath = '',
    this.fileName = '',
    this.subDir,
    this.overwrite = false,
    this.title = '',
    this.subtitle = '',
    this.totalBytes = -1,
  });

  final TransferKind kind;
  final String accountId;
  final String remotePath;
  final String localPath;
  final String fileName;
  final String? subDir;

  /// 上传用：目标已存在时是否覆盖（拍板3 的默认是跳过，必须原样恢复）。
  final bool overwrite;

  final String title;
  final String subtitle;
  final int totalBytes;

  /// 去重键：恢复时若队列里已有同一件事，不重复入队。
  String get dedupeKey => '${kind.name}|$accountId|$remotePath|$localPath';

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'accountId': accountId,
        'remotePath': remotePath,
        'localPath': localPath,
        'fileName': fileName,
        if (subDir != null) 'subDir': subDir,
        'overwrite': overwrite,
        'title': title,
        'subtitle': subtitle,
        'totalBytes': totalBytes,
      };

  /// 坏记录返回 null（调用方跳过，不要让一条脏数据卡住整个恢复）。
  static TransferRestoreSpec? tryParse(Map<String, Object?> json) {
    final kindName = json['kind'];
    final accountId = json['accountId'];
    final remotePath = json['remotePath'];
    if (kindName is! String || accountId is! String || remotePath is! String) {
      return null;
    }
    final kind = TransferKind.values
        .where((k) => k.name == kindName)
        .cast<TransferKind?>()
        .firstWhere((k) => true, orElse: () => null);
    if (kind == null || accountId.isEmpty || remotePath.isEmpty) return null;
    return TransferRestoreSpec(
      kind: kind,
      accountId: accountId,
      remotePath: remotePath,
      localPath: json['localPath'] is String ? json['localPath']! as String : '',
      fileName: json['fileName'] is String ? json['fileName']! as String : '',
      subDir: json['subDir'] is String ? json['subDir']! as String : null,
      overwrite: json['overwrite'] == true,
      title: json['title'] is String ? json['title']! as String : '',
      subtitle: json['subtitle'] is String ? json['subtitle']! as String : '',
      totalBytes: json['totalBytes'] is int ? json['totalBytes']! as int : -1,
    );
  }
}

enum TransferStatus {
  queued,
  running,
  done,
  failed,
  canceled,

  /// 用户主动暂停（285 P2）。与 [canceled] 的区别是**这条还在队列里**：
  /// 断点/`.part` 保留、恢复时接着传，重启后也恢复成暂停态而不是自动开跑。
  paused,
}

/// 单个传输任务。UI 直接监听 [TransferQueue] 的 ChangeNotifier 刷新。
class TransferTask {
  TransferTask._({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.totalBytes,
    this.spec,
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

  /// 可恢复描述（284 P1）；为 null 的任务不入库（例如临时/一次性的传输）。
  TransferRestoreSpec? spec;

  /// 这一条是从上次落盘恢复回来的（UI 标「已恢复」）。
  bool restored = false;

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

  /// 是否处于暂停（排队中都可能被暂停：还没开跑的直接不进 `running`）。
  bool get isPaused => status == TransferStatus.paused;
}

/// 执行体：返回产物（下载为本地路径 String）；进度通过 onProgress 上报。
typedef TransferRunner = Future<Object?> Function(
  TransferCancelToken cancel,
  void Function(int received, int total) onProgress,
);

/// 有界并发的传输队列（默认 [kMaxConcurrentTransfers] 个任务同时在跑）。
class TransferQueue extends ChangeNotifier {
  TransferQueue({
    this.retryDelay,
    int? maxConcurrent,
    TransferQueueStore? store,
    TransferKeepAlive? keepAlive,
  })  : maxConcurrent = maxConcurrent ?? kMaxConcurrentTransfers,
        _store = store ?? TransferQueueStore(),
        _keepAlive = keepAlive ?? TransferKeepAlive(),
        assert((maxConcurrent ?? kMaxConcurrentTransfers) >= 1,
            '并发数至少为 1');

  /// 固定重试等待（测试传 Duration.zero 让退避不占用测试时间）。
  ///
  /// null（生产默认）时按 [kTransferRetryDelays] 退避，并尊重服务端的
  /// `Retry-After`；给了值则一律用该值（但 `Retry-After` 更长时仍取更长）。
  final Duration? retryDelay;

  /// 同时最多在跑的任务数（见 [kMaxConcurrentTransfers]）。
  final int maxConcurrent;

  /// 任务元数据落盘（284 P1）。
  final TransferQueueStore _store;

  /// 传输期间的前台保活（284 P1）。
  final TransferKeepAlive _keepAlive;

  // ------------------------------------------------- 网络条件闸门（287 P1）

  /// 网络策略，默认仅 Wi-Fi（见 [TransferNetworkPolicy]）。
  TransferNetworkPolicy _networkPolicy = TransferNetworkPolicy.wifiOnly;

  /// "移动网络上仍要传一次"的临时放行；**网络类型一变就清掉** ——
  /// "这次"指的是当时那次网络，换了网络要重新问。
  bool _mobileOverride = false;

  /// 原生推来的当前网络类型。
  ///
  /// null = **完全没有情报**（通道不存在/读不出来）→ 队列不拦，否则没有这个通道的
  /// 平台会被静默停死；一旦拿到真实读数（哪怕是不认识的类型）就按策略判定。
  NetworkKind? _networkKind;

  /// 界面展示用：没有情报时显示"未知网络"。
  NetworkKind get currentNetworkKind => _networkKind ?? NetworkKind.other;

  TransferNetworkPolicy get networkPolicy => _networkPolicy;

  /// 现在是否因为网络条件被闸住（含"没网"）。
  ///
  /// 只在**有情报**时判定：[NetworkKind.none] 与不认识的类型都会被拦住，但"完全
  /// 读不到"（[_networkKind] 为 null）不拦 —— 见 [_networkKind] 的说明。
  bool get networkBlocked {
    final kind = _networkKind;
    if (kind == null) return false;
    return !networkAllowsTransfer(_networkPolicy, kind) && !_mobileOverride;
  }

  /// 正在等网络的任务数（传输面板横幅用）。
  int get waitingForNetworkCount => networkBlocked
      ? _tasks.where((t) => t.status == TransferStatus.queued).length
      : 0;

  final List<TransferTask> _tasks = [];
  int _running = 0;
  int _seq = 0;
  DateTime _lastProgressNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// 上一次更新通知的时间（进度类更新按 1s 节流，别每帧都写）。
  DateTime _lastKeepAliveUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  /// 前台保活是否已经起了（幂等，避免反复 start）。
  bool _keepAliveRunning = false;

  Future<void>? _persistInFlight;

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
    TransferRestoreSpec? spec,
  }) {
    _seq += 1;
    final task = TransferTask._(
      id: 't${DateTime.now().microsecondsSinceEpoch}_$_seq',
      kind: kind,
      title: title,
      subtitle: subtitle,
      totalBytes: totalBytes,
      spec: spec,
    );
    task.runner = runner;
    task.onFinished = onFinished;
    _tasks.insert(0, task);
    notifyListeners();
    _persist(); // 入队就落盘：紧接着被杀也不会丢这一条
    _pump();
    return task;
  }

  /// 暂停：在跑的那次传输会被取消（断点保留），排队中的直接转暂停。
  ///
  /// 先改状态再取消 token —— 否则 [_run] 的取消分支会把它记成"已取消"。
  bool pause(TransferTask task) {
    if (task.status != TransferStatus.queued &&
        task.status != TransferStatus.running) {
      return false;
    }
    task.status = TransferStatus.paused;
    task.cancelToken.cancel();
    task.retryAttempt = 0;
    notifyListeners();
    _persist();
    _syncKeepAlive();
    return true;
  }

  /// 暂停所有能暂停的（在跑 + 排队中）。
  int pauseAll() {
    var n = 0;
    for (final task in _tasks) {
      if (pause(task)) n += 1;
    }
    return n;
  }

  /// 继续：把暂停的放回队列（token 一次性，必须复位，见 [retry] 的注释）。
  bool resume(TransferTask task) {
    if (task.status != TransferStatus.paused) return false;
    task.cancelToken.reset();
    task.status = TransferStatus.queued;
    task.errorMessage = null;
    notifyListeners();
    _persist();
    _pump();
    return true;
  }

  int resumeAll() {
    var n = 0;
    for (final task in _tasks.reversed) {
      if (resume(task)) n += 1;
    }
    return n;
  }

  int get pausedCount =>
      _tasks.where((t) => t.status == TransferStatus.paused).length;

  void clearFinished() {
    // 暂停的任务是"用户还留着、待会要继续"的，不属于"已结束"，不能一起清掉。
    _tasks.removeWhere(
      (t) => !t.isActive && t.status != TransferStatus.paused,
    );
    notifyListeners();
    _persist();
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
    task.restored = false; // 用户主动重试：不再算"恢复回来的"
    notifyListeners();
    _persist();
    _pump();
    return true;
  }

  /// 一键重试**所有**失败任务（284 P5），返回真正被重试的条数。
  ///
  /// 复用 [retry]：它已经处理了"状态必须 failed、token 复位、计数归零"这几件
  /// 容易漏的事（token 不复位会被立刻判成取消）。批量重试只是把它套在列表上。
  int retryAllFailed() {
    var count = 0;
    // 先收集再重试：retry 会 notifyListeners + 触发 _pump，边遍历边改列表不安全。
    final failed = _tasks
        .where((t) => t.status == TransferStatus.failed)
        .toList(growable: false);
    for (final task in failed) {
      if (retry(task)) count += 1;
    }
    return count;
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

  // --------------------------------------------- 网络条件闸门（287 P1）

  /// 设置网络策略。换档会清掉临时放行，并按新档位重新起跑。
  void setNetworkPolicy(TransferNetworkPolicy policy) {
    if (policy == _networkPolicy) return;
    _networkPolicy = policy;
    _mobileOverride = false;
    notifyListeners();
    _pump();
  }

  /// 原生推来的网络变化（Wi-Fi 连上/断开、移动网络开关）。
  ///
  /// 类型一变就清掉临时放行：用户当时点"仍要传"针对的是**那一次**网络。
  void setNetworkState(NetworkKind kind) {
    if (kind == _networkKind) return;
    _networkKind = kind;
    _mobileOverride = false;
    notifyListeners();
    _pump();
  }

  /// 用户在移动网络上点了"仍要传一次"。
  void allowMobileOnce() {
    if (_mobileOverride) return;
    _mobileOverride = true;
    notifyListeners();
    _pump();
  }

  /// 拉起能跑的任务，直到达到并发上限。
  ///
  /// 本方法**不含 await**（[TransferTask.runner] 的等待在 [_run] 里），所以不存在
  /// 重入；任务结束时由完成回调再调一次，把腾出来的位置补上——不需要"是否正在
  /// pump"的开关（原来那个开关只能表达"串行"）。
  void _pump() {
    while (_running < maxConcurrent) {
      // 网络条件不允许就整队停住：任务留在队列里（**不标 running、不挂保活**），
      // 等 setNetworkState / allowMobileOnce / setNetworkPolicy 再 pump ——
      // 这样面板上看到的是"等待 Wi-Fi"，而不是被标成在跑然后失败。
      if (networkBlocked) return;
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
      // 开始跑就挂上前台服务：长任务期间进程不能被系统回收。
      _syncKeepAlive();
      unawaited(
        _run(next).whenComplete(() {
          _running -= 1;
          _syncKeepAlive();
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
              _syncKeepAlive(progressOnly: true);
            }
          },
        );
        current.result = result;
        current.status = TransferStatus.done;
        break;
      } on TransferCanceledException {
        // 暂停也走取消这条路（传输层只认取消），但状态要留在 paused。
        if (current.status != TransferStatus.paused) {
          current.status = TransferStatus.canceled;
        }
        break;
      } catch (e) {
        if (current.status == TransferStatus.paused) break;
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
    _persist();
    _syncKeepAlive();
    current.onFinished?.call(current);
  }

  // ------------------------------------------------- 落盘与恢复（284 P1）

  /// 当前该落盘的记录：只落"没结束"的（queued/running/failed）。
  ///
  /// 已完成的（结果有效）与已取消的（用户主动放弃）不落：下次启动看到它们
  /// 既没用也容易让人误以为"还在跑"。失败的要连失败原因一起落 —— 否则恢复回来
  /// 会显示成"上次未完成"，用户看不到真正的原因。
  List<Map<String, Object?>> _pendingRecords() => [
        for (final task in _tasks)
          if (task.spec != null &&
              task.status != TransferStatus.done &&
              task.status != TransferStatus.canceled)
            {
              ...task.spec!.toJson(),
              'failed': task.status == TransferStatus.failed,
              // 暂停态要单独标：恢复时不能自动开跑（否则用户暂停的东西一重启就跑）。
              'paused': task.status == TransferStatus.paused,
              if (task.errorMessage != null) 'errorMessage': task.errorMessage,
            },
      ];

  /// 写盘：**不节流**。
  ///
  /// 曾经按 1s 节流，结果"任务已完成"这次状态变化也被吞掉 —— 盘里留着一条已经
  /// 传完的记录，下次启动会当成未完成再跑一遍（测试逮到的真 bug）。落盘只在
  /// 生命周期变化时发生（入队/结束/重试/清理），进度根本不入库，所以没有节流的必要。
  void _persist() {
    final records = _pendingRecords();
    _persistInFlight = _store
        .save(records)
        .catchError((Object e) {
      // 落盘失败不影响传输本身。
      AppLogger.instance.logTo(
        LogChannel.storage,
        '传输队列落盘失败: $e',
        level: LogLevel.debug,
      );
    });
  }

  /// 测试用：等最后一次落盘写完（生产里是 fire-and-forget）。
  @visibleForTesting
  Future<void> debugAwaitPersistence() async => _persistInFlight;

  /// 当前真正在跑的个数（测试用）：[pause] 会把状态立刻改成 paused，但那次传输
  /// 还要等它自己抛取消才算收尾 —— 想断言"暂停已生效"就得看这个，不是看状态。
  int get debugRunningCount => _running;

  /// 恢复上次未完成的传输（284 P1），返回恢复出几条。
  ///
  /// [factory] 用描述重建 runner（service 提供）；[canRestore] 用来过滤已经没法跑的
  /// 记录（账户被删了、本地文件不在了……），返回 false 的直接丢弃。
  ///
  /// 恢复策略：
  /// - 上次"排队中/在传"的 → 重新排队（并标 [TransferTask.restored]，UI 显示「已恢复」）；
  /// - 上次"失败"的 → 恢复成失败态（让用户看到并可以「全部重试」），不自动重跑，
  ///   免得一个必失败的任务每次启动都白跑一遍网络。
  /// - 上次"暂停"的 → 恢复成暂停态（285 P2），等用户点继续。
  /// - 队列里已经有同一件事（同 dedupeKey）→ 跳过，不重复。
  Future<int> restorePending({
    required TransferRunner Function(TransferRestoreSpec spec) factory,
    Future<bool> Function(TransferRestoreSpec spec)? canRestore,
  }) async {
    final records = await _store.load();
    if (records.isEmpty) return 0;

    final existing = {for (final t in _tasks) if (t.spec != null) t.spec!.dedupeKey};
    var restored = 0;
    // 落盘是"新的在前"，恢复时按同一顺序入队（保持用户看到的顺序）。
    for (final record in records) {
      final spec = TransferRestoreSpec.tryParse(record);
      if (spec == null) continue;
      if (existing.contains(spec.dedupeKey)) continue;
      if (canRestore != null && !await canRestore(spec)) continue;

      final failed = record['failed'] == true;
      final paused = record['paused'] == true;
      _seq += 1;
      final task = TransferTask._(
        id: 'r${DateTime.now().microsecondsSinceEpoch}_$_seq',
        kind: spec.kind,
        title: spec.title.isEmpty ? _baseName(spec) : spec.title,
        subtitle: spec.subtitle,
        totalBytes: spec.totalBytes,
        spec: spec,
      )..restored = true;
      task.runner = factory(spec);
      if (paused) {
        // 用户暂停过的：恢复成暂停态，等他自己点继续（不自动开跑）。
        task.status = TransferStatus.paused;
      } else if (failed) {
        task.status = TransferStatus.failed;
        task.errorMessage = record['errorMessage'] is String
            ? record['errorMessage']! as String
            : '上次未完成';
      }
      _tasks.add(task);
      existing.add(spec.dedupeKey);
      restored += 1;
    }
    if (restored == 0) {
      // 一条都没恢复出来也要重写一次：被 canRestore 过滤掉的记录（账户已删、
      // 源文件已不在）不能永远躺在盘里，每次启动都被翻出来再丢一次。
      _persist();
      return 0;
    }
    notifyListeners();
    _persist();
    _pump();
    return restored;
  }

  String _baseName(TransferRestoreSpec spec) {
    final path = spec.kind == TransferKind.upload
        ? spec.localPath
        : spec.remotePath;
    final idx = path.lastIndexOf('/');
    final name = idx >= 0 ? path.substring(idx + 1) : path;
    return name.isEmpty ? '未命名任务' : name;
  }

  // ------------------------------------------------- 前台保活（284 P1）

  /// 有在跑的任务就起前台服务（并在进度变化时更新通知），跑完就撤。
  ///
  /// [progressOnly] 为 true 时只更新通知文案，不做 start/stop —— 进度回调很密，
  /// 每一步都判断一次状态没有意义，而且 1s 节流后也够。
  void _syncKeepAlive({bool progressOnly = false}) {
    final active = activeCount;
    if (!progressOnly) {
      if (active > 0 && !_keepAliveRunning) {
        _keepAliveRunning = true;
        unawaited(
          _keepAlive.start(title: 'Box 传输中', text: _keepAliveText()),
        );
        return;
      }
      if (active == 0 && _keepAliveRunning) {
        _keepAliveRunning = false;
        unawaited(_keepAlive.stop());
        return;
      }
    }
    if (active == 0 || !_keepAliveRunning) return;
    final now = DateTime.now();
    if (now.difference(_lastKeepAliveUpdate).inMilliseconds < 1000) return;
    _lastKeepAliveUpdate = now;
    unawaited(_keepAlive.update(text: _keepAliveText()));
  }

  String _keepAliveText() {
    final active = _tasks.where((t) => t.isActive).toList(growable: false);
    if (active.isEmpty) return '正在收尾…';
    final done = _tasks.where((t) => t.status == TransferStatus.done).length;
    final totalProgress = active
        .map((t) => t.progress)
        .fold<double>(0, (sum, p) => sum + p);
    final percent = (totalProgress / active.length * 100).round();
    return '正在传输 ${active.length} 项 · 已完成 $done 项 · $percent%';
  }

  @override
  void dispose() {
    if (_keepAliveRunning) {
      _keepAliveRunning = false;
      unawaited(_keepAlive.stop());
    }
    super.dispose();
  }
}