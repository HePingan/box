import '../video-Pro/config/video_proxy_config.dart';

/// 全局代理包裹函数：让一切资源走统一配置的代理节点。
String wrapWithProxy(String rawUrl) {
  final url = rawUrl.trim();
  if (url.isEmpty || !url.startsWith('http')) return url;

  final proxyUri = Uri.tryParse(kDefaultVideoProxyHost);
  final uri = Uri.tryParse(url);
  if (proxyUri != null &&
      uri != null &&
      uri.host.toLowerCase() == proxyUri.host.toLowerCase()) {
    return url; // 防止重复套娃
  }

  return '$kDefaultVideoProxyHost/$url';
}
