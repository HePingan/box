import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:box/video/services/search_failure_exception.dart';
import 'package:box/video/services/shared_http_client.dart';
import 'package:box/video/services/video_api_service.dart';

void main() {
  setUp(() {
    SharedHttpClient.reset();
    VideoApiService.configureVodProxy(enabled: false);
  });
  tearDown(() {
    SharedHttpClient.reset();
    VideoApiService.configureVodProxy(enabled: true);
  });

  group('VideoApiService.searchVideo', () {
    test(
      'returns an empty list when a candidate successfully has no matches',
      () async {
        final server = await _startServer((request) async {
          await _respondJson(request, const {'code': 1, 'list': []});
        });
        addTearDown(server.close);

        final result = await VideoApiService.searchVideo(server.url, 'missing');

        expect(result, isEmpty);
      },
    );

    test('throws when every candidate request fails', () async {
      final server = await _startServer((request) async {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
      });
      addTearDown(server.close);

      await expectLater(
        VideoApiService.searchVideo(server.url, 'broken'),
        throwsA(
          isA<AllSearchCandidatesFailedException>().having(
            (error) => error.errors,
            'errors',
            hasLength(4),
          ),
        ),
      );
    });

    test('uses one total timeout budget across candidate formats', () async {
      var requestCount = 0;
      final server = await _startServer((request) async {
        requestCount++;
        await Future<void>.delayed(const Duration(milliseconds: 70));
        await _respondJson(request, const {'code': 1, 'list': []});
      });
      addTearDown(server.close);

      final watch = Stopwatch()..start();
      final result = await VideoApiService.searchVideo(
        server.url,
        'budget',
        timeout: const Duration(milliseconds: 115),
      );

      expect(result, isEmpty);
      expect(requestCount, lessThan(4));
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 210)));
    });
  });
}

Future<_TestServer> _startServer(
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  unawaited(server.forEach(handler));
  return _TestServer(server);
}

Future<void> _respondJson(HttpRequest request, Object json) async {
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(json));
  await request.response.close();
}

class _TestServer {
  const _TestServer(this._server);

  final HttpServer _server;

  String get url => 'http://${_server.address.address}:${_server.port}/api.php';

  Future<void> close() => _server.close(force: true);
}
