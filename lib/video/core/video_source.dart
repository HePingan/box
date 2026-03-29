import 'models.dart';

abstract class VideoSource {
  /// 数据源的名称
  String get sourceName;

  /// 该数据源支持的分类列表
  List<VideoCategory> get categories;

  /// 搜索视频
  Future<List<VideoItem>> searchVideos(String keyword, {int page = 1});

  /// 根据分类路径/条件获取视频列表
  Future<List<VideoItem>> fetchByPath(String path, {int page = 1});

  /// 获取视频详情和播放源
  Future<VideoDetail> fetchDetail({
    required String videoId,
    String? detailUrl,
  });
}