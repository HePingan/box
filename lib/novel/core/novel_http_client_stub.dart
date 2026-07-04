import 'dart:convert';

import 'package:http/http.dart' as http;

import 'novel_http_client.dart';

/// Stub — 不应该被实际使用，仅用于满足类型系统
class PlatformHttpClient implements NovelHttpClient {
  PlatformHttpClient({http.Client? client});

  @override
  Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration? timeout,
  }) =>
      throw UnsupportedError('Unsupported platform');

  @override
  Future<http.Response> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    Duration? timeout,
  }) =>
      throw UnsupportedError('Unsupported platform');
}
