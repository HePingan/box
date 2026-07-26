const String kDefaultVideoProxyHost = 'https://proxy.shuabu.eu.org';
const String kDefaultVideoProxyPrefix = '$kDefaultVideoProxyHost/?url=';
const String kDefaultVideoCatalogUrlFormat0 =
    '$kDefaultVideoProxyHost?format=0&source=jin18';
const String kDefaultVideoCatalogUrlFormat1 =
    '$kDefaultVideoProxyHost?format=1&source=jin18';

class VideoProxyConfig {
  final bool enabled;
  final bool mediaEnabled;
  final String proxyPrefix;

  const VideoProxyConfig({
    this.enabled = true,
    this.mediaEnabled = false,
    this.proxyPrefix = kDefaultVideoProxyPrefix,
  });

  VideoProxyConfig copyWith({
    bool? enabled,
    bool? mediaEnabled,
    String? proxyPrefix,
  }) {
    final trimmedPrefix = proxyPrefix?.trim();
    return VideoProxyConfig(
      enabled: enabled ?? this.enabled,
      mediaEnabled: mediaEnabled ?? this.mediaEnabled,
      proxyPrefix: trimmedPrefix == null || trimmedPrefix.isEmpty
          ? this.proxyPrefix
          : trimmedPrefix,
    );
  }

  bool isProxyUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    final proxyUri = Uri.tryParse(proxyPrefix.trim());
    return uri != null &&
        proxyUri != null &&
        uri.host.toLowerCase() == proxyUri.host.toLowerCase();
  }

  /// 已验证被当前转发服务拦截、但直连标准 VOD 接口正常的源。
  ///
  /// 这不是“关闭代理”：只有命中这些确定的 host 时才直连；其他源仍完全
  /// 沿用全局代理策略。新增前必须完成 分类→列表→详情→播放 的实测。
  static const Set<String> _directVodApiHosts = {'p2100.net'};

  bool _shouldUseDirectVodApi(String url) {
    final target = Uri.tryParse(unwrapTargetUrl(url));
    if (target == null || target.host.isEmpty) return false;
    return _directVodApiHosts.contains(target.host.toLowerCase());
  }

  String wrapWithProxy(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return trimmed;
    if (_shouldUseDirectVodApi(trimmed)) return trimmed;
    if (trimmed.startsWith(proxyPrefix)) return trimmed;
    if (isProxyUrl(trimmed)) return trimmed;
    return '$proxyPrefix${Uri.encodeComponent(trimmed)}';
  }

  /// 把裸域名自动补成标准 VOD 接口：
  /// https://example.com  -> https://example.com/api.php/provide/vod
  String normalizeProvideVodEndpoint(String baseUrl) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) return trimmed;

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return trimmed;

    if (uri.path.contains('/api.php/provide/vod')) {
      return trimmed;
    }

    // 只对“纯根域名”自动补接口，避免破坏代理类 URL
    if ((uri.path.isEmpty || uri.path == '/') && uri.queryParameters.isEmpty) {
      return uri.replace(path: '/api.php/provide/vod').toString();
    }

    return trimmed;
  }

  /// 先补成标准 VOD 接口，再按需包代理。
  String buildVodBaseUrl(String baseUrl) {
    final normalized = normalizeProvideVodEndpoint(baseUrl.trim());
    if (normalized.isEmpty) return normalized;
    if (!enabled) return normalized;
    return wrapWithProxy(normalized);
  }

  /// 递归展开嵌套 url，用于推断真实目标站点。
  String unwrapTargetUrl(String url, {int maxDepth = 3}) {
    var current = url.trim();
    if (current.isEmpty) return current;

    for (var i = 0; i < maxDepth; i++) {
      final uri = Uri.tryParse(current);
      if (uri == null || !uri.hasScheme) break;

      final nested = uri.queryParameters['url'];
      if (nested == null || nested.trim().isEmpty) break;

      current = nested.trim();
    }

    return current;
  }

  /// 智能拼接 query：
  /// - 普通 URL：直接追加参数
  /// - 带 ?url=xxx 的嵌套代理/转发 URL：把参数追加到真正的内层目标地址
  String withQuery(String baseUrl, Map<String, String> params) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty || params.isEmpty) return trimmed;

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) {
      final separator = trimmed.contains('?') ? '&' : '?';
      final query = params.entries
          .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      return '$trimmed$separator$query';
    }

    final query = Map<String, String>.from(uri.queryParameters);
    final nestedTarget = query['url'];

    if (nestedTarget != null && nestedTarget.trim().isNotEmpty) {
      query['url'] = withQuery(nestedTarget, params);
      return uri.replace(queryParameters: query).toString();
    }

    query.addAll(params);
    return uri.replace(queryParameters: query).toString();
  }
}
