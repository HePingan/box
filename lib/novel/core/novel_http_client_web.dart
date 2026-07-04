// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:http/http.dart' as http;

import 'novel_http_client.dart';

/// Web 平台实现 — 使用 dart:html 的 XMLHttpRequest
///
/// 解决 http 包在 Web 端的两个问题：
/// 1. BrowserClient 不发送自定义 headers（CORS 限制）
/// 2. responseType 不匹配导致响应体为空
///
/// 使用原生 XMLHttpRequest 可以：
/// - 设置自定义 headers（服务器需配置 CORS Access-Control-Allow-Headers）
/// - 正确设置 responseType = 'text' 获取响应体
/// - 支持超时控制
class PlatformHttpClient implements NovelHttpClient {
  const PlatformHttpClient({http.Client? client});

  @override
  Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration? timeout,
  }) =>
      _send('GET', uri, headers: headers, timeout: timeout);

  @override
  Future<http.Response> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    Duration? timeout,
  }) =>
      _send('POST', uri,
          headers: headers, body: body, timeout: timeout);

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    final completer = Completer<http.Response>();
    final xhr = html.HttpRequest();

    xhr.open(method, uri.toString(), async: true);
    xhr.responseType = 'text';
    xhr.timeout = (timeout ?? const Duration(seconds: 15)).inMilliseconds;

    // 设置请求头
    if (headers != null) {
      for (final entry in headers.entries) {
        try {
          xhr.setRequestHeader(entry.key, entry.value);
        } catch (_) {
          // 某些头在 Web 端不允许设置（如某些 forbidden headers），静默忽略
        }
      }
    }

    // 超时
    xhr.onTimeout.first.then((_) {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException(
          '请求超时 (${timeout?.inSeconds ?? 15}秒)',
          timeout ?? const Duration(seconds: 15),
        ));
      }
    });

    // 网络错误
    xhr.onError.first.then((_) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('网络请求失败: ${uri.host}'));
      }
    });

    // 加载完成
    xhr.onLoad.first.then((_) {
      if (completer.isCompleted) return;
      final status = xhr.status ?? 0;
      final responseText = xhr.responseText ?? '';

      // 解析响应头
      final responseHeaders = <String, String>{};
      final allHeaders = xhr.getAllResponseHeaders();
      if (allHeaders.isNotEmpty) {
        for (final line in allHeaders.split('\r\n')) {
          if (line.isEmpty) continue;
          final colonIdx = line.indexOf(':');
          if (colonIdx > 0) {
            final key = line.substring(0, colonIdx).trim().toLowerCase();
            final value = line.substring(colonIdx + 1).trim();
            responseHeaders[key] = value;
          }
        }
      }

      completer.complete(http.Response(
        responseText,
        status,
        headers: responseHeaders,
        reasonPhrase: xhr.statusText,
      ));
    });

    // 发送
    if (body != null) {
      if (body is String) {
        xhr.send(body);
      } else if (body is List<int>) {
        xhr.send(body);
      } else {
        xhr.send(body.toString());
      }
    } else {
      xhr.send();
    }

    return completer.future;
  }
}
