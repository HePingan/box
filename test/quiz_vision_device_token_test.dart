// 匿名设备令牌：签发客户端 + 凭证解析器（客户端零内置密钥）。
//
// 契约（与服务端同时冻结，字段名/路径/状态码都是线缆的一部分）：
//   POST <账号服务器>/api/quiz/vision/device-token
//   body:   {"deviceId": "<8-64 字符的不透明设备标识>"}
//   200  →  {"token":"<64 位 hex>","deviceId":"...","dailyCap":100,"expiresInDays":null}
//   429  →  限流；400 → 设备标识被拒。
//
// 本文件锁三件事：
//   1) 签发请求的形状（路径/方法/body）与失败文案（可读、不抛、不带 token）；
//   2) 解析器分流：未登录签发/复用、已登录不签发、手填凭证完全不碰这条链；
//   3) 一切失败都返回 unavailable + 原因（**不静默降级**：内置 key 已删除）。
import 'dart:convert';

import 'package:box/features/account/data/account_store.dart';
import 'package:box/features/account/domain/account_models.dart';
import 'package:box/features/quiz_plugin/data/quiz_vision_credentials.dart';
import 'package:box/features/quiz_plugin/data/quiz_vision_device_token_client.dart';
import 'package:box/features/quiz_plugin/data/quiz_vision_device_token_store.dart';
import 'package:box/features/quiz_plugin/domain/quiz_config.dart';
import 'package:box/features/quiz_plugin/domain/quiz_vision_endpoint.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _server = 'https://background.hpa888.top';
const _proxyBase = 'https://background.hpa888.top/api/quiz/vision';
const _deviceTokenPath = '/api/quiz/vision/device-token';

/// 内存版安全存储（单测里没有平台通道，Keystore 实现不可用）。
class _MemoryStore implements QuizVisionDeviceTokenStore {
  _MemoryStore({this.deviceId, this.token, this.throwOnRead = false});

  String? deviceId;
  String? token;
  bool throwOnRead;
  int tokenWrites = 0;
  int tokenClears = 0;

  @override
  Future<String?> readDeviceId() async {
    if (throwOnRead) throw StateError('keystore 读失败');
    return deviceId;
  }

  @override
  Future<void> writeDeviceId(String value) async {
    deviceId = value;
  }

  @override
  Future<String?> readDeviceToken() async {
    if (throwOnRead) throw StateError('keystore 读失败');
    return token;
  }

  @override
  Future<void> writeDeviceToken(String value) async {
    tokenWrites++;
    token = value;
  }

  @override
  Future<void> clearDeviceToken() async {
    tokenClears++;
    token = null;
  }
}

/// 账号存储替身：不碰 SharedPreferences（真实实现在最后一个用例里单独验）。
class _FakeAccountStore extends BoxAccountStore {
  _FakeAccountStore({
    this.session,
    this.throwOnLoad = false,
  });

  final BoxAccountSession? session;
  final bool throwOnLoad;

  @override
  Future<BoxAccountSession?> loadSession() async {
    if (throwOnLoad) throw StateError('登录态读取炸了');
    return session;
  }

  @override
  Future<String> loadServerUrl() async {
    if (throwOnLoad) throw StateError('服务器地址读取炸了');
    return _server;
  }
}

BoxAccountSession _session() => const BoxAccountSession(
  serverUrl: _server,
  token: 'sess-token-abc123',
  user: BoxAccountUser(
    id: 'u1',
    username: 'tester',
    role: 'user',
    status: 'active',
  ),
);

/// 假签发服务端：记录每个请求的 path 与 deviceId，便于断言「复用/重签」。
class _FakeIssuer {
  _FakeIssuer({
    this.status = 200,
    this.throwOnRequest = false,
    this.body = '',
  });

  final int status;
  final bool throwOnRequest;
  final String body;

  final List<String> paths = [];
  final List<String> deviceIds = [];
  int calls = 0;

  QuizVisionDeviceTokenClient get client => QuizVisionDeviceTokenClient(
    httpClient: MockClient((req) async {
      calls++;
      paths.add(req.url.path);
      final sent = jsonDecode(req.body) as Map<String, dynamic>;
      deviceIds.add(sent['deviceId']?.toString() ?? '');
      if (throwOnRequest) throw Exception('网络不可达');
      if (status != 200) {
        return http.Response(jsonEncode({'error': 'server says no'}), status);
      }
      return http.Response(
        body.isNotEmpty
            ? body
            : jsonEncode({
                'token': 'device-token-$calls',
                'deviceId': sent['deviceId'],
                'dailyCap': 100,
                'expiresInDays': null,
              }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
}

QuizVisionCredentialResolver _resolver({
  required _MemoryStore store,
  _FakeIssuer? issuer,
  BoxAccountStore? accountStore,
}) => QuizVisionCredentialResolver(
  store: store,
  client: issuer?.client,
  accountStore: accountStore ?? _FakeAccountStore(),
);

void main() {
  group('generateQuizDeviceId（不透明设备标识）', () {
    test('长度落在契约区间（8~64）且为十六进制', () {
      final id = generateQuizDeviceId();
      expect(id.length, inInclusiveRange(8, 64));
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(id), isTrue, reason: '契约：不透明串 $id');
    });

    test('两次生成不同（随机，不是硬件号）', () {
      expect(generateQuizDeviceId(), isNot(generateQuizDeviceId()));
    });
  });

  group('QuizVisionDeviceTokenClient.issue（线缆契约）', () {
    test('成功：POST /api/quiz/vision/device-token，body 带 deviceId，取回 token', () async {
      final issuer = _FakeIssuer();
      final r = await issuer.client.issue(
        serverUrl: '$_server/',
        deviceId: 'a1b2c3d4e5f60718',
      );
      expect(r.isSuccess, isTrue);
      expect(r.token, 'device-token-1');
      expect(issuer.paths.single, _deviceTokenPath);
      expect(issuer.deviceIds.single, 'a1b2c3d4e5f60718');
      expect(r.error, isEmpty);
    });

    test('429 → 可读原因（限流口径），不抛异常', () async {
      final r = await _FakeIssuer(status: 429).client.issue(
        serverUrl: _server,
        deviceId: 'a1b2c3d4e5f60718',
      );
      expect(r.isSuccess, isFalse);
      expect(r.token, isNull);
      expect(r.error, contains('429'));
      expect(r.error, contains('稍后'));
    });

    test('400 → 可读原因（设备标识被拒）', () async {
      final r = await _FakeIssuer(status: 400).client.issue(
        serverUrl: _server,
        deviceId: 'a1b2c3d4e5f60718',
      );
      expect(r.error, contains('400'));
      expect(r.error, contains('设备标识'));
    });

    test('网络异常 → 可读原因，不抛', () async {
      final r = await _FakeIssuer(throwOnRequest: true).client.issue(
        serverUrl: _server,
        deviceId: 'a1b2c3d4e5f60718',
      );
      expect(r.isSuccess, isFalse);
      expect(r.error, contains('请求异常'));
    });

    test('200 但响应缺 token → 如实报错（不许返回空 token 冒充成功）', () async {
      final r = await _FakeIssuer(body: '{"deviceId":"a1b2c3d4e5f60718"}').client
          .issue(serverUrl: _server, deviceId: 'a1b2c3d4e5f60718');
      expect(r.isSuccess, isFalse);
      expect(r.error, contains('token'));
    });

    test('200 但响应不是 JSON → 如实报错', () async {
      final r = await _FakeIssuer(body: '<html>502 bad gateway</html>').client
          .issue(serverUrl: _server, deviceId: 'a1b2c3d4e5f60718');
      expect(r.isSuccess, isFalse);
      expect(r.error, contains('无法解析'));
    });

    test('设备标识长度不合法 → 本地拒绝，不发请求', () async {
      final issuer = _FakeIssuer();
      final r = await issuer.client.issue(serverUrl: _server, deviceId: 'short');
      expect(r.isSuccess, isFalse);
      expect(r.error, contains('8~64'));
      expect(issuer.calls, 0, reason: '契约外的标识没必要浪费一次请求');
    });

    test('服务器地址为空 → 本地拒绝，不发请求', () async {
      final issuer = _FakeIssuer();
      final r = await issuer.client.issue(
        serverUrl: '  ',
        deviceId: 'a1b2c3d4e5f60718',
      );
      expect(r.isSuccess, isFalse);
      expect(issuer.calls, 0);
    });
  });

  group('QuizVisionCredentialResolver 凭证解析', () {
    test('未登录：签发设备令牌 → deviceProxy，令牌与设备标识都落盘', () async {
      final store = _MemoryStore();
      final issuer = _FakeIssuer();
      final ep = await _resolver(store: store, issuer: issuer).resolve(
        const QuizConfig(),
      );

      expect(ep.mode, QuizVisionMode.deviceProxy);
      expect(ep.baseUrl, _proxyBase);
      expect(ep.apiKey, 'device-token-1');
      expect(issuer.paths.single, _deviceTokenPath);
      expect(
        RegExp(r'^[0-9a-f]{8,64}$').hasMatch(issuer.deviceIds.single),
        isTrue,
        reason: '送出的 deviceId 必须符合契约；实收 ${issuer.deviceIds.single}',
      );
      expect(store.deviceId, issuer.deviceIds.single, reason: '设备标识要落盘复用');
      expect(store.token, 'device-token-1', reason: '签发的令牌要落盘，下次直接复用');
    });

    test('未登录 + 本机已有令牌：直接复用，不再签发', () async {
      final store = _MemoryStore(
        deviceId: 'a1b2c3d4e5f60718',
        token: 'device-token-cached',
      );
      final issuer = _FakeIssuer();
      final ep = await _resolver(store: store, issuer: issuer).resolve(
        const QuizConfig(),
      );

      expect(ep.mode, QuizVisionMode.deviceProxy);
      expect(ep.apiKey, 'device-token-cached');
      expect(issuer.calls, 0, reason: '本机已有令牌就不该再打签发接口');
    });

    test('未登录 + 签发 429 → unavailable + 可读原因，不写盘、不回落内置 key', () async {
      final store = _MemoryStore();
      final ep = await _resolver(
        store: store,
        issuer: _FakeIssuer(status: 429),
      ).resolve(const QuizConfig());

      expect(ep.mode, QuizVisionMode.unavailable);
      expect(ep.isUnavailable, isTrue);
      expect(ep.errorMessage, contains('429'));
      expect(ep.baseUrl, isEmpty, reason: '拿不到凭证就不该带端点出去');
      expect(store.token, isNull, reason: '没签发成功就不许写盘');
      expect(ep.apiKey, isEmpty);
    });

    test('未登录 + 签发网络异常 → unavailable + 可读原因', () async {
      final store = _MemoryStore();
      final ep = await _resolver(
        store: store,
        issuer: _FakeIssuer(throwOnRequest: true),
      ).resolve(const QuizConfig());

      expect(ep.mode, QuizVisionMode.unavailable);
      expect(ep.errorMessage, isNotEmpty);
      expect(store.token, isNull);
    });

    test('已登录：platformProxy 用 session token，不签发、不碰设备令牌存储', () async {
      final store = _MemoryStore();
      final issuer = _FakeIssuer();
      final ep = await _resolver(
        store: store,
        issuer: issuer,
        accountStore: _FakeAccountStore(session: _session()),
      ).resolve(const QuizConfig());

      expect(ep.mode, QuizVisionMode.platformProxy);
      expect(ep.apiKey, 'sess-token-abc123');
      expect(ep.baseUrl, _proxyBase);
      expect(issuer.calls, 0);
      expect(store.tokenWrites, 0, reason: '登录用户不该被写设备令牌');
    });

    test('手填 key：ownKey，且不签发、不读不写设备存储', () async {
      final store = _MemoryStore(throwOnRead: true); // 一旦被读就会炸
      final issuer = _FakeIssuer();
      final ep = await _resolver(store: store, issuer: issuer).resolve(
        const QuizConfig(apiKey: 'sk-user-self-key'),
      );

      expect(ep.mode, QuizVisionMode.ownKey);
      expect(ep.apiKey, 'sk-user-self-key');
      expect(issuer.calls, 0);
      expect(store.tokenWrites, 0);
    });

    test('安全存储读取异常：仍能签发走代理（不把整条读屏卡死）', () async {
      final store = _MemoryStore(throwOnRead: true);
      final issuer = _FakeIssuer();
      final ep = await _resolver(store: store, issuer: issuer).resolve(
        const QuizConfig(),
      );

      expect(ep.mode, QuizVisionMode.deviceProxy);
      expect(ep.apiKey, 'device-token-1');
    });

    test('登录态读取异常 → 按未登录走设备令牌（不静默停摆）', () async {
      final store = _MemoryStore();
      final issuer = _FakeIssuer();
      final ep = await _resolver(
        store: store,
        issuer: issuer,
        accountStore: _FakeAccountStore(throwOnLoad: true),
      ).resolve(const QuizConfig());

      expect(ep.mode, QuizVisionMode.deviceProxy);
      expect(
        ep.baseUrl,
        _proxyBase,
        reason: '地址读失败要回落到线上默认账号服务器，而不是放弃读屏',
      );
    });

    test('令牌被拒后 invalidateDeviceToken：清掉本机令牌，重签复用同一设备标识', () async {
      final store = _MemoryStore();
      final issuer = _FakeIssuer();
      final resolver = _resolver(store: store, issuer: issuer);

      final first = await resolver.resolve(const QuizConfig());
      expect(first.mode, QuizVisionMode.deviceProxy);

      await resolver.invalidateDeviceToken();
      expect(store.tokenClears, 1);
      expect(store.token, isNull);
      expect(
        store.deviceId,
        isNotNull,
        reason: '只清令牌：服务端按设备标识记账/限额，标识不能换',
      );

      final second = await resolver.resolve(const QuizConfig());
      expect(second.mode, QuizVisionMode.deviceProxy);
      expect(second.apiKey, 'device-token-2', reason: '清掉后应重新签发（自愈）');
      expect(issuer.calls, 2);
      expect(
        issuer.deviceIds[1],
        issuer.deviceIds[0],
        reason: '重签必须复用同一设备标识（否则等于换了一台设备）',
      );
    });

    test('真实 BoxAccountStore + 无持久化登录态 → 视为未登录并签发', () async {
      // 这一条不打桩账号存储：验的就是「真机上未登录」这条真实路径。
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = _MemoryStore();
      final issuer = _FakeIssuer();
      final ep = await QuizVisionCredentialResolver(
        store: store,
        client: issuer.client,
        accountStore: BoxAccountStore(),
      ).resolve(const QuizConfig());

      expect(ep.mode, QuizVisionMode.deviceProxy);
      expect(ep.baseUrl, _proxyBase, reason: '取用户保存的服务器地址（未存过=线上默认）');
      expect(issuer.calls, 1);
    });
  });

  group('resolveAnonymous（登录档被拒时的降级入口）', () {
    test('本机有会话令牌时：resolve 走登录档，resolveAnonymous 仍走匿名档', () async {
      final store = _MemoryStore(token: 'cached-device-token');
      final resolver = _resolver(
        store: store,
        accountStore: _FakeAccountStore(session: _session()),
      );

      final normal = await resolver.resolve(const QuizConfig());
      expect(normal.mode, QuizVisionMode.platformProxy);
      expect(normal.apiKey, 'sess-token-abc123', reason: '有会话就用会话');
      expect(
        normal.baseUrl,
        _proxyBase,
        reason: '登录档与匿名档是同一条代理路径',
      );

      final anon = await resolver.resolveAnonymous(const QuizConfig());
      expect(
        anon.mode,
        QuizVisionMode.deviceProxy,
        reason: '降级必须跳过登录档（会话已失效，再拿它重试只会再 401）',
      );
      expect(anon.apiKey, 'cached-device-token');
      expect(anon.baseUrl, _proxyBase);
    });

    test('本机没有设备令牌 → 签发一次并复用同一设备标识', () async {
      final store = _MemoryStore();
      final issuer = _FakeIssuer();
      final resolver = _resolver(store: store, issuer: issuer);

      final anon = await resolver.resolveAnonymous(const QuizConfig());

      expect(anon.mode, QuizVisionMode.deviceProxy);
      expect(anon.apiKey, 'device-token-1');
      expect(issuer.calls, 1);
      expect(issuer.paths.single, _deviceTokenPath);
      expect(store.token, 'device-token-1', reason: '签发后落盘，下次直接复用');
      expect(store.deviceId, isNotNull);
    });

    test('签发失败 → unavailable + 可读原因（不静默：内置 key 已删除）', () async {
      final resolver = _resolver(
        store: _MemoryStore(),
        issuer: _FakeIssuer(status: 429),
      );

      final anon = await resolver.resolveAnonymous(const QuizConfig());

      expect(anon.isUnavailable, isTrue);
      expect(anon.errorMessage, contains('429'));
    });

    test('手填了 key/端点 → 原样直连，绝不被改道到匿名代理', () async {
      final issuer = _FakeIssuer();
      final resolver = _resolver(store: _MemoryStore(), issuer: issuer);

      final anon = await resolver.resolveAnonymous(
        const QuizConfig(
          allowExternalApi: true,
          apiUrl: 'https://newapi.hpa888.top/v1',
          apiKey: 'sk-user-own',
        ),
      );

      expect(anon.mode, QuizVisionMode.ownKey);
      expect(anon.apiKey, 'sk-user-own');
      expect(issuer.calls, 0, reason: '手填凭证的用户不碰平台这条链');
    });
  });
}
