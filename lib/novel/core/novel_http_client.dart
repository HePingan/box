import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'novel_http_client_stub.dart'
    if (dart.library.html) 'novel_http_client_web.dart'
    if (dart.library.io) 'novel_http_client_native.dart';

abstract class NovelHttpClient {
  const NovelHttpClient();

  Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration? timeout,
  });

  Future<http.Response> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    Duration? timeout,
  });

  /// 自动选择平台实现
  factory NovelHttpClient.create({http.Client? client}) = PlatformHttpClient;
}
