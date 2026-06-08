import 'dart:async';
import 'dart:convert';

import 'package:box/utils/app_logger.dart';
import 'package:box/utils/logging_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _FakeClient extends http.BaseClient {
  _FakeClient(this._handler);

  final FutureOr<http.StreamedResponse> Function(http.BaseRequest request)
  _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return _handler(request);
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLogger.instance.clear();
  });

  group('LoggingHttpClient redaction', () {
    test('redacts sensitive headers and url query parameters', () async {
      final client = LoggingHttpClient(
        _FakeClient((request) {
          return http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode('{"ok":true}')),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await client.get(
        Uri.parse(
          'https://api.example.com/check?token=raw-token&device_id=device-1&q=keep',
        ),
        headers: {
          'Authorization': 'Bearer raw-secret',
          'Cookie': 'sid=cookie-secret',
          'X-Trace': 'trace-ok',
        },
      );

      final logs = AppLogger.instance.lines.value.join('\n');
      expect(logs, contains('token=%3Credacted%3E'));
      expect(logs, contains('device_id=%3Credacted%3E'));
      expect(logs, contains('q=keep'));
      expect(logs, contains('Authorization: <redacted>'));
      expect(logs, contains('Cookie: <redacted>'));
      expect(logs, contains('X-Trace: trace-ok'));
      expect(logs, isNot(contains('raw-token')));
      expect(logs, isNot(contains('device-1')));
      expect(logs, isNot(contains('raw-secret')));
      expect(logs, isNot(contains('cookie-secret')));
    });

    test(
      'redacts sensitive json fields from request and response previews',
      () async {
        final client = LoggingHttpClient(
          _FakeClient((request) {
            return http.StreamedResponse(
              Stream<List<int>>.value(
                utf8.encode(
                  '{"access_token":"response-token","name":"visible"}',
                ),
              ),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }),
        );

        await client.post(
          Uri.parse('https://api.example.com/login'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'password': 'plain-password',
            'user': 'visible-user',
          }),
        );

        final logs = AppLogger.instance.lines.value.join('\n');
        expect(logs, contains('visible-user'));
        expect(logs, contains('visible'));
        expect(logs, contains('"password":"<redacted>"'));
        expect(logs, contains('"access_token":"<redacted>"'));
        expect(logs, isNot(contains('plain-password')));
        expect(logs, isNot(contains('response-token')));
      },
    );
  });
}
