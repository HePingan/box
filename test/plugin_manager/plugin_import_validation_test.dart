// 导入是投稿之外的第二条插件入口，必须与投稿同口径校验。
//
// 背景：投稿接口后端会拒掉「未知动作 / navigate 指向不存在的页面」（400），
// 但 `importSnapshotJson` 原先只校验 JSON 结构与版本 —— 一个 navigate + 错路由码的
// 插件可以整包导进来，装上点一下毫无反应；未知动作更隐蔽，`_actionFromName` 会静默
// 回落 toast，用户以为装了个真插件。
//
// 语义（两段都要有）：
//   - 部分非法：非法的不导入，合法的照常进，剔除了谁要能报出来（PluginImportResult）；
//   - 全部非法：整体抛 FormatException —— 不能报「导入成功 0 个」，那读起来像成功。

import 'dart:convert';

import 'package:box/core/storage/cache_store.dart';
import 'package:box/plugin_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

HomePluginHost _host(String ns) => HomePluginHost(
  persistence: HomePluginPersistence(cache: CacheStore.inMemory(ns)),
);

HomeCustomPluginConfig _plugin({
  required String id,
  String actionCode = 'navigate',
  String payload = '{"route":"openMusic"}',
}) => HomeCustomPluginConfig(
  id: id,
  title: id,
  subtitle: 'import validation',
  iconCodePoint: Icons.extension_outlined.codePoint,
  colorValue: Colors.blue.toARGB32(),
  area: HomePluginArea.center,
  actionType: HomePluginActionType.navigate,
  actionCode: actionCode,
  payload: payload,
  enabled: true,
  sort: 10,
  createdAt: 1,
  origin: 'user_market',
);

/// 用 host 自己导出真实形状的快照 —— 手写 JSON 容易和 `fromJson` 的 key 对不上，
/// 那样测出来的红是假的。
Future<String> _snapshotOf(
  HomePluginHost host,
  List<HomeCustomPluginConfig> plugins,
) async {
  await host.bootstrap();
  for (final p in plugins) {
    await host.addCustomPlugin(p);
  }
  final json = await host.exportSnapshotJson(pretty: false);
  for (final p in plugins) {
    await host.unregister(p.id);
  }
  return json;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('导入校验（与投稿同口径）', () {
    test('未知动作被挡下，同批合法插件照常导入', () async {
      final host = _host('import_validation_unknown_action');
      final json = await _snapshotOf(host, [
        _plugin(id: 'imp_good_a'),
        _plugin(id: 'imp_bad_action', actionCode: 'bogusAction'),
      ]);

      final result = await host.importSnapshotJson(json, merge: true);
      final ids = host.snapshot().customPlugins.map((p) => p.id).toList();

      expect(result.imported, 1, reason: '合法的那条要进来');
      expect(result.rejected.length, 1, reason: '未知动作必须被挡下');
      expect(result.rejected.first.id, 'imp_bad_action');
      expect(result.rejected.first.reason, contains('未知动作'));
      expect(ids.contains('imp_good_a'), isTrue);
      expect(ids.contains('imp_bad_action'), isFalse, reason: '被挡下的不该进配置');
    });

    test('navigate 指向不存在的页面被挡下', () async {
      final host = _host('import_validation_bad_route');
      final json = await _snapshotOf(host, [
        _plugin(id: 'imp_good_b'),
        _plugin(id: 'imp_bad_route', payload: '{"route":"no_such_page"}'),
      ]);

      final result = await host.importSnapshotJson(json, merge: true);

      expect(result.imported, 1);
      expect(result.rejected.length, 1);
      expect(result.rejected.first.reason, contains('目标页面不存在'));
      expect(
        host.snapshot().customPlugins.any((p) => p.id == 'imp_bad_route'),
        isFalse,
      );
    });

    test('navigate 未指定页面被挡下', () async {
      final host = _host('import_validation_empty_route');
      final json = await _snapshotOf(host, [
        _plugin(id: 'imp_good_c'),
        _plugin(id: 'imp_empty_route', payload: ''),
      ]);

      final result = await host.importSnapshotJson(json, merge: true);
      expect(result.imported, 1);
      expect(result.rejected.length, 1);
      expect(result.rejected.first.reason, contains('未指定'));
    });

    test('合法 navigate 照常导入', () async {
      final host = _host('import_validation_ok');
      final json = await _snapshotOf(host, [_plugin(id: 'imp_ok')]);

      final result = await host.importSnapshotJson(json, merge: true);
      expect(result.imported, 1);
      expect(result.hasRejects, isFalse);
      expect(host.snapshot().customPlugins.any((p) => p.id == 'imp_ok'), isTrue);
    });

    test('全部非法时整体报错，不静默导入 0 个', () async {
      final host = _host('import_validation_all_bad');
      final json = await _snapshotOf(host, [
        _plugin(id: 'imp_all_bad', actionCode: 'nope'),
      ]);

      await expectLater(
        host.importSnapshotJson(json, merge: true),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('不可用'),
          ),
        ),
      );
    });

    test('被挡下的插件不留下启用状态残留', () async {
      final host = _host('import_validation_enabled_map');
      final json = await _snapshotOf(host, [
        _plugin(id: 'imp_good_d'),
        _plugin(id: 'imp_bad_d', actionCode: 'nope'),
      ]);

      await host.importSnapshotJson(json, merge: true);
      final enabled = host.snapshot().enabledMap.keys.toList();

      expect(enabled.contains('imp_bad_d'), isFalse, reason: 'enabledMap 也要清掉');
      expect(enabled.contains('imp_good_d'), isTrue);
    });
  });

  group('单插件导出（分享用）', () {
    test('只带目标插件本身', () async {
      final host = _host('export_single_plugin');
      await host.bootstrap();
      await host.addCustomPlugin(_plugin(id: 'share_a'));
      await host.addCustomPlugin(
        _plugin(id: 'share_b', payload: '{"route":"daily_news"}'),
      );

      final json = await host.exportSinglePluginJson('share_a', pretty: false);
      final map = jsonDecode(json) as Map<String, dynamic>;
      final plugins = (map['customPlugins'] as List).cast<Map>();

      expect(plugins.length, 1, reason: '分享只该带一个插件');
      expect(plugins.first['id'], 'share_a');
      expect((map['enabledMap'] as Map).keys, ['share_a']);
    });

    test('导出结果能被另一台设备导入（闭环）', () async {
      final host = _host('export_single_roundtrip');
      await host.bootstrap();
      await host.addCustomPlugin(_plugin(id: 'rt_a'));
      final json = await host.exportSinglePluginJson('rt_a', pretty: false);

      final other = _host('export_single_roundtrip_2');
      final result = await other.importSnapshotJson(json, merge: true);

      expect(result.imported, 1);
      expect(other.snapshot().customPlugins.first.id, 'rt_a');
    });
  });
}
