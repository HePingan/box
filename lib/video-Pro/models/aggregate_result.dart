import 'video_source.dart';
import 'vod_item.dart';

/// 聚合搜索结果项：绑定源站与视频条目
class AggregateResult {
  final VideoSource source;
  final VodItem video;

  const AggregateResult({
    required this.source,
    required this.video,
  });
}