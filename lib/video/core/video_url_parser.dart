class ParsedEpisodeUrl {
  final String url;
  final Map<String, String> headers;

  const ParsedEpisodeUrl({
    required this.url,
    required this.headers,
  });
}

class PlayerRequestAttempt {
  final String name;
  final String url;
  final Map<String, String> headers;

  const PlayerRequestAttempt({
    required this.name,
    required this.url,
    required this.headers,
  });
}

class VideoUrlParser {
  /// 解析带 Headers 的原始集数 URL，形如 "http://xx.mp4|User-Agent=123"
  static ParsedEpisodeUrl parseEpisodeUrl(String input) {
    var raw = input.trim();
    if (raw.isEmpty) {
      return const ParsedEpisodeUrl(url: '', headers: {});
    }

    raw = raw
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&#39;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('\\/', '/')
        .trim();

    if (!raw.contains('|')) {
      return ParsedEpisodeUrl(url: raw, headers: const {});
    }

    final firstPipe = raw.indexOf('|');
    if (firstPipe <= 0) {
      return ParsedEpisodeUrl(url: raw, headers: const {});
    }

    final urlPart = raw.substring(0, firstPipe).trim();
    final headerPart = raw.substring(firstPipe + 1).trim();

    final headers = <String, String>{};
    final pairs = headerPart.split('&');

    for (final pair in pairs) {
      final segment = pair.trim();
      if (segment.isEmpty) continue;

      final eqIndex = segment.indexOf('=');
      if (eqIndex <= 0 || eqIndex >= segment.length - 1) continue;

      final key = segment.substring(0, eqIndex).trim();
      final value = Uri.decodeComponent(segment.substring(eqIndex + 1).trim());
      if (key.isEmpty || value.isEmpty) continue;

      headers[_normalizeHeaderKey(key)] = value;
    }

    return ParsedEpisodeUrl(url: urlPart, headers: headers);
  }

  /// 标准化播放 URL（补全域名等）
  static String normalizePlayUrl(String input, String sourceUrl, String detailUrl) {
    // 👇 就是这行代码可能在您复制时丢失了，导致了未定义报错
    var url = input.trim(); 
    
    if (url.isEmpty) return '';

    url = url
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&#39;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('\\/', '/')
        .trim();

    if (url.startsWith('//')) {
      url = 'https:$url';
    }

    final maybeDirect = Uri.tryParse(url);
    if (maybeDirect != null && maybeDirect.scheme.isNotEmpty) {
      return maybeDirect.toString();
    }

    final base = sourceUrl.isNotEmpty ? sourceUrl : detailUrl;

    final baseUri = Uri.tryParse(base);
    if (baseUri != null) {
      try {
        return baseUri.resolve(url).toString();
      } catch (_) {}
    }

    try {
      return Uri.encodeFull(url);
    } catch (_) {
      return url;
    }
  }

  /// 根据输入构建具有不同 Headers 的多个候选播放请求，解决跨域/防盗链问题
  static List<PlayerRequestAttempt> buildRequestCandidates({
    required String url,
    required Map<String, String> embeddedHeaders,
    required String sourceUrl,
    required String detailUrl,
  }) {
    final attempts = <PlayerRequestAttempt>[];

    final detailReferer = _safeReferer(sourceUrl.isNotEmpty ? sourceUrl : detailUrl);
    final detailOrigin = _safeOrigin(detailReferer);

    final mediaOrigin = _safeOrigin(url);
    final mediaReferer = mediaOrigin.isNotEmpty ? '$mediaOrigin/' : '';

    const desktopUa =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';
    const mobileUa =
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36';

    Map<String, String> baseHeaders(String ua) {
      return <String, String>{
        'User-Agent': ua,
        'Accept': '*/*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Connection': 'keep-alive',
      };
    }

    Map<String, String> withRefererOrigin(
      Map<String, String> headers,
      String referer,
      String origin,
    ) {
      final map = <String, String>{...headers};
      if (referer.isNotEmpty) map['Referer'] = referer;
      if (origin.isNotEmpty) map['Origin'] = origin;
      return map;
    }

    final candidateHeaders = <Map<String, String>>[
      {...baseHeaders(desktopUa), ...embeddedHeaders},
      withRefererOrigin(
        {...baseHeaders(desktopUa), ...embeddedHeaders},
        detailReferer,
        detailOrigin,
      ),
      withRefererOrigin(
        {...baseHeaders(desktopUa), ...embeddedHeaders},
        mediaReferer,
        mediaOrigin,
      ),
      withRefererOrigin(
        {...baseHeaders(mobileUa), ...embeddedHeaders},
        detailReferer,
        detailOrigin,
      ),
      withRefererOrigin(
        {...baseHeaders(mobileUa), ...embeddedHeaders},
        mediaReferer,
        mediaOrigin,
      ),
    ];

    final seen = <String>{};

    for (var i = 0; i < candidateHeaders.length; i++) {
      final headers = _normalizeHeaders(candidateHeaders[i]);
      final signature = _headersSignature(headers);
      if (!seen.add(signature)) continue;

      attempts.add(
        PlayerRequestAttempt(
          name: '线路尝试 ${i + 1}',
          url: url,
          headers: headers,
        ),
      );
    }

    return attempts;
  }

  static Map<String, String> _normalizeHeaders(Map<String, String> headers) {
    final map = <String, String>{};
    headers.forEach((key, value) {
      final normalizedKey = _normalizeHeaderKey(key);
      final trimmedValue = value.trim();
      if (normalizedKey.isEmpty || trimmedValue.isEmpty) return;
      map[normalizedKey] = trimmedValue;
    });
    return map;
  }

  static String _normalizeHeaderKey(String key) {
    final lower = key.trim().toLowerCase();
    switch (lower) {
      case 'user-agent':
        return 'User-Agent';
      case 'referer':
        return 'Referer';
      case 'origin':
        return 'Origin';
      case 'accept':
        return 'Accept';
      case 'accept-language':
        return 'Accept-Language';
      case 'cookie':
        return 'Cookie';
      case 'connection':
        return 'Connection';
      default:
        if (lower.isEmpty) return '';
        return key.trim();
    }
  }

  static String _headersSignature(Map<String, String> headers) {
    final entries = headers.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((e) => '${e.key}=${e.value}').join('&');
  }

  static String _safeOrigin(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) return '';
    return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
  }

  static String _safeReferer(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) return '';
    final path = uri.path.isEmpty ? '/' : uri.path;
    return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}$path';
  }
}