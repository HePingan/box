// 分享码的客户端契约：这些字段名（code / payload）是与后端的唯一接缝，
// 后端改了 App 不知道，就会静默变成「码拿到了但导入没内容」。
//
// 服务端那 11 条已经在冒烟脚本里跑过真实 HTTP，这里锁的是 App 侧解析：
//   1) createShareCode → POST /api/plugins/share，body 带 payload，读回 code；
//   2) fetchSharePayload → GET /api/plugins/share/<CODE>，码先规范成大写；
//   3) 服务端 404 时抛出带服务端原话的异常（不是「导入失败」四个字）。

import 'dart:convert';

import 'package:box/features/account/domain/account_models.dart';
import 'package:box/features/extensions/market/data/plugin_market_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _server = 'https://background.hpa888.top';

BoxAccountSession _session() => const BoxAccountSession(
  serverUrl: _server,
  token: 'test-token',
  user: BoxAccountUser(id: 'u_1', username: 'tester', role: 'user', status: 'normal'),
);

PluginMarketApi _api(MockClient client) =>
    PluginMarketApi(httpClient: client, loadSession: () async => _session());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('分享码 API 契约', () {
    test('创建分享码：POST 带上 payload，读回 code', () async {
      String? seenPath;
      String? seenMethod;
      Map<String, dynamic>? seenBody;

      final api = _api(
        MockClient((req) async {
          seenPath = req.url.path;
          seenMethod = req.method;
          seenBody = jsonDecode(req.body) as Map<String, dynamic>;
          expect(req.headers['Authorization'], 'Bearer test-token');
          return http.Response(
            jsonEncode({'code': '7K2M9Q', 'title': '音乐入口'}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final code = await api.createShareCode(
        payload: '{"customPlugins":[]}',
        title: '音乐入口',
      );

      expect(seenMethod, 'POST');
      expect(seenPath, '/api/plugins/share');
      expect(seenBody?['payload'], '{"customPlugins":[]}');
      expect(seenBody?['title'], '音乐入口');
      expect(code, '7K2M9Q');
    });

    test('取回分享码：码统一成大写，且不带 Authorization', () async {
      String? seenPath;
      String? seenAuth;

      final api = _api(
        MockClient((req) async {
          seenPath = req.url.path;
          seenAuth = req.headers['Authorization'];
          return http.Response(
            jsonEncode({
              'code': '7K2M9Q',
              'payload': '{"customPlugins":[{"id":"p1"}]}',
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final payload = await api.fetchSharePayload('7k2m9q');

      expect(seenPath, '/api/plugins/share/7K2M9Q', reason: '小写码要能直接用');
      expect(seenAuth, isNull, reason: '接收方可能没登录，不能要求 token');
      expect(payload, '{"customPlugins":[{"id":"p1"}]}');
    });

    test('码不存在：把服务端原话抛出来', () async {
      final api = _api(
        MockClient((req) async {
          return http.Response(
            jsonEncode({
              'error': {'message': '分享码不存在或已失效'},
            }),
            404,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      await expectLater(
        api.fetchSharePayload('ZZZZZZ'),
        throwsA(
          isA<PluginMarketApiException>()
              .having((e) => e.message, 'message', contains('不存在'))
              .having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });

    test('空码本地就挡住，不发请求', () async {
      var called = false;
      final api = _api(
        MockClient((req) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        api.fetchSharePayload('   '),
        throwsA(isA<PluginMarketApiException>()),
      );
      expect(called, isFalse);
    });

    test('服务端返回空 payload 时报错而不是导入空配置', () async {
      final api = _api(
        MockClient((req) async {
          return http.Response(
            jsonEncode({'code': '7K2M9Q', 'payload': ''}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      await expectLater(
        api.fetchSharePayload('7K2M9Q'),
        throwsA(
          isA<PluginMarketApiException>().having(
            (e) => e.message,
            'message',
            contains('没有内容'),
          ),
        ),
      );
    });
  });
}
