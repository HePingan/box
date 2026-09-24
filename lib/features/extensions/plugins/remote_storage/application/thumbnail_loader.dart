// 缩略图取用器：缓存 + 并发上限 + 同键去重。
//
// 三个约束，都是列表滚动时会真踩到的：
// 1. **缓存**（内存/磁盘，见 RemoteThumbnailCache）：滚出去再滚回来不重复下载。
// 2. **并发上限**：一屏十几张图如果一起发请求，会把带宽占满、把用户主动发起的
//    上传/下载挤慢。缩略图是"顺便看看"，不该压过用户正在做的事。
// 3. **同键去重**：同一张图可能因为列表重建/滚动来回而同时被请求两次
//    （两个 widget 实例各发一次），去重后只发一次。
//
// 取不到一律返回 null：列表里绝不因为缩略图失败而显示错误——回退通用图标即可。

import 'dart:async';
import 'dart:typed_data';

import 'package:box/utils/app_logger.dart';
import 'package:box/utils/log_channels.dart';

import '../data/remote_thumbnail_cache.dart';
import '../domain/remote_storage_models.dart';

class ThumbnailLoader {
  ThumbnailLoader({
    required this.cache,
    this.maxConcurrent = kThumbnailMaxConcurrent,
  });

  final RemoteThumbnailCache cache;
  final int maxConcurrent;

  final Map<String, Future<Uint8List?>> _inFlight = {};
  final List<Completer<void>> _waiting = [];
  int _active = 0;

  /// 当前在途的取图数（测试用）。
  int get activeCount => _active;

  /// 取缩略图：[fetch] 只在缓存未命中时被调用，且同一 [key] 同时只调一次。
  Future<Uint8List?> load(
    String key,
    Future<Uint8List?> Function() fetch,
  ) async {
    final cached = await cache.get(key);
    if (cached != null) return cached;

    final existing = _inFlight[key];
    if (existing != null) return existing;

    final future = _run(key, fetch);
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<Uint8List?> _run(
    String key,
    Future<Uint8List?> Function() fetch,
  ) async {
    await _acquire();
    try {
      final bytes = await fetch();
      if (bytes == null || bytes.isEmpty) return null;
      await cache.put(key, bytes);
      return bytes;
    } catch (e) {
      // 列表里的缩略图失败不是错误状态：记一条调试日志，回退图标。
      AppLogger.instance.logTo(
        LogChannel.storage,
        '缩略图获取失败（$key）: $e',
        level: LogLevel.debug,
      );
      return null;
    } finally {
      _release();
    }
  }

  Future<void> _acquire() async {
    if (_active < maxConcurrent) {
      _active += 1;
      return;
    }
    // 排队等待**槽位转交**（见 _release）：醒来时槽位已经算在自己头上了，
    // 这里不能再自增——否则"释放时唤醒"与"新请求直接通过"会同时发生，把并发数
    // 顶到 maxConcurrent 之上。
    final completer = Completer<void>();
    _waiting.add(completer);
    await completer.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      final next = _waiting.removeAt(0);
      if (!next.isCompleted) next.complete();
      return;
    }
    _active -= 1;
  }

  /// 账户切换/退出时清内存缓存（磁盘留着跨会话用）。
  void clearMemory() => cache.clearMemory();
}
