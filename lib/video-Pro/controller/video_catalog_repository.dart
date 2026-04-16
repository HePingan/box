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

  /// 加载所有片源
  Future<List<VideoSource>> loadSources(String catalogUrl) async {
    final url = catalogUrl.trim();
    if (url.isEmpty) return const <VideoSource>[];

    try {
      return await VideoApiService.fetchSources(url);
    } catch (e, st) {
      AppLogger.instance.logError(e, st, 'VIDEO_CATALOG');
      return const <VideoSource>[];
    }
  }

  /// 加载某个片源下的分类
  ///
  /// 优先使用 source.url，再用 source.detailUrl 兜底。
  Future<List<VideoCategory>> loadCategories(VideoSource source) async {
    for (final url in _candidateApiUrls(source)) {
      if (url.isEmpty) continue;

      try {
        final categories = await VideoApiService.fetchCategories(url);
        if (categories.isNotEmpty) return categories;
      } catch (e, st) {
        AppLogger.instance.logError(e, st, 'VIDEO_CATALOG');
      }
    }

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
    for (final url in _candidateApiUrls(source)) {
      if (url.isEmpty) continue;

      try {
        final videos = await VideoApiService.fetchVideos(
          url,
          typeId,
          page,
        );
        if (videos.isNotEmpty) return videos;
      } catch (e, st) {
        AppLogger.instance.logError(e, st, 'VIDEO_CATALOG');
      }
    }

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