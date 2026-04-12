import '../../models/video_source.dart';
import '../../models/vod_item.dart';

// ✅ 彻底干掉 video_api_service 的引入，斩断网络并发风暴的根源！

/// 搜索页封面解析：仅处理本地字符串
String? resolveSearchImageUrl(
  String? rawUrl, {
  required VideoSource source,
}) {
  if (rawUrl == null) return null;

  var url = rawUrl.trim().replaceAll('\\', '');
  if (url.isEmpty) return null;

  if (url.startsWith('//')) {
    return 'https:$url';
  }

  final parsed = Uri.tryParse(url);
  if (parsed != null && parsed.hasScheme) {
    return url;
  }

  final baseUrls = <String>[
    source.detailUrl.trim(),
    source.url.trim(),
  ];

  for (final base in baseUrls) {
    if (base.isEmpty) continue;

    final baseUri = Uri.tryParse(base);
    if (baseUri == null || !baseUri.hasScheme) continue;

    try {
      return baseUri.resolve(url).toString();
    } catch (_) {}
  }

  return url;
}

// 🚀 终极极速版：改为同步方法，不再返回 Future
String? loadSearchVideoCover(VodItem video, VideoSource source) {
  final direct = resolveSearchImageUrl(video.vodPic, source: source);
  if (direct != null && direct.isNotEmpty) {
    return direct;
  }
  
  // ⛔️ 列表无图就显示占位图，绝不能在滑动时发起网络请求！
  return null;
}