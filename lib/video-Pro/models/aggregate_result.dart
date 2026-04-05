import 'video_source.dart';
import 'vod_item.dart';

/// 文件功能：聚合搜索结果项模型
/// 实现：将视频条目与其来源站(Source)绑定，方便点击时跳转至正确的源
class AggregateResult {
  final VideoSource source;
  final VodItem video;

  AggregateResult({required this.source, required this.video});
}