import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_logger.dart';

class LoggingHttpClient extends http.BaseClient {
  LoggingHttpClient(this._inner, {this.tag = 'HTTP'});

  final http.Client _inner;
  final String tag;

  static const int _previewMax = 1200;

  void _log(String message) {
    AppLogger.instance.log(message, tag: tag);
  }

  Map<String, String> _redactHeaders(Map<String, String> headers) {
    final out = <String, String>{};
    headers.forEach((k, v) {
      final key = k.toLowerCase();
      if (key == 'cookie' || key == 'authorization') {
        out[k] = '<redacted>';
      } else {
        out[k] = v;
      }
    });
    return out;
  }

  String _preview(String text) {
    final normalized = text.replaceAll('\r\n', '\n');
    if (normalized.length <= _previewMax) return normalized;
    return '${normalized.substring(0, _previewMax)}\n...<truncated ${normalized.length - _previewMax} chars>';
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _log('→ ${request.method} ${request.url}');
    _log('headers=${_redactHeaders(request.headers)}');

    if (request is http.Request && request.body.isNotEmpty) {
      _log('body=${_preview(request.body)}');
    }

    try {
      final streamed = await _inner.send(request);

      final bytes = await streamed.stream.fold<List<int>>(
        <int>[],
        (prev, chunk) {
          prev.addAll(chunk);
          return prev;
        },
      );

      final body = utf8.decode(bytes, allowMalformed: true);

      _log(
        '← ${request.method} ${request.url} '
        'status=${streamed.statusCode} '
        'contentType=${streamed.headers['content-type']} '
        'length=${bytes.length}',
      );
      _log('preview:\n${_preview(body)}');

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
      _log('request failed ${request.method} ${request.url} error=$e');
      _log(st.toString());
      rethrow;
    }
  }

  @override
  void close() {
    _inner.close();
  }
}