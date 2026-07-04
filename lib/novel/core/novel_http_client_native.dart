import 'dart:convert';

import 'package:http/http.dart' as http;

import 'novel_http_client.dart';

/// 原生平台实现 — 使用 http 包的标准 Client
class PlatformHttpClient implements NovelHttpClient {
  PlatformHttpClient({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    final request = http.Request('GET', uri);
    if (headers != null) request.headers.addAll(headers);
    final streamed = await _client.send(request).timeout(
          timeout ?? const Duration(seconds: 15),
        );
    return http.Response.fromStream(streamed);
  }

  @override
  Future<http.Response> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    Duration? timeout,
  }) async {
    final request = http.Request('POST', uri);
    if (headers != null) request.headers.addAll(headers);
    if (body != null) {
      if (body is String) {
        request.body = body;
      } else if (body is List<int>) {
        request.bodyBytes = body;
      } else if (body is Map<String, dynamic>) {
        request.headers['Content-Type'] ??= 'application/json';
        request.body = jsonEncode(body);
      }
    }
    if (encoding != null) request.encoding = encoding;
    final streamed = await _client.send(request).timeout(
          timeout ?? const Duration(seconds: 15),
        );
    return http.Response.fromStream(streamed);
  }
}
