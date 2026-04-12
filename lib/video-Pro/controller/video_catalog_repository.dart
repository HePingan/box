import '../../utils/app_logger.dart';
import '../models/video_category.dart';
import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../services/video_api_service.dart';

/// 视频目录数据仓库
///
/// 这个类负责把 VideoApiService 和 Controller 隔开。
/// 如果你的 VideoApiService 方法名和我这里假设的不一致，
/// 只需要改这个文件，不要动 controller。
class VideoCatalogRepository {
  const VideoCatalogRepository({
    this.pageSize = 20,
  });

  /// 用于判断是否还有下一页的保守估计
  final int pageSize;

  /// 加载所有片源
  Future<List<VideoSource>> loadSources(String catalogUrl) async {
    try {
      final sources = await VideoApiService.fetchSources(catalogUrl);
      return sources;
    } catch (e, st) {
      AppLogger.instance.logError(e, st, 'VIDEO_CATALOG');
      return <VideoSource>[];
    }
  }

  /// 加载某个片源下的分类
  ///
  /// 优先使用 detailUrl，没有就退回 url。
  Future<List<VideoCategory>> loadCategories(VideoSource source) async {
    final categoryUrl = source.detailUrl.trim().isNotEmpty
        ? source.detailUrl
        : source.url;

    if (categoryUrl.trim().isEmpty) {
      return <VideoCategory>[];
    }

    try {
      final categories = await VideoApiService.fetchCategories(categoryUrl);
      return categories;
    } catch (e, st) {
      AppLogger.instance.logError(e, st, 'VIDEO_CATALOG');
      return <VideoCategory>[];
    }
  }

  /// 加载某个片源的视频列表
  ///
  /// typeId = null 时表示“全部”
  Future<List<VodItem>> loadVideos(
    VideoSource source, {
    required int? typeId,
    required int page,
  }) async {
    final listUrl = source.url.trim().isNotEmpty ? source.url : source.detailUrl;

    if (listUrl.trim().isEmpty) {
      return <VodItem>[];
    }

    try {
      final videos = await VideoApiService.fetchVideos(
        listUrl,
        typeId,
        page,
      );
      return videos;
    } catch (e, st) {
      AppLogger.instance.logError(e, st, 'VIDEO_CATALOG');
      return <VodItem>[];
    }
  }
}