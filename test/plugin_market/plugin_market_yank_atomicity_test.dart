// P1-3 回归测试：yank 强制禁用不得依赖「循环开始时的快照」判断 enabled。
//
// 已修复的真实缺陷（plugin_market_local_sync.dart）：
//   final plugin = marketPlugins.where((p) => p.id == id).firstOrNull;
//   ...
//   await _host.addCustomPlugin(next);          // 已把 enabled:false 写进 config
//   if (plugin.enabled) {                       // ← 快照里的旧值！
//     await _host.toggleEnabled(id, false);
//   }
//
// 竞态成因：`plugin.enabled` 取的是**本次同步开始前**的列表快照。若同一插件
// 在循环开始后、走到这里之前被其它路径改过 enabled（例如用户在列表里刚点了
// 启用），这里读到的是过时值：
//   - 快照 enabled=true → 多调一次 toggle。此时 config 已是 marketRisk，
//     toggleEnabled 的「下架插件禁止重新启用」守卫只在 enabled==true 时生效，
//     这里是关，不会误伤，但多花一次持久化且触发 onDisabled 生命周期回调。
//   - 快照 enabled=false → 跳过 toggle。若另一路径刚把它启用，插件会带着
//     marketRisk 保持启用状态直到下一次同步。
//
// 修复：addCustomPlugin 后**无条件** toggleEnabled(id, false)。
//（addCustomPlugin 内的 _normalizeForRegister 已按 config.enabled 归一化，
//  无条件 toggle 幂等，且确保「下架必禁用」不依赖任何时序假设。）

import 'dart:convert';
import 'dart:io';

import 'package:box/features/extensions/core/home_plugin_core.dart';
import 'package:box/features/extensions/market/data/plugin_market_api.dart';
import 'package:box/features/extensions/market/data/plugin_market_local_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 读源码并剥掉 `//` 行注释 —— 否则解释性注释里出现的标识符会被误判成用法。
String _readLocalSyncSource() {
  const path =
      'lib/features/extensions/market/data/plugin_market_local_sync.dart';
  return File(path)
      .readAsLinesSync()
      .map((line) {
        final idx = line.indexOf('//');
        return idx >= 0 ? line.substring(0, idx) : line;
      })
      .join('\n');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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
    required bool enabled,
    String status = 'published',
  }) =>
      HomeCustomPluginConfig(
        id: id,
        title: 'P1-3 插件',
        subtitle: '',
        iconCodePoint: 0xe1bd,
        colorValue: 0xFF112233,
        area: HomePluginArea.recommend,
        actionType: HomePluginActionType.toast,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        origin: 'user_market',
        enabled: enabled,
        marketStatus: status,
        marketVersion: '1.0',
      );

  group('P1-3 yank 禁用原子性', () {
    test('yanked 后最终必须是禁用态（无论循环中 enabled 被如何改动）', () async {
      final host = HomePluginHost.instance;
      await host.bootstrap();
      await host.addCustomPlugin(marketPlugin('p1_3_yanked', enabled: true));

      final sync = PluginMarketLocalSync(
        api: apiWithStatus([
          {'id': 'p1_3_yanked', 'status': 'yanked', 'yankNote': '违规'},
        ]),
        host: host,
      );

      await sync.syncInstalledStatuses(force: true);

      HomePlugin? after() => host.allPlugins
          .where((p) => p.id == 'p1_3_yanked')
          .firstOrNull;

      expect(after()?.enabled, isFalse, reason: '下架插件必须被禁用');
      expect(after()?.customConfig?.enabled, isFalse);

      // 幂等：再同步一次不得把状态又改坏
      await sync.syncInstalledStatuses(force: true);
      expect(after()?.enabled, isFalse);
    });

    test('unknown 状态同样必须落到禁用态', () async {
      final host = HomePluginHost.instance;
      await host.bootstrap();
      await host.addCustomPlugin(marketPlugin('p1_3_unknown', enabled: true));

      final sync = PluginMarketLocalSync(
        api: apiWithStatus([
          {'id': 'p1_3_unknown', 'status': 'unknown'},
        ]),
        host: host,
      );

      await sync.syncInstalledStatuses(force: true);

      final after = host.allPlugins
          .where((p) => p.id == 'p1_3_unknown')
          .firstOrNull;
      expect(after?.enabled, isFalse);
      expect(after?.customConfig?.marketStatus, 'yanked');
    });

    test('源码不得再用循环开始时的快照 plugin.enabled 做条件 toggle', () {
      final src = _readLocalSyncSource();
      expect(
        src,
        isNot(matches(RegExp(r'if\s*\(\s*plugin\.enabled\s*\)'))),
        reason: 'P1-3：if (plugin.enabled) 依赖同步开始时的列表快照，'
            '与 addCustomPlugin 非原子；必须改为无条件 toggleEnabled',
      );
    });

    test('源码必须在 addCustomPlugin 之后无条件 toggleEnabled(id, false)', () {
      final src = _readLocalSyncSource();
      expect(
        src,
        contains('await _host.toggleEnabled(id, false);'),
        reason: 'P1-3：addCustomPlugin 后必须无条件禁用，保证 '
            '「下架必禁用」不依赖时序',
      );
    });
  });
}
