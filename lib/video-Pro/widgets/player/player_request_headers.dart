import 'package:flutter/foundation.dart';

const String kFallbackPlayerUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

Map<String, String> buildPlayerHeaders({
  required String userAgent,
  String? referer,
  Map<String, String>? extraHeaders,
}) {
  if (kIsWeb) return const <String, String>{};

  final ua = userAgent.trim().isNotEmpty
      ? userAgent.trim()
      : kFallbackPlayerUserAgent;

  final headers = <String, String>{
    'User-Agent': ua,
    'Accept': '*/*',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'Accept-Encoding': 'identity',
    'Connection': 'keep-alive',
  };

  if (extraHeaders != null && extraHeaders.isNotEmpty) {
    for (final entry in extraHeaders.entries) {
      final key = entry.key.trim();
      final value = entry.value.trim();

      if (key.isEmpty || value.isEmpty) continue;

      final lowerKey = key.toLowerCase();
      if (lowerKey == 'host' ||
          lowerKey == 'content-length' ||
          lowerKey == 'referer' ||
          lowerKey == 'origin') {
        continue;
      }

      headers[key] = value;
    }
  }

  final cleanedReferer = referer?.trim();
  if (cleanedReferer != null && cleanedReferer.isNotEmpty) {
    headers['Referer'] = cleanedReferer;

    final origin = originFromUrl(cleanedReferer);
    if (origin != null && origin.isNotEmpty) {
      headers['Origin'] = origin;
    }
  }

  return headers;
}

String? originFromUrl(String raw) {
  try {
    final uri = Uri.parse(raw);
    if (!uri.hasScheme || uri.host.isEmpty) return null;

    return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
  } catch (_) {
    return null;
  }
}