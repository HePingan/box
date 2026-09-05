import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:box/features/account/data/account_client.dart';
import 'package:box/features/account/domain/account_models.dart';

/// A2 / A4 的红灯：错误语义与 quota 承接，都在客户端层可测。
void main() {
  http.Client jsonClient(
    int status,
    Object body, {
    Map<String, String> headers = const {},
    void Function(http.Request request)? onRequest,
  }) {
    return MockClient((request) async {
      onRequest?.call(request);
      return http.Response(
        jsonEncode(body),
        status,
        headers: {
          'content-type': 'application/json; charset=utf-8',
          ...headers,
        },
      );
    });
  }

  group('A2 登录节流 429 的错误语义', () {
    test('429 透传服务端秒数文案，不再拼通用「请求失败。」', () async {
      final client = BoxAccountClient(
        httpClient: jsonClient(
          429,
          {
            'error': {'message': '登录失败次数过多，请 42 秒后再试。'},
          },
          headers: {'Retry-After': '42'},
        ),
      );

      await expectLater(
        client.login(
          serverUrl: 'https://example.com',
          username: 'someone',
          password: 'bad',
        ),
        throwsA(
          isA<BoxAccountException>()
              .having((e) => e.statusCode, 'statusCode', 429)
              // 服务端已经把秒数说清楚了，客户端不该再补一句自相矛盾的通用话。
              .having((e) => e.message, 'message', isNot(contains('请求失败。')))
              .having((e) => e.message, 'message', contains('42 秒')),
        ),
      );
    });

    test('429 缺少服务端文案时给出可操作提示，而非通用「请求失败。」', () async {
      final client = BoxAccountClient(
        httpClient: jsonClient(
          429,
          <String, dynamic>{},
          headers: {'Retry-After': '15'},
        ),
      );

      await expectLater(
        client.login(
          serverUrl: 'https://example.com',
          username: 'someone',
          password: 'bad',
        ),
        throwsA(
          isA<BoxAccountException>().having(
            (e) => e.message,
            'message',
            allOf(contains('15'), isNot(contains('请求失败。'))),
          ),
        ),
      );
    });

    test('401 仍保留原有的账号密码错误提示', () async {
      final client = BoxAccountClient(
        httpClient: jsonClient(401, {
          'error': {'message': '用户名或密码错误'},
        }),
      );

      await expectLater(
        client.login(
          serverUrl: 'https://example.com',
          username: 'someone',
          password: 'bad',
        ),
        throwsA(
          isA<BoxAccountException>().having(
            (e) => e.message,
            'message',
            contains('账号或密码错误'),
          ),
        ),
      );
    });
  });

  group('A4 注册响应里的 quota 不该被丢掉', () {
    test('register 接住服务端已返回的 quota', () async {
      final client = BoxAccountClient(
        httpClient: jsonClient(201, {
          'token': 'box_session_abc',
          'user': {
            'id': 'u1',
            'username': 'newbie',
            'nickname': 'newbie',
            'role': 'user',
            'status': 'normal',
          },
          'quota': {
            'remaining': 5,
            'dailyLimit': 5,
            'usedToday': 0,
            'totalLimit': 5,
            'status': 'normal',
            'message': '',
          },
        }),
      );

      final result = await client.register(
        serverUrl: 'https://example.com',
        username: 'newbie',
        password: 'secret123',
      );

      expect(result.session.user.username, 'newbie');
      // 服务端注册响应本来就带 quota，客户端过去只取 token/user 白丢了。
      expect(result.quota, isNotNull);
      expect(result.quota!.remaining, 5);
    });

    test('register 响应没有 quota 时不报错，quota 为空', () async {
      final client = BoxAccountClient(
        httpClient: jsonClient(201, {
          'token': 'box_session_abc',
          'user': {
            'id': 'u1',
            'username': 'newbie',
            'role': 'user',
            'status': 'normal',
          },
        }),
      );

      final result = await client.register(
        serverUrl: 'https://example.com',
        username: 'newbie',
        password: 'secret123',
      );

      expect(result.session.token, 'box_session_abc');
      expect(result.quota, isNull);
    });
  });

  group('A4 额度查询', () {
    test('fetchMyQuota 带 Bearer 打到 /api/image/quota', () async {
      Uri? seen;
      String? auth;
      final client = BoxAccountClient(
        httpClient: jsonClient(
          200,
          {
            'remaining': 3,
            'dailyLimit': 5,
            'usedToday': 2,
            'totalLimit': 5,
            'status': 'normal',
            'message': '',
          },
          onRequest: (request) {
            seen = request.url;
            auth = request.headers['Authorization'];
          },
        ),
      );

      final quota = await client.fetchMyQuota(
        serverUrl: 'https://example.com',
        token: 'tok',
      );

      expect(seen?.path, '/api/image/quota');
      expect(auth, 'Bearer tok');
      expect(quota.remaining, 3);
      expect(quota.usedToday, 2);
    });
  });
}
