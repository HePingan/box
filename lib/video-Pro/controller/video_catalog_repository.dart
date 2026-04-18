import 'package:flutter/foundation.dart';

import '../../utils/app_logger.dart';
import '../models/video_category.dart';
import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../services/video_api_service.dart';

/// 视频目录数据仓库
///
/// 负责把 VideoApiService 和 Controller 隔开。
class VideoCatalogRepository {
  const VideoCatalogRepository({
    this.pageSize = 20,
  });

  /// 用于判断是否还有下一页的保守估计
  final int pageSize;

  void _log(String message) {
    if (kDebugMode) {
      AppLogger.instance.log(message, tag: 'VIDEO_CATALOG');
    }
  }

  String _briefSource(VideoSource source) {
    return 'name=${source.name}, id=${source.id}, url=${source.url}, detail=${source.detailUrl}';
  }

  String _sampleCategories(List<VideoCategory> categories, {int limit = 5}) {
    if (categories.isEmpty) return '[]';
    return categories
        .take(limit)
        .map((e) => '${e.typeId}:${e.typeName}')
        .join(' | ');
  }

  String _sampleVideos(List<VodItem> videos, {int limit = 3}) {
    if (videos.isEmpty) return '[]';
    return videos
        .take(limit)
        .map((e) => '${e.vodId}:${e.vodName}:pic=${e.vodPic ?? "null"}')
        .join(' | ');
  }

  /// 加载所有片源
  Future<List<VideoSource>> loadSources(String catalogUrl) async {
    final url = catalogUrl.trim();
    if (url.isEmpty) {
      _log('[loadSources] skip empty catalogUrl');
      return const <VideoSource>[];
    }

    _log('[loadSources] start catalogUrl=$url');

    try {
      final sources = await VideoApiService.fetchSources(url);

      _log(
        '[loadSources] success count=${sources.length} '
        'sample=${sources.take(5).map((e) => e.name).join(" | ")}',
      );

      if (sources.isEmpty) {
        _log('[loadSources] empty result');
      }

      return sources;
    } catch (e, st) {
      AppLogger.instance.logError(e, st, 'VIDEO_CATALOG');
      _log('[loadSources] error=$e');
      return const <VideoSource>[];
    }
  }

  /// 加载某个片源下的分类
  ///
  /// 优先使用 source.url，再用 source.detailUrl 兜底。
  Future<List<VideoCategory>> loadCategories(VideoSource source) async {
    _log('[loadCategories] start source=${_briefSource(source)}');

    final candidates = _candidateApiUrls(source);
    _log('[loadCategories] candidates=${candidates.join(" | ")}');

    for (final url in candidates) {
      if (url.isEmpty) continue;

      _log('[loadCategories] try url=$url');

      try {
        final categories = await VideoApiService.fetchCategories(url);

        _log(
          '[loadCategories] result url=$url count=${categories.length} '
          'sample=${_sampleCategories(categories)}',
        );

        if (categories.isNotEmpty) {
          _log('[loadCategories] success on url=$url');
          return categories;
        }
      } catch (e, st) {
        AppLogger.instance.logError(e, st, 'VIDEO_CATALOG');
        _log('[loadCategories] error url=$url err=$e');
      }
    }

    _log('[loadCategories] fallback empty for source=${source.name}');
    return const <VideoCategory>[];
  }

  /// 加载某个片源的视频列表
  ///
  /// typeId = null 时表示“全部”
  /// 优先使用 source.url，再用 source.detailUrl 兜底
  Future<List<VodItem>> loadVideos(
    VideoSource source, {
    required int? typeId,
    required int page,
  }) async {
    _log(
      '[loadVideos] start source=${_briefSource(source)} '
      'typeId=${typeId?.toString() ?? "all"} page=$page',
    );

    final candidates = _candidateApiUrls(source);
    _log('[loadVideos] candidates=${candidates.join(" | ")}');

    for (final url in candidates) {
      if (url.isEmpty) continue;

      _log(
        '[loadVideos] try url=$url '
        'typeId=${typeId?.toString() ?? "all"} page=$page',
      );

      try {
        final videos = await VideoApiService.fetchVideos(
          url,
          typeId,
          page,
        );

        _log(
          '[loadVideos] result url=$url '
          'count=${videos.length} sample=${_sampleVideos(videos)}',
        );

        if (videos.isNotEmpty) {
          _log(
            '[loadVideos] success url=$url '
            'typeId=${typeId?.toString() ?? "all"} page=$page',
          );
          return videos;
        }
      } catch (e, st) {
        AppLogger.instance.logError(e, st, 'VIDEO_CATALOG');
        _log(
          '[loadVideos] error url=$url '
          'typeId=${typeId?.toString() ?? "all"} page=$page err=$e',
        );
      }
    }

    _log(
      '[loadVideos] fallback empty '
      'source=${source.name} typeId=${typeId?.toString() ?? "all"} page=$page',
    );
    return const <VodItem>[];
  }

  /// API 候选地址：优先 url，其次 detailUrl
  List<String> _candidateApiUrls(VideoSource source) {
    return _uniqueOrdered([
      source.url,
      source.detailUrl,
    ]);
  }

  /// 去重、清理空字符串、保留原顺序
  List<String> _uniqueOrdered(Iterable<String> urls) {
    final result = <String>[];
    final seen = <String>{};

    for (final raw in urls) {
      final url = raw.trim();
      if (url.isEmpty) continue;
      if (seen.contains(url)) continue;

      seen.add(url);
      result.add(url);
    }

    return result;
  }
}