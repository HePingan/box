// 下一话预取：本话快读完时，先把下一话**开头几张**图落到本地缓存。
//
// 为什么只取开头几张：整话最多 209 张 ≈ 10MB —— 全取既费流量，又会把刚设的图片缓存
// 上限（300MB）顶满，把"上限 + 淘汰"变成常驻噪音。开头几张正好盖住"翻到下一话第一屏"
// 那段空档（用户体感就是这里卡一下）。
//
// 纪律：预取是**顺手**，不是阅读的前提 —— 任何一步失败都安静收场（真读那一话时会再取
// 一次，那时候才该报错）；同一话不重复打接口，也不重复下图。

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'comic_image_cache.dart';
import 'comic_online_service.dart';

class ComicChapterPrefetcher {
  ComicChapterPrefetcher({
    required this.loadImages,
    required this.cache,
    this.leadingImages = 3,
  });

  /// 取某一话的图片地址列表（生产里就是 `ComicOnlineService.chapterImages`）。
  ///
  /// 传闭包而不是服务对象：换源 / 换令牌会把 service 整个换掉，闭包每次读最新的那个。
  final Future<List<String>> Function(String chapterUrl) loadImages;

  /// 图片缓存（带请求头的那个，`ComicImageCache`）。
  final ComicImageCache cache;

  /// 预取开头几张。
  final int leadingImages;

  /// 已经预取成功的章节（同一话不再打接口）。
  final Set<String> _done = <String>{};

  /// 正在预取中的章节 → 任务（并发触发只跑一次）。
  final Map<String, Future<void>> _inFlight = <String, Future<void>>{};

  @visibleForTesting
  bool get hasPrefetchedAnything => _done.isNotEmpty;

  /// 预取 [chapters] 里第 [currentIndex] 话的**下一话**。
  ///
  /// 没有下一话（最后一话）就什么都不做 —— 不抛、不提示。
  Future<void> prefetchNext(List<ComicChapterRef> chapters, int currentIndex) {
    final nextIndex = currentIndex + 1;
    if (nextIndex < 0 || nextIndex >= chapters.length) {
      return Future<void>.value();
    }
    final url = chapters[nextIndex].url;
    if (_done.contains(url)) return Future<void>.value();
    final running = _inFlight[url];
    if (running != null) return running;
    final job = _run(url);
    _inFlight[url] = job;
    return job;
  }

  Future<void> _run(String chapterUrl) async {
    try {
      final images = await loadImages(chapterUrl);
      if (images.isEmpty) return;
      for (final url in images.take(leadingImages)) {
        try {
          // 低优先级：预取是顺手，不能占着并发名额让**正在读的这一话**排队
          // （2026-10-01：预取和正文共用同一个缓存实例 → 同一个并发池）。
          await cache.fetch(url, lowPriority: true);
        } on Object {
          // 某张没下来不中断其余几张：真读那一话时这张还会再取一次（那次会如实报错）。
        }
      }
      _done.add(chapterUrl);
    } on Object {
      // 目录/图列表取不到（网络、规则、源被挡）都在这里收场：预取失败不该影响正在读的这一话。
    } finally {
      _inFlight.remove(chapterUrl);
    }
  }
}
