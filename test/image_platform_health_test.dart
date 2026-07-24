import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('image platform quota server exposes root health payload', () async {
    final fixture = await _startServer();
    try {
      final client = HttpClient();
      try {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:${fixture.port}/'),
        );
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final decoded = jsonDecode(body) as Map<String, dynamic>;

        expect(response.statusCode, HttpStatus.ok);
        expect(decoded['ok'], isTrue);
        expect(decoded['service'], 'box-image-platform');
        expect(decoded['message'], contains('running'));
      } finally {
        client.close(force: true);
      }
    } finally {
      await fixture.dispose();
    }

    expect(
      fixture.stderrText.toString(),
      isNot(contains('Unhandled request error')),
    );
  });

  test('image proxy requires login and forwards image bytes', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final upstreamDone = upstream.listen((request) async {
      if (request.uri.path == '/image.png') {
        final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
        await request.response.close();
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    });

    final fixture = await _startServer();
    final client = HttpClient();
    try {
      final imageUrl = Uri.encodeQueryComponent(
        'http://127.0.0.1:${upstream.port}/image.png',
      );
      final unauthorizedRequest = await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:${fixture.port}/api/image/proxy?url=$imageUrl',
        ),
      );
      final unauthorizedResponse = await unauthorizedRequest.close();
      expect(unauthorizedResponse.statusCode, HttpStatus.unauthorized);
      await unauthorizedResponse.drain<void>();

      final loginRequest = await client.postUrl(
        Uri.parse('http://127.0.0.1:${fixture.port}/api/auth/login'),
      );
      loginRequest.headers.contentType = ContentType.json;
      loginRequest.write(
        jsonEncode({'username': 'admin', 'password': 'test-admin-password'}),
      );
      final loginResponse = await loginRequest.close();
      final loginBody = await loginResponse.transform(utf8.decoder).join();
      final token =
          (jsonDecode(loginBody) as Map<String, dynamic>)['token'] as String;

      final proxyRequest = await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:${fixture.port}/api/image/proxy?url=$imageUrl',
        ),
      );
      proxyRequest.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $token',
      );
      final proxyResponse = await proxyRequest.close();
      final bytes = await proxyResponse.fold<List<int>>(
        <int>[],
        (previous, chunk) => previous..addAll(chunk),
      );

      expect(proxyResponse.statusCode, HttpStatus.ok);
      expect(proxyResponse.headers.contentType?.mimeType, 'image/png');
      expect(proxyResponse.headers.value('x-box-image-proxy'), '1');
      expect(bytes, [1, 2, 3, 4, 5]);
    } finally {
      client.close(force: true);
      await fixture.dispose();
      await upstream.close(force: true);
      await upstreamDone.cancel();
    }

    expect(
      fixture.stderrText.toString(),
      isNot(contains('Unhandled request error')),
    );
  });

  test(
    'quiz cloud workflow creates, syncs, submits, and approves questions',
    () async {
      final fixture = await _startServer();
      final client = HttpClient();
      try {
        final login = await _jsonRequest(
          client,
          'POST',
          fixture.port,
          '/api/auth/login',
          body: {'username': 'admin', 'password': 'test-admin-password'},
        );
        final token = login['token'] as String;
        final created = await _jsonRequest(
          client,
          'POST',
          fixture.port,
          '/admin/quiz/questions',
          token: token,
          body: {
            'question': '云端题库是否支持离线同步？',
            'type': 'single_choice',
            'options': ['支持', '不支持'],
            'correctAnswer': 'A',
            'category': 'drive_ev',
          },
        );
        expect(created['status'], 'published');

        final sync = await _jsonRequest(
          client,
          'GET',
          fixture.port,
          '/api/quiz/sync?cursor=0',
        );
        final changes = sync['changes'] as List;
        expect(changes, hasLength(1));
        expect((changes.single as Map)['operation'], 'upsert');

        final submitted = await _jsonRequest(
          client,
          'POST',
          fixture.port,
          '/api/quiz/submissions',
          token: token,
          body: {
            'question': '审核题会进入正式题库吗？',
            'type': 'single_choice',
            'options': ['会', '不会'],
            'correctAnswer': 'A',
            'category': 'drive_ev',
          },
        );
        final submissionId = submitted['id'] as String;
        expect(submitted['status'], 'pending');

        final approved = await _jsonRequest(
          client,
          'POST',
          fixture.port,
          '/admin/quiz/submissions/$submissionId/approve',
          token: token,
          body: const {},
        );
        expect(approved['status'], 'approved');
        final catalogs = await _jsonRequest(
          client,
          'GET',
          fixture.port,
          '/api/quiz/catalogs',
        );
        expect((catalogs['catalogs'] as List).single, containsPair('count', 2));
      } finally {
        client.close(force: true);
        await fixture.dispose();
      }
    },
  );
  test('slow image generation does not block health requests', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final upstreamDone = upstream.listen((request) async {
      if (request.uri.path == '/v1/images/generations') {
        await Future<void>.delayed(const Duration(seconds: 3));
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': [
              {'url': 'https://example.com/generated.png'},
            ],
          }),
        );
        await request.response.close();
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    });

    final fixture = await _startServer(
      extraEnvironment: {
        'IMAGE_ADMIN_BASE_URL': 'http://127.0.0.1:${upstream.port}/v1',
        'IMAGE_ADMIN_API_KEY': 'test-key',
        'IMAGE_ALLOWED_MODELS': 'gpt-image-2',
      },
    );
    final client = HttpClient();
    try {
      final loginRequest = await client.postUrl(
        Uri.parse('http://127.0.0.1:${fixture.port}/api/auth/login'),
      );
      loginRequest.headers.contentType = ContentType.json;
      loginRequest.write(
        jsonEncode({'username': 'admin', 'password': 'test-admin-password'}),
      );
      final loginResponse = await loginRequest.close();
      final loginBody = await loginResponse.transform(utf8.decoder).join();
      final token =
          (jsonDecode(loginBody) as Map<String, dynamic>)['token'] as String;

      final generateRequest = await client.postUrl(
        Uri.parse('http://127.0.0.1:${fixture.port}/api/image/generate'),
      );
      generateRequest.headers.contentType = ContentType.json;
      generateRequest.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $token',
      );
      generateRequest.write(
        jsonEncode({
          'model': 'gpt-image-2',
          'prompt': 'slow lettuce',
          'size': '1024x1024',
          'quality': 'auto',
          'n': 1,
        }),
      );
      final generateFuture = generateRequest.close();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final healthRequest = await client.getUrl(
        Uri.parse('http://127.0.0.1:${fixture.port}/'),
      );
      final healthResponse = await healthRequest.close().timeout(
        const Duration(seconds: 1),
      );
      await healthResponse.drain<void>();
      expect(healthResponse.statusCode, HttpStatus.ok);

      final generateResponse = await generateFuture.timeout(
        const Duration(seconds: 5),
      );
      await generateResponse.drain<void>();
      expect(generateResponse.statusCode, HttpStatus.ok);
    } finally {
      client.close(force: true);
      await fixture.dispose();
      await upstream.close(force: true);
      await upstreamDone.cancel();
    }
  });
}

Future<_ServerFixture> _startServer({
  Map<String, String> extraEnvironment = const {},
}) async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();

  final stateFile = File(
    '${Directory.systemTemp.path}/box_health_${DateTime.now().microsecondsSinceEpoch}.json',
  );
  final dartCommand = Platform.isWindows ? 'dart.bat' : 'dart';
  final process = await Process.start(
    dartCommand,
    [
      'run',
      'tool/image_platform_quota_server.dart',
      '--host',
      '127.0.0.1',
      '--port',
      '$port',
    ],
    environment: {
      'IMAGE_STATE_PATH': stateFile.path,
      'BOX_ADMIN_PASSWORD': 'test-admin-password',
      ...extraEnvironment,
    },
    includeParentEnvironment: true,
  );

  final stdoutLines = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .asBroadcastStream();
  final stderrText = StringBuffer();
  final stderrSubscription = process.stderr
      .transform(utf8.decoder)
      .listen(stderrText.write);

  await stdoutLines.firstWhere(
    (line) => line.contains('Box image platform quota server running'),
  );

  return _ServerFixture(
    port: port,
    process: process,
    stateFile: stateFile,
    stderrText: stderrText,
    stderrSubscription: stderrSubscription,
  );
}

Future<Map<String, dynamic>> _jsonRequest(
  HttpClient client,
  String method,
  int port,
  String path, {
  String? token,
  Map<String, dynamic>? body,
}) async {
  final request = await client.openUrl(
    method,
    Uri.parse('http://127.0.0.1:$port$path'),
  );
  if (token != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  }
  if (body != null) {
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
  }
  final response = await request.close();
  final text = await response.transform(utf8.decoder).join();
  expect(response.statusCode, greaterThanOrEqualTo(HttpStatus.ok));
  expect(response.statusCode, lessThan(HttpStatus.multipleChoices));
  return Map<String, dynamic>.from(jsonDecode(text) as Map);
}

class _ServerFixture {
  _ServerFixture({
    required this.port,
    required this.process,
    required this.stateFile,
    required this.stderrText,
    required this.stderrSubscription,
  });

  final int port;
  final Process process;
  final File stateFile;
  final StringBuffer stderrText;
  final StreamSubscription<String> stderrSubscription;

  Future<void> dispose() async {
    process.kill();
    await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () => -1,
    );
    await stderrSubscription.cancel();
    if (await stateFile.exists()) await stateFile.delete();
  }
}
