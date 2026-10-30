// 举报链路（提交 → 结案）回归测试。
//
// 已修复的真实缺口（2026-10-30）：
//   1. 服务端只有「提交举报」「列出举报」，**没有结案接口** —— status 永远是
//      open，管理端 openCount 只增不减，举报队列永久堆积。
//   2. App 侧 `PluginMarketApi.reportPlugin()` 早就写好，但**全仓零调用**：
//      市场页没有举报入口，用户报不了，管理端队列自然永远空。
//   3. 下架插件后，该插件的 open 举报仍然挂着。
//
// 本文件锁三件事：
//   A. API 契约（真发请求，用 MockClient 抓 path/method/body/头）
//   B. 市场页确实接了举报入口（源码契约 + 文案）
//   C. 管理端确实能结案（源码契约，调 adminResolveReport 且 resolve/dismiss 都传）
import 'dart:convert';
import 'dart:io';

import 'package:box/features/account/domain/account_models.dart';
import 'package:box/features/extensions/market/data/plugin_market_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _readCode(String path) {
  return File(path)
      .readAsLinesSync()
      .map((line) {
        final idx = line.indexOf('//');
        return idx >= 0 ? line.substring(0, idx) : line;
      })
      .join('\n');
}

BoxAccountSession _session() => const BoxAccountSession(
      serverUrl: 'https://background.hpa888.top',
      token: 'test-token',
      user: BoxAccountUser(id: 'u_1', username: 'tester', role: 'user', status: 'normal'),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A. API 契约', () {
    test('reportPlugin 打到 /api/plugin-market/<id>/report 并带 reason', () async {
      http.Request? captured;
      final api = PluginMarketApi(
        httpClient: MockClient((req) async {
          captured = req;
          return http.Response(
            jsonEncode({'id': 'pr_1', 'status': 'open'}),
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
        loadSession: () async => _session(),
      );

      final body = await api.reportPlugin('user.u_1.demo', reason: '内容与描述不符');
      expect(body['status'], 'open');
      expect(captured, isNotNull);
      expect(captured!.method, 'POST');
      expect(captured!.url.path, '/api/plugin-market/user.u_1.demo/report');
      expect(jsonDecode(captured!.body)['reason'], '内容与描述不符');
      expect(captured!.headers['Authorization'], 'Bearer test-token');
    });

    test('adminResolveReport(resolve) 打到 .../resolve，返回 openCount', () async {
      http.Request? captured;
      final api = PluginMarketApi(
        httpClient: MockClient((req) async {
          captured = req;
          return http.Response(
            jsonEncode({
              'report': {'id': 'pr_1', 'status': 'resolved'},
              'openCount': 0,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        loadSession: () async => _session(),
      );

      final body = await api.adminResolveReport('pr_1', resolve: true, note: '已处理');
      expect(body['openCount'], 0);
      expect(captured!.method, 'POST');
      expect(captured!.url.path, '/admin/plugins/reports/pr_1/resolve');
      expect(jsonDecode(captured!.body)['note'], '已处理');
    });

    test('adminResolveReport(dismiss) 打到 .../dismiss', () async {
      http.Request? captured;
      final api = PluginMarketApi(
        httpClient: MockClient((req) async {
          captured = req;
          return http.Response(
            jsonEncode({'report': {'id': 'pr_2', 'status': 'dismissed'}, 'openCount': 1}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        loadSession: () async => _session(),
      );

      await api.adminResolveReport('pr_2', resolve: false);
      expect(captured!.url.path, '/admin/plugins/reports/pr_2/dismiss');
    });

    test('服务端冲突（已结案 409）要抛带 message 的异常', () async {
      final api = PluginMarketApi(
        httpClient: MockClient((req) async {
          return http.Response(
            jsonEncode({
              'error': {'message': '该举报已结案：resolved'}
            }),
            409,
            headers: {'content-type': 'application/json'},
          );
        }),
        loadSession: () async => _session(),
      );

      await expectLater(
        api.adminResolveReport('pr_1', resolve: true),
        throwsA(isA<PluginMarketApiException>()
            .having((e) => e.statusCode, 'statusCode', 409)
            .having((e) => e.message, 'message', contains('已结案'))),
      );
    });
  });

  group('B. 市场页的举报入口确实接线', () {
    final src =
        _readCode('lib/features/extensions/market/presentation/plugin_market_page.dart');

    test('页面调用 reportPlugin', () {
      expect(src, matches(RegExp(r'_reportApi\.reportPlugin\(')));
    });

    test('卡片上有「举报」入口，且只在服务端清单来源显示', () {
      expect(src, contains('const Text(\'举报\''));
      expect(src, matches(RegExp(r'_reportableSource\s*=>')));
      expect(src, contains("_marketSource == 'remote'"));
      expect(src, contains("_marketSource == 'cache'"));
    });

    test('举报原因走确认对话框，不是一发就走', () {
      expect(src, contains("'举报插件'"));
      expect(src, contains("'提交举报'"));
    });
  });

  group('C. 管理端能结案', () {
    final src =
        _readCode('lib/features/admin/presentation/widgets/plugin_market_admin_tab.dart');

    test('调用 adminResolveReport，且 resolve/dismiss 两条路径都在', () {
      expect(src, matches(RegExp(r'_api\.adminResolveReport\(')));
      expect(src, contains('_resolveReport(r, resolve: true)'));
      expect(src, contains('_resolveReport(r, resolve: false)'));
    });

    test('举报卡片菜单里三个动作都在（成立/驳回/下架）', () {
      expect(src, contains("'举报成立（结案）'"));
      expect(src, contains("'举报不成立（驳回）'"));
      expect(src, contains("'下架插件（自动结案）'"));
    });
  });
}
