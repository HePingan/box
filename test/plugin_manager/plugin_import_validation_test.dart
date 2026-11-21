// 导入是投稿之外的第二条插件入口，必须与投稿同口径校验。
//
// 背景：投稿接口后端会拒掉「未知动作 / navigate 指向不存在的页面」（400），
// 但 `importSnapshotJson` 原先只校验 JSON 结构与版本 —— 一个 navigate + 错路由码的
// 插件可以整包导进来，装上点一下毫无反应；未知动作更隐蔽，`_actionFromName` 会静默
// 回落 toast，用户以为装了个真插件。
//
// 本测试锁三件事：
//   1) 未知动作被挡下并给出原因（不是静默变 toast）；
//   2) navigate 指向不存在的页面被挡下；
//   3) 合法的 navigate / 普通动作照常导入；全部非法时整体报错而不是导入 0 个。

import 'dart:convert';

import 'package:box/core/storage/cache_store.dart';
import 'package:box/plugin_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

HomePluginHost _host(String ns) => HomePluginHost(
  persistence: HomePluginPersistence(cache: CacheStore.inMemory(ns)),
);

HomeCustomPluginConfig _navigatePlugin({
  required String id,
  required String payload,
  String actionCode = 'navigate',
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

/// 用 host 自己导出一个真实形状的快照，再改字段 —— 手写 JSON 容易和
/// `fromJson` 的 key 对不上，测出来的红是假的。
Future<String> _snapshotOf(
  HomePluginHost host,
  HomeCustomPluginConfig plugin,
) async {
  await host.bootstrap();
  await host.addCustomPlugin(plugin);
  final json = await host.exportSinglePluginJson(plugin.id, pretty: false);
  await host.unregister(plugin.id);
  return json;
}

String _patchField(String json, String field, String value) {
  final map = jsonDecode(json) as Map<String, dynamic>;
  final list = (map['customPlugins'] as List).cast<Map<String, dynamic>>();
  list.first[field] = value;
  map['customPlugins'] = list;
  return jsonEncode(map);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('导入校验（与投稿同口径）', () {
    test('未知动作被挡下并说明原因', () async {
      final host = _host('import_validation_unknown_action');
      final good = await _snapshotOf(
        host,
        _navigatePlugin(id: 'imp_unknown', payload: '{"route":"openMusic"}'),
      );
      final bad = _patchField(good, 'actionCode', 'bogusAction');

      final result = await host.importSnapshotJson(bad, merge: true);
      final ids = host.snapshot().customPlugins.map((p) => p.id).toList();

      expect(result.rejected.length, 1, reason: '未知动作必须被挡下');
      expect(result.rejected.first.reason, contains('未知动作'));
      expect(ids.contains('imp_unknown'), isFalse, reason: '被挡下的插件不该进配置');
    });

    test('navigate 指向不存在的页面被挡下', () async {
      final host = _host('import_validation_bad_route');
      final good = await _snapshotOf(
        host,
        _navigatePlugin(id: 'imp_badroute', payload: '{"route":"openMusic"}'),
      );
      final bad = _patchField(good, 'payload', '{"route":"no_such_page"}');

      final result = await host.importSnapshotJson(bad, merge: true);

      expect(result.rejected.length, 1);
      expect(result.rejected.first.reason, contains('目标页面不存在'));
      expect(
        host.snapshot().customPlugins.any((p) => p.id == 'imp_badroute'),
        isFalse,
      );
    });

    test('navigate 未指定页面被挡下', () async {
      final host = _host('import_validation_empty_route');
      final good = await _snapshotOf(
        host,
        _navigatePlugin(id: 'imp_emptyr', payload: '{"route":"openMusic"}'),
      );
      final bad = _patchField(good, 'payload', '');

      final result = await host.importSnapshotJson(bad, merge: true);
      expect(result.rejected.length, 1);
      expect(result.rejected.first.reason, contains('未指定'));
    });

    test('合法 navigate 照常导入', () async {
      final host = _host('import_validation_ok');
      final json = await _snapshotOf(
        host,
        _navigatePlugin(id: 'imp_ok', payload: '{"route":"openMusic"}'),
      );

      final result = await host.importSnapshotJson(json, merge: true);
      expect(result.imported, 1);
      expect(result.hasRejects, isFalse);
      expect(host.snapshot().customPlugins.any((p) => p.id == 'imp_ok'), isTrue);
    });

    test('全部非法时整体报错，不静默导入 0 个', () async {
      final host = _host('import_validation_all_bad');
      final good = await _snapshotOf(
        host,
        _navigatePlugin(id: 'imp_allbad', payload: '{"route":"openMusic"}'),
      );
      final bad = _patchField(good, 'actionCode', 'nope');

      await expectLater(
        host.importSnapshotJson(bad, merge: true),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('单插件导出（分享用）', () {
    test('只带目标插件本身', () async {
      final host = _host('export_single_plugin');
      await host.bootstrap();
      await host.addCustomPlugin(
        _navigatePlugin(id: 'share_a', payload: '{"route":"openMusic"}'),
      );
      await host.addCustomPlugin(
        _navigatePlugin(id: 'share_b', payload: '{"route":"daily_news"}'),
      );

      final json = await host.exportSinglePluginJson('share_a', pretty: false);
      final map = jsonDecode(json) as Map<String, dynamic>;
      final plugins = (map['customPlugins'] as List).cast<Map>();

      expect(plugins.length, 1, reason: '分享只该带一个插件');
      expect(plugins.first['id'], 'share_a');
      expect((map['enabledMap'] as Map).keys, ['share_a']);
    });

    test('导出结果能被自己导入（闭环）', () async {
      final host = _host('export_single_roundtrip');
      await host.bootstrap();
      await host.addCustomPlugin(
        _navigatePlugin(id: 'rt_a', payload: '{"route":"openMusic"}'),
      );
      final json = await host.exportSinglePluginJson('rt_a', pretty: false);

      final other = _host('export_single_roundtrip_2');
      final result = await other.importSnapshotJson(json, merge: true);

      expect(result.imported, 1);
      expect(other.snapshot().customPlugins.first.id, 'rt_a');
    });
  });
}
