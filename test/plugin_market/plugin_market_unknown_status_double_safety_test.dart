// P1-4 回归测试：`unknown` 状态（商店已无此插件）必须与 `yanked` 一样
// 同时落 marketStatus='yanked' + marketRisk=true 双保险。
//
// 已修复的真实缺陷：plugin_market_local_sync.dart 的 status 分支
//   - 'yanked'  → copyWith(marketStatus:'yanked', marketRisk:true, ...)
//   - 'unknown' → copyWith(marketRisk:true, ...)   ← 漏了 marketStatus
// 下游多处按 `marketStatus == 'yanked'` 判定风险：
//   - plugin_market_local_sync.dart:119  wasRisk
//   - home_plugin_core.dart 列表项门禁
//   - plugin_tab.dart 安装提示
// 只置 marketRisk 会让「商店已无此插件」漏过这些按状态判定的门禁，
// 且 UI「已下架」文案取不到正确状态。

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

  HomeCustomPluginConfig userMarketPlugin(String id) =>
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
        enabled: true,
        marketStatus: 'published',
        marketVersion: '1.0',
      );

  group('P1-4 unknown 状态双保险', () {
    test('status=unknown 时必须同时落 marketStatus=yanked 与 marketRisk=true', () async {
      final host = HomePluginHost.instance;
      await host.bootstrap();
      // 清掉上一条用例可能留下的状态，保证幂等。
      await host.addCustomPlugin(userMarketPlugin('p1_4_unknown'));

      final sync = PluginMarketLocalSync(
        api: apiWithStatus([
          {'id': 'p1_4_unknown', 'status': 'unknown'},
        ]),
        host: host,
      );

      final result = await sync.syncInstalledStatuses(force: true);

      final cfg = host
          .allPlugins
          .where((p) => p.id == 'p1_4_unknown')
          .map((p) => p.customConfig)
          .firstOrNull;
      expect(cfg, isNotNull, reason: '插件应仍在列表中');
      expect(cfg!.marketRisk, isTrue, reason: '风险标记必须置位');
      expect(
        cfg.marketStatus,
        'yanked',
        reason: 'P1-4：unknown 必须与 yanked 一样落 marketStatus，'
            '否则下游按 marketStatus==yanked 判定的门禁会漏掉它',
      );
      expect(cfg.enabled, isFalse, reason: '风险插件应被禁用');
      expect(result.risks.map((r) => r.kind), contains(PluginRiskKind.yanked));
    });

    test('status=yanked 同样落 marketStatus=yanked（对照组，确保未回归）', () async {
      final host = HomePluginHost.instance;
      await host.bootstrap();
      await host.addCustomPlugin(userMarketPlugin('p1_4_yanked'));

      final sync = PluginMarketLocalSync(
        api: apiWithStatus([
          {'id': 'p1_4_yanked', 'status': 'yanked', 'yankNote': '违规'},
        ]),
        host: host,
      );

      await sync.syncInstalledStatuses(force: true);

      final cfg = host
          .allPlugins
          .where((p) => p.id == 'p1_4_yanked')
          .map((p) => p.customConfig)
          .firstOrNull;
      expect(cfg!.marketStatus, 'yanked');
      expect(cfg.marketRisk, isTrue);
      expect(cfg.enabled, isFalse);
    });
  });
}
