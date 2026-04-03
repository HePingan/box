import 'models.dart';

abstract class VideoSourceProvider {
  String get key;
  String get name;

  bool get enabled => true;

  /// 搜索站点内容
  Future<List<VideoItem>> search(String keyword);

  /// 拉详情并返回多线路结构
  Future<VideoDetail> fetchDetail(VideoItem item);
}