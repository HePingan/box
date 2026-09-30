import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// 服务端：匿名设备令牌 + 按主体计额度 的端到端用例（真实起进程 + 真 HTTP）。
///
/// 客户端那半边的契约锁在 test/quiz_vision_device_token_test.dart（另一份）。
/// 本文件只验服务端：签发形状、只存哈希、设备额度键单列（device: 前缀）、
/// 撤销立即 401、按 IP 每日签发上限、旧 state 文件向后兼容。
///
/// 注意：绝不能调用 TestWidgetsFlutterBinding.ensureInitialized()——它会劫持
/// HttpClient 让所有请求返回 400（image_platform_health_test.dart 同款坑）。
void main() {
  const deviceId = 'dev-alpha-0001';
  const upstreamFailMarker = 'upstream-fail-marker';
  late _Fixture fixture;
  late HttpServer upstream;
  late StreamSubscription<HttpRequest> upstreamSub;
  late String deviceToken;
  late String adminToken;

  setUpAll(() async {
    // 上游桩：正常 200；请求体里带 marker 时回 502（用来验设备上游失败数）。
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstreamSub = upstream.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      if (body.contains(upstreamFailMarker)) {
        request.response.statusCode = HttpStatus.badGateway;
        request.response.write(jsonEncode({'error': 'upstream down'}));
      } else {
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'A'},
              },
            ],
          }),
        );
      }
      await request.response.close();
    });

    // 旧格式 state：没有 quizVisionDevices 字段，且已有一条老用量。
    // 必须先证明这种文件能正常启动、新字段读成空表、老数据不被挤掉。
    fixture = await _startServer(
      seedState: {
        'quizVisionUsage': {
          'u_legacy0001': {'2000-01-01': 3},
        },
        'usage': <dynamic>[],
      },
    );

    adminToken = (await fixture.ok(
      'POST',
      '/api/auth/login',
      body: {'username': 'admin', 'password': 'test-admin-password'},
    ))['token'] as String;

    final provider = await fixture.ok(
      'POST',
      '/admin/quiz-vision/provider',
      token: adminToken,
      body: {
        'baseUrl': 'http://127.0.0.1:${upstream.port}/v1',
        'apiKey': 'test-upstream-key',
        'model': '',
        'enabled': true,
      },
    );
    expect(provider['enabled'], isTrue);
    expect(provider['hasApiKey'], isTrue);
  });

  tearDownAll(() async {
    await fixture.dispose();
    await upstream.close(force: true);
    await upstreamSub.cancel();
  });

  test('签发设备令牌：形状符合契约，且 state 里只有哈希、没有明文', () async {
    final issued = await fixture.ok(
      'POST',
      '/api/quiz/vision/device-token',
      body: {'deviceId': deviceId},
    );
    expect(issued['deviceId'], deviceId);
    expect(issued['dailyCap'], 100);
    // 契约：设备令牌不设过期。
    expect(issued['expiresInDays'], isNull);
    deviceToken = issued['token'] as String;
    expect(deviceToken, matches(RegExp(r'^[0-9a-f]{64}$')));

    final raw = await fixture.stateFile.readAsString();
    expect(raw, isNot(contains(deviceToken)), reason: '明文令牌绝不能落盘');
    final digest = sha256.convert(utf8.encode(deviceToken)).toString();
    expect(raw, contains(digest), reason: '应存 sha256 哈希');
    expect(raw, contains('"tokenHash"'));
    // 向后兼容：旧 state 里已有的用量没被新字段挤掉。
    expect(raw, contains('u_legacy0001'));
    expect(raw, contains('quizVisionDevices'));

    // 签发即入设备统计；此时只有这一台设备，统计值可以做精确断言。
    final stats = await fixture.ok(
      'GET',
      '/admin/quiz-vision/stats',
      token: adminToken,
    );
    expect(stats['deviceCount'], 1);
    expect(stats['deviceTotal'], 0);
    expect(stats['deviceFailed'], 0);
    // 2000 年那条旧用量不属于今天，也不该被算进账号口径。
    expect(stats['total'], 0);
    expect(stats['accounts'], 0);
  });

  test('deviceId 形状非法一律 400，且不消耗签发配额', () async {
    final badBodies = <String, Object?>{
      '缺失 deviceId': <String, dynamic>{},
      '太短': {'deviceId': 'short'},
      '带空格': {'deviceId': 'has space here'},
      '带斜杠': {'deviceId': 'has/slash/inside'},
      '超长 65': {'deviceId': 'x' * 65},
      '不是字符串': {'deviceId': <String, dynamic>{'nested': 1}},
    };
    for (final entry in badBodies.entries) {
      final res = await fixture.send(
        'POST',
        '/api/quiz/vision/device-token',
        body: entry.value,
      );
      expect(
        res.statusCode,
        HttpStatus.badRequest,
        reason: '${entry.key} 应 400，实际 ${res.statusCode} ${res.text}',
      );
      expect(res.errorMessage, isNotEmpty, reason: '${entry.key} 要有中文原因');
    }
    // 形状校验失败不计数：随后仍能正常签发（配额没被 400 吃掉）。
    final stillOk = await fixture.ok(
      'POST',
      '/api/quiz/vision/device-token',
      body: {'deviceId': 'dev-gamma-0003'},
    );
    expect(stillOk['token'], isA<String>());
  });

  test('设备令牌走 /api/quiz/vision，额度按 device:<id> 单列，账号口径不回归', () async {
    final deviceCall = await fixture.ok(
      'POST',
      '/api/quiz/vision',
      token: deviceToken,
      body: {
        'model': 'stub-model',
        'messages': [
          {
            'role': 'user',
            'content': '这台车的仪表盘是什么意思',
          },
        ],
      },
    );
    expect((deviceCall['choices'] as List), isNotEmpty);

    // 设备上游失败 → deviceFailed +1，deviceTotal 同步 +1。
    // 走别名路径，顺带验「两条路径共用一个主体解析」没有漏掉别名。
    final failed = await fixture.send(
      'POST',
      '/api/quiz/vision/chat/completions',
      token: deviceToken,
      body: {
        'model': 'stub-model',
        'messages': [
          {
            'role': 'user',
            'content': upstreamFailMarker,
          },
        ],
      },
    );
    expect(failed.statusCode, HttpStatus.badGateway);

    var stats = await fixture.ok(
      'GET',
      '/admin/quiz-vision/stats',
      token: adminToken,
    );
    expect(stats['deviceCount'], greaterThanOrEqualTo(1));
    expect(stats['deviceTotal'], 2);
    expect(stats['deviceFailed'], 1);
    expect(stats['deviceDailyCap'], 100);
    expect((stats['perDevice'] as Map).keys, contains('device:$deviceId'));
    // 设备用量不混进账号口径。
    expect(stats['total'], 0);
    expect(stats['accounts'], 0);
    expect(stats['failed'], 0);
    expect(stats['perAccount'], isEmpty);

    // 账号主体行为与加设备前一致：额度键是账号 id、计入 total/accounts。
    final accountCall = await fixture.ok(
      'POST',
      '/api/quiz/vision',
      token: adminToken,
      body: {
        'model': 'stub-model',
        'messages': [
          {
            'role': 'user',
            'content': '账号主体这一路还通吗',
          },
        ],
      },
    );
    expect((accountCall['choices'] as List), isNotEmpty);

    stats = await fixture.ok(
      'GET',
      '/admin/quiz-vision/stats',
      token: adminToken,
    );
    expect(stats['total'], 1);
    expect(stats['accounts'], 1);
    expect((stats['perAccount'] as Map).keys, contains('u_admin'));
    expect(stats['deviceTotal'], 2, reason: '账号调用不该改动设备口径');
    expect(stats['deviceCount'], greaterThanOrEqualTo(1));
  });

  test('未知令牌 / 无令牌一律 401，且都带中文原因（不静默）', () async {
    final unknown = await fixture.send(
      'POST',
      '/api/quiz/vision',
      token: 'f' * 64,
      body: {
        'model': 'stub-model',
        'messages': [
          {
            'role': 'user',
            'content': 'x',
          },
        ],
      },
    );
    expect(unknown.statusCode, HttpStatus.unauthorized);
    expect(unknown.errorMessage, isNotEmpty);

    final none = await fixture.send('POST', '/api/quiz/vision', body: const {});
    expect(none.statusCode, HttpStatus.unauthorized);
    expect(none.errorMessage, isNotEmpty);
  });

  test('管理员撤销设备令牌后立刻 401，且该设备无法重签', () async {
    final second = await fixture.ok(
      'POST',
      '/api/quiz/vision/device-token',
      body: {'deviceId': 'dev-beta-0002'},
    );
    final token = second['token'] as String;

    // 撤销前可用。
    final before = await fixture.ok(
      'POST',
      '/api/quiz/vision',
      token: token,
      body: {
        'model': 'stub-model',
        'messages': [
          {
            'role': 'user',
            'content': 'before revoke',
          },
        ],
      },
    );
    expect((before['choices'] as List), isNotEmpty);

    // 无鉴权不能撤销。
    final anon = await fixture.send(
      'DELETE',
      '/api/quiz/vision/device/dev-beta-0002',
    );
    expect(anon.statusCode, HttpStatus.unauthorized);

    final revoked = await fixture.ok(
      'DELETE',
      '/api/quiz/vision/device/dev-beta-0002',
      token: adminToken,
    );
    expect(revoked['revoked'], isTrue);
    expect(revoked['deviceId'], 'dev-beta-0002');

    // 撤销后立刻 401。
    final after = await fixture.send(
      'POST',
      '/api/quiz/vision',
      token: token,
      body: {
        'model': 'stub-model',
        'messages': [
          {
            'role': 'user',
            'content': 'after revoke',
          },
        ],
      },
    );
    expect(after.statusCode, HttpStatus.unauthorized);
    expect(after.errorMessage, isNotEmpty);

    // 撤销是粘性的：重签被拒，令牌不会复活。
    final reissue = await fixture.send(
      'POST',
      '/api/quiz/vision/device-token',
      body: {'deviceId': 'dev-beta-0002'},
    );
    expect(reissue.statusCode, HttpStatus.forbidden);
    expect(reissue.errorMessage, isNotEmpty);

    // 撤销另一台不影响已签发的第一台设备。
    final stillWorks = await fixture.ok(
      'POST',
      '/api/quiz/vision',
      token: deviceToken,
      body: {
        'model': 'stub-model',
        'messages': [
          {
            'role': 'user',
            'content': 'still alive',
          },
        ],
      },
    );
    expect((stillWorks['choices'] as List), isNotEmpty);

    // 撤不存在的设备 → 404，不静默。
    final missing = await fixture.send(
      'DELETE',
      '/api/quiz/vision/device/dev-nope-9999',
      token: adminToken,
    );
    expect(missing.statusCode, HttpStatus.notFound);
    expect(missing.errorMessage, isNotEmpty);
  });

  test('同一 IP 每日签发上限 5 次，第 6 次 429（独立进程，避免串台）', () async {
    final capFixture = await _startServer();
    try {
      for (var i = 0; i < 5; i++) {
        final res = await capFixture.send(
          'POST',
          '/api/quiz/vision/device-token',
          body: {'deviceId': 'dev-cap-0000$i'},
        );
        expect(
          res.statusCode,
          HttpStatus.ok,
          reason: '第 ${i + 1} 次签发应放行，实际 ${res.statusCode} ${res.text}',
        );
      }
      final denied = await capFixture.send(
        'POST',
        '/api/quiz/vision/device-token',
        body: {'deviceId': 'dev-cap-00006'},
      );
      expect(denied.statusCode, HttpStatus.tooManyRequests);
      expect(denied.errorMessage, contains('签发过于频繁'));
    } finally {
      await capFixture.dispose();
    }
  });
}

Future<_Fixture> _startServer({Map<String, dynamic>? seedState}) async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();

  final stateFile = File(
    '${Directory.systemTemp.path}/box_quiz_vision_device_'
    '${DateTime.now().microsecondsSinceEpoch}.json',
  );
  if (seedState != null) {
    await stateFile.writeAsString(jsonEncode(seedState));
  }

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
    workingDirectory: Directory.current.path,
    environment: {
      'IMAGE_STATE_PATH': stateFile.path,
      'BOX_ADMIN_PASSWORD': 'test-admin-password',
    },
    includeParentEnvironment: true,
  );

  final stdoutText = StringBuffer();
  final stderrText = StringBuffer();
  // 必须持续把 stdout 读干：用 firstWhere 直接等就绪行会在命中时取消订阅、
  // 关掉子进程的 stdout，服务端紧接着写启动清单时 EPIPE 直接死掉
  // （症状是登录请求 "Connection closed before full header"）。
  final ready = Completer<void>();
  final stdoutSubscription = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        stdoutText.writeln(line);
        if (!ready.isCompleted &&
            line.contains('Box image platform quota server running')) {
          ready.complete();
        }
      });
  final stderrSubscription = process.stderr
      .transform(utf8.decoder)
      .listen(stderrText.write);

  await ready.future.timeout(
    const Duration(seconds: 120),
    onTimeout: () => fail(
      'server did not start in 120s: $stdoutText $stderrText',
    ),
  );

  return _Fixture(
    port: port,
    process: process,
    stateFile: stateFile,
    stdoutText: stdoutText,
    stdoutSubscription: stdoutSubscription,
    stderrText: stderrText,
    stderrSubscription: stderrSubscription,
  );
}

class _Fixture {
  _Fixture({
    required this.port,
    required this.process,
    required this.stateFile,
    required this.stdoutText,
    required this.stdoutSubscription,
    required this.stderrText,
    required this.stderrSubscription,
  });

  final int port;
  final Process process;
  final File stateFile;
  final StringBuffer stdoutText;
  final StreamSubscription<String> stdoutSubscription;
  final StringBuffer stderrText;
  final StreamSubscription<String> stderrSubscription;

  Future<_Response> send(
    String method,
    String path, {
    String? token,
    Object? body,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(
        method,
        Uri.parse('http://127.0.0.1:$port$path'),
      );
      if (token != null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $token',
        );
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      return _Response(response.statusCode, text);
    } finally {
      client.close(force: true);
    }
  }

  /// 断言 200 并返回解码后的 JSON 对象。
  Future<Map<String, dynamic>> ok(
    String method,
    String path, {
    String? token,
    Object? body,
  }) async {
    final res = await send(method, path, token: token, body: body);
    expect(
      res.statusCode,
      HttpStatus.ok,
      reason: '$method $path => ${res.statusCode} ${res.text}',
    );
    return res.json;
  }

  Future<void> dispose() async {
    process.kill();
    await process.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () => -1,
    );
    await stderrSubscription.cancel();
    await stdoutSubscription.cancel();
    if (await stateFile.exists()) await stateFile.delete();
  }
}

class _Response {
  _Response(this.statusCode, this.text);

  final int statusCode;
  final String text;

  Map<String, dynamic> get json => text.trim().isEmpty
      ? <String, dynamic>{}
      : Map<String, dynamic>.from(jsonDecode(text) as Map);

  /// 契约里所有失败都带 {"error":{"message":"..."}}，取出来断言文案。
  String get errorMessage {
    final error = json['error'];
    if (error is Map) return error['message']?.toString() ?? '';
    return '';
  }
}
