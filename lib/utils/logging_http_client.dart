import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_logger.dart';

class LoggingHttpClient extends http.BaseClient {
  LoggingHttpClient(this._inner, {this.tag = 'HTTP'});

  final http.Client _inner;
  final String tag;

  static const int _previewMax = 1200;
  static const Set<String> _sensitiveKeys = {
    'authorization',
    'cookie',
    'token',
    'access_token',
    'refresh_token',
    'device_id',
    'user_id',
    'password',
    'secret',
    'signature',
    'sign',
  };

  void _log(String message) {
    AppLogger.instance.log(message, tag: tag);
  }

  Map<String, String> _redactHeaders(Map<String, String> headers) {
    final out = <String, String>{};
    headers.forEach((k, v) {
      final key = k.toLowerCase();
      if (_isSensitiveKey(key)) {
        out[k] = '<redacted>';
      } else {
        out[k] = v;
      }
    });
    return out;
  }

  bool _isSensitiveKey(String key) {
    final normalized = key.toLowerCase();
    return _sensitiveKeys.any(normalized.contains);
  }

  Uri _redactUrl(Uri url) {
    if (url.queryParametersAll.isEmpty) return url;

    final redactedQuery = <String, List<String>>{};
    for (final entry in url.queryParametersAll.entries) {
      final key = entry.key;
      redactedQuery[key] = _isSensitiveKey(key)
          ? const ['<redacted>']
          : entry.value;
    }

    return url.replace(queryParameters: redactedQuery);
  }

  String _preview(String text) {
    final normalized = text.replaceAll('\r\n', '\n');
    final redacted = _redactSensitiveText(normalized);
    if (redacted.length <= _previewMax) return redacted;
    return '${redacted.substring(0, _previewMax)}\n...<truncated ${redacted.length - _previewMax} chars>';
  }

  String _redactSensitiveText(String text) {
    try {
      final decoded = jsonDecode(text);
      return jsonEncode(_redactJsonValue(decoded));
    } catch (_) {
      return text;
    }
  }

  dynamic _redactJsonValue(dynamic value, [String? key]) {
    if (key != null && _isSensitiveKey(key)) return '<redacted>';

    if (value is Map) {
      return value.map(
        (k, v) => MapEntry(k.toString(), _redactJsonValue(v, k.toString())),
      );
    }

    if (value is List) {
      return value.map(_redactJsonValue).toList(growable: false);
    }

    return value;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final safeUrl = _redactUrl(request.url);
    _log('→ ${request.method} $safeUrl');
    _log('headers=${_redactHeaders(request.headers)}');

    if (!kReleaseMode && request is http.Request && request.body.isNotEmpty) {
      _log('body=${_preview(request.body)}');
    }

    try {
      final streamed = await _inner.send(request);

      final bytes = await streamed.stream.fold<List<int>>(<int>[], (
        prev,
        chunk,
      ) {
        prev.addAll(chunk);
        return prev;
      });

      final body = utf8.decode(bytes, allowMalformed: true);

      _log(
        '← ${request.method} $safeUrl '
        'status=${streamed.statusCode} '
        'contentType=${streamed.headers['content-type']} '
        'length=${bytes.length}',
      );
      if (!kReleaseMode) {
        _log('preview:\n${_preview(body)}');
      }

      return http.StreamedResponse(
        Stream<List<int>>.value(bytes),
        streamed.statusCode,
        contentLength: bytes.length,
        request: streamed.request,
        headers: streamed.headers,
        isRedirect: streamed.isRedirect,
        persistentConnection: streamed.persistentConnection,
        reasonPhrase: streamed.reasonPhrase,
      );
    } catch (e, st) {
      _log('request failed ${request.method} $safeUrl error=$e');
      _log(st.toString());
      rethrow;
    }
  }

  @override
  void close() {
    _inner.close();
  }
}
