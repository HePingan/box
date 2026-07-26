import 'dart:async';

import 'package:flutter/material.dart';

import '../models/video_download_task.dart';
import '../services/video_download_gateway.dart';
import '../services/video_download_repository.dart';

class VideoDownloadController extends ChangeNotifier {
  VideoDownloadController({
    required VideoDownloadRepository repository,
    required VideoDownloadGateway gateway,
  }) : _repository = repository,
       _gateway = gateway;

  final VideoDownloadRepository _repository;
  final VideoDownloadGateway _gateway;

  List<VideoDownloadTask> _tasks = [];
  List<VideoDownloadTask> get tasks => List.unmodifiable(_tasks);

  String? _message;
  String? get message => _message;

  Timer? _pollTimer;
  static const Duration _pollInterval = Duration(seconds: 1);

  /// 加载本地持久化任务，并启动平台进度轮询。
  Future<void> load() async {
    _tasks = await _repository.loadAll();
    notifyListeners();
    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollSnapshots());
  }

  Future<void> _pollSnapshots() async {
    try {
      final raw = await _gateway.snapshots();
      if (raw.isNotEmpty) {
        await applyPlatformSnapshots(raw);
      }
    } catch (_) {
      // 静默忽略轮询失败
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  /// Create a native task first, then immediately persist and publish a local
  /// queued snapshot. This gives the UI an observable state even before the
  /// first native (three-second) progress poll arrives.
  Future<bool> enqueue(VideoDownloadTask task) async {
    if (task.mediaUrl.trim().isEmpty) {
      _setMessage('下载地址为空，无法创建任务');
      return false;
    }
    // Only allow HTTPS URLs for security
    if (!task.mediaUrl.startsWith('https://')) {
      _setMessage('仅支持 HTTPS 地址');
      return false;
    }
    try {
      await _gateway.enqueue(task);
      final queued = task.copyWith(status: VideoDownloadStatus.queued);
      await _repository.save(queued);
      _tasks = await _repository.loadAll();
      notifyListeners();
      unawaited(_pollSnapshots());
      return true;
    } catch (e) {
      _setMessage('下载任务创建失败');
      return false;
    }
  }

  Future<void> pause(String id) async {
    try {
      await _gateway.pause(id);
      await _updateStatus(id, VideoDownloadStatus.paused);
    } catch (e) {
      _setMessage('暂停失败');
    }
  }

  Future<void> resume(String id) async {
    try {
      await _gateway.resume(id);
      // Native may set "downloading" or "queued" depending on concurrency slot availability.
      // We let the poll cycle apply the real status from snapshots rather than forcing a local value.
      unawaited(_pollSnapshots());
    } catch (e) {
      _setMessage('恢复失败');
    }
  }

  Future<void> cancel(String id) async {
    try {
      await _gateway.cancel(id);
      await _updateStatus(id, VideoDownloadStatus.cancelled);
    } catch (e) {
      _setMessage('取消失败');
    }
  }

  Future<void> remove(String id) async {
    try {
      await _gateway.remove(id);
      await _repository.delete(id);
      _tasks = await _repository.loadAll();
      notifyListeners();
    } catch (e) {
      _setMessage('删除失败');
    }
  }

  /// Apply progress snapshots from the native download engine.
  Future<void> applyPlatformSnapshots(List<Map<String, dynamic>> raw) async {
    for (final item in raw) {
      final id = item['id'] as String?;
      if (id == null || id.isEmpty) continue;
      final statusRaw = item['status'] as String? ?? '';
      final downloadedBytes = item['downloadedBytes'] as int? ?? 0;
      final totalBytes = item['totalBytes'] as int? ?? 0;
      final downloadSpeedBytesPerSecond =
          item['downloadSpeedBytesPerSecond'] as int? ?? 0;
      final localPath = item['localPath'] as String? ?? '';
      final sourceName = item['sourceName'] as String? ?? '';
      final episodeName = item['episodeName'] as String? ?? '';
      final errorMessage = item['errorMessage'] as String? ?? '';

      // native 的 sharedTasks 是进程内静态存储，完成后仍会残留到进程结束。
      // 若快照里出现本地 _tasks 中不存在的 ID（例如已从 Hive 删除、或跨会话残留），
      // 直接跳过而非抛错——否则单条未知任务会中断整轮更新，让已知任务进度也刷不出来。
      final index = _tasks.indexWhere((t) => t.id == id);
      if (index < 0) continue;

      final updated = _tasks[index].copyWith(
        sourceName: sourceName.isEmpty ? null : sourceName,
        episodeName: episodeName.isEmpty ? null : episodeName,
        status: VideoDownloadStatusValue.parse(statusRaw),
        downloadedBytes: downloadedBytes,
        totalBytes: totalBytes,
        downloadSpeedBytesPerSecond: downloadSpeedBytesPerSecond,
        localPath: localPath,
        errorMessage: errorMessage,
      );

      await _repository.save(updated);
    }
    await load();
  }

  Future<void> _updateStatus(String id, VideoDownloadStatus status) async {
    final existing = _tasks.firstWhere(
      (t) => t.id == id,
      orElse: () => throw StateError('Unknown task $id'),
    );
    final updated = existing.copyWith(status: status);
    await _repository.save(updated);
    await load();
  }

  void _setMessage(String msg) {
    _message = msg;
    notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_message == msg) {
        _message = null;
        notifyListeners();
      }
    });
  }
}
