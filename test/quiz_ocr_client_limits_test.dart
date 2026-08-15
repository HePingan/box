import 'dart:convert';
import 'dart:typed_data';

import 'package:box/features/quiz_plugin/data/quiz_ocr_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// 成功响应体（UTF-8 JSON）。
String _okBody(String text) => jsonEncode({
  'code': 200,
  'data': {
    'texts': [text],
    'scores': [0.9],
    'full_text': text,
  },
});

void main() {
  test('recognizeBytes rejects oversized capture before any upload', () async {
    final stub = _StubClient((_) => _Reply(200, '{}'));
    final client = QuizOcrClient(
      endpoint: 'https://ocr.example',
      httpClient: stub,
    );

    final result = await client.recognizeBytes(
      Uint8List(QuizOcrClient.maxUploadBytes + 1),
    );

    expect(result.isSuccess, isFalse);
    expect(result.error, contains('2MB'));
    expect(stub.calls, 0, reason: '超限时不应发起任何网络请求');
  });

  test('recognizeBytes uploads a payload at the size boundary', () async {
    final stub = _StubClient((_) => _Reply(200, _okBody('边界题')));
    final client = QuizOcrClient(
      endpoint: 'https://ocr.example',
      httpClient: stub,
    );

    final result = await client.recognizeBytes(
      Uint8List(QuizOcrClient.maxUploadBytes),
    );

    expect(stub.calls, 1);
    expect(result.isSuccess, isTrue);
    expect(result.fullText, '边界题');
  });

  test('decodes UTF-8 body even without a charset header', () async {
    // package:http 缺少 charset 时按 latin1 解码，中文会变乱码。
    final stub = _StubClient(
      (_) => _Reply(200, _okBody('中文题干'), contentType: 'application/json'),
    );
    final client = QuizOcrClient(
      endpoint: 'https://ocr.example',
      httpClient: stub,
    );

    final result = await client.recognizeUrl('https://img.example/a.png');

    expect(result.isSuccess, isTrue);
    expect(result.fullText, '中文题干');
  });

  test('recognizeUrl retries a 5xx and then succeeds', () async {
    final stub = _StubClient(
      (call) => call == 1 ? _Reply(503, 'boom') : _Reply(200, _okBody('第一行')),
    );
    final client = QuizOcrClient(
      endpoint: 'https://ocr.example',
      retryDelay: Duration.zero,
      httpClient: stub,
    );

    final result = await client.recognizeUrl('https://img.example/a.png');

    expect(stub.calls, 2);
    expect(result.isSuccess, isTrue);
    expect(result.fullText, '第一行');
  });

  test('recognizeUrl does not retry a business-level failure', () async {
    final stub = _StubClient(
      (_) => _Reply(200, jsonEncode({'code': 400, 'msg': '参数错误'})),
    );
    final client = QuizOcrClient(
      endpoint: 'https://ocr.example',
      retryDelay: Duration.zero,
      httpClient: stub,
    );

    final result = await client.recognizeUrl('https://img.example/a.png');

    expect(stub.calls, 1, reason: '业务错误不应重试');
    expect(result.isSuccess, isFalse);
    expect(result.error, contains('400'));
  });

  test('recognizeUrl gives up after maxAttempts on persistent 5xx', () async {
    final stub = _StubClient((_) => _Reply(500, 'down'));
    final client = QuizOcrClient(
      endpoint: 'https://ocr.example',
      retryDelay: Duration.zero,
      maxAttempts: 3,
      httpClient: stub,
    );

    final result = await client.recognizeUrl('https://img.example/a.png');

    expect(stub.calls, 3);
    expect(result.isSuccess, isFalse);
    expect(result.error, contains('OCR 抓取失败'));
  });
}

class _Reply {
  _Reply(this.statusCode, this.body, {this.contentType});
  final int statusCode;
  final String body;
  final String? contentType;
}

class _StubClient extends http.BaseClient {
  _StubClient(this.responder);

  final _Reply Function(int call) responder;
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    final reply = responder(calls);
    return http.StreamedResponse(
      Stream.value(utf8.encode(reply.body)),
      reply.statusCode,
      headers: {
        'content-type': reply.contentType ?? 'application/json; charset=utf-8',
      },
    );
  }
}
