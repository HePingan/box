// P1-1 数据层回归测试：同步确实会把「风险已清除、恢复上架」的插件
// 计入 riskCleared —— 这是 plugin_tab.dart 提示用户的唯一数据来源。
//
// 已修复的真实缺陷：plugin_tab.dart 的 _syncInstalledStatuses 只消费
// result.risks，把 riskCleared 完整丢弃。若哪一天 sync 侧也不再产出
// riskCleared（例如误把 changed 条件改掉），用户同样看不到任何提示，
// 且不会有测试报错。本测试锁住数据侧契约。
import 'dart:convert';

import 'package:box/features/extensions/core/home_plugin_core.dart';
import 'package:box/features/extensions/market/data/plugin_market_api.dart';
import 'package:box/features/extensions/market/data/plugin_market_local_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 假服务端：对 /status 返回给定 status 列表。
  PluginMarketApi apiWithStatus(List<Map<String, dynamic>> items) {
    return PluginMarketApi(
      httpClient: MockClient((req) async {
        if (req.url.path.contains('/status')) {
          return http.Response(
            jsonEncode({'items': items}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('{}', 200);
      }),
      loadSession: () async => null,
    );
  }

  HomeCustomPluginConfig marketPlugin(
    String id, {
    bool risk = true,
    String status = 'yanked',
  }) =>
      HomeCustomPluginConfig(
        id: id,
        title: '测试插件',
        subtitle: '',
        iconCodePoint: 0xe1bd,
        colorValue: 0xFF112233,
        area: HomePluginArea.recommend,
        actionType: HomePluginActionType.toast,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        origin: 'user_market',
        enabled: false,
        marketStatus: status,
        marketRisk: risk,
        marketVersion: '1.0',
      );

  group('P1-1 riskCleared 数据契约', () {
    test('yanked 转 published 后必须计入 riskCleared', () async {
      final host = HomePluginHost.instance;
      await host.bootstrap();
      await host.addCustomPlugin(marketPlugin('p1_1_cleared'));

      final sync = PluginMarketLocalSync(
        api: apiWithStatus([
          {
            'id': 'p1_1_cleared',
            'status': 'published',
            'version': '1.0',
            'packageSha256': '',
          },
        ]),
        host: host,
      );

      final result = await sync.syncInstalledStatuses(force: true);

      expect(
        result.riskCleared,
        1,
        reason: 'P1-1：插件从 yanked 恢复上架，riskCleared 必须为 1，'
            '否则 plugin_tab 无从提示用户「已恢复上架，可手动启用」',
      );
      expect(result.yankedDisabled, 0);
      expect(
        host.allPlugins
            .where((p) => p.id == 'p1_1_cleared')
            .map((p) => p.customConfig?.marketRisk)
            .firstOrNull,
        isFalse,
        reason: '恢复上架后风险标记应被清掉',
      );
    });

    test('本来就是 published 且无变化时 riskCleared 不得虚增', () async {
      final host = HomePluginHost.instance;
      await host.bootstrap();
      await host.addCustomPlugin(
        marketPlugin('p1_1_noop', risk: false, status: 'published'),
      );

      final sync = PluginMarketLocalSync(
        api: apiWithStatus([
          {
            'id': 'p1_1_noop',
            'status': 'published',
            'version': '1.0',
            'packageSha256': '',
          },
        ]),
        host: host,
      );

      final result = await sync.syncInstalledStatuses(force: true);

      expect(
        result.riskCleared,
        0,
        reason: '无实际状态变化不得计入 riskCleared，'
            '否则用户会收到「已恢复上架」的误导提示',
      );
    });
  });
}
