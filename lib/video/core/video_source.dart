import 'models.dart';

abstract class VideoSource {
  /// 数据源名称
  String get sourceName;

  /// 分类
  List<VideoCategory> get categories;

  /// 搜索视频
  Future<List<VideoItem>> searchVideos(String keyword, {int page = 1});

  /// 根据分类路径获取视频列表
  Future<List<VideoItem>> fetchByPath(String path, {int page = 1});

  /// 获取详情和播放线路
  Future<VideoDetail> fetchDetail({
    required VideoItem item,
  });
}