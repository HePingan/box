// P0-1 回归测试：导入快照必须护栏，不得静默清空用户插件配置。
//
// 背景（已复现的真实缺陷）：
//   home_plugin_core.dart 的 importSnapshotJson 唯一校验是 `decoded is! Map`，
//   之后直接整体替换 + 落盘；而 HomePluginSnapshot.fromJson 对字段缺失完全静默容忍
//   （enabledMap 非 Map → 空表；customPlugins 非 List → 空列表；单元素异常 → 吞掉）。
//
//   推论：传入 {"foo":"bar"} 这类任意 JSON → 解析出「两个空表」→ 覆盖模式下
//   把用户全部插件配置清空并落盘，UI 还提示「导入成功（已覆盖）」。
//
// 本测试锁两件事：
//   1) 不合法/无关 JSON 必须抛错，而不是静默变成空快照；
//   2) 即便真有合法但为空的快照，也不能在覆盖模式下把非空配置清空（需显式允许）。

import 'package:box/core/storage/cache_store.dart';
import 'package:box/plugin_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

HomePluginHost _host(String ns) => HomePluginHost(
  persistence: HomePluginPersistence(cache: CacheStore.inMemory(ns)),
);

/// 装一个自定义插件，让快照「非空」
Future<HomePluginHost> _hostWithCustom(String ns) async {
  final host = _host(ns);
  await host.bootstrap();
  await host.addCustomPlugin(
    HomeCustomPluginConfig(
      id: 'custom_guard_a',
      title: 'Guard A',
      subtitle: 'guard test',
      iconCodePoint: Icons.extension_outlined.codePoint,
      colorValue: Colors.blue.toARGB32(),
      area: HomePluginArea.center,
      actionType: HomePluginActionType.toast,
      payload: 'hi',
      enabled: true,
      sort: 10,
      createdAt: 1,
      origin: 'user_market',
    ),
  );
  return host;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P0-1 导入快照护栏', () {
    test('无关 JSON（{"foo":"bar"}）必须抛错，不得静默解析为空快照', () async {
      final host = _host('snapshot_guard_irrelevant');
      await host.bootstrap();

      await expectLater(
        host.importSnapshotJson('{"foo":"bar"}'),
        throwsA(isA<FormatException>()),
        reason: '缺少 enabledMap/customPlugins 字段的 JSON 应被拒绝，'
            '否则覆盖模式会静默清空全部配置',
      );
    });

    test('无关 JSON 不得清空已有的自定义插件（覆盖模式也不许）', () async {
      final host = await _hostWithCustom('snapshot_guard_no_wipe');
      expect(host.allPlugins.where((p) => p.id == 'custom_guard_a'), isNotEmpty,
          reason: '前置条件：应已装入自定义插件');

      try {
        await host.importSnapshotJson('{"foo":"bar"}');
      } catch (_) {
        // 抛错是预期行为
      }

      expect(
        host.allPlugins.where((p) => p.id == 'custom_guard_a'),
        isNotEmpty,
        reason: '导入无关 JSON 后自定义插件必须仍在——这是数据丢失防线',
      );
    });

    test('合法快照缺少 version 字段应被拒绝', () async {
      final host = _host('snapshot_guard_version');
      await host.bootstrap();

      await expectLater(
        host.importSnapshotJson(
          '{"enabledMap":{"a":true},"customPlugins":[]}',
        ),
        throwsA(isA<FormatException>()),
        reason: 'toJson 会写 version，fromJson 却忽略；导入侧应校验 version',
      );
    });

    test('合法且带 version 的非空快照可正常导入（正例不能误伤）', () async {
      final host = _host('snapshot_guard_positive');
      await host.bootstrap();

      await host.importSnapshotJson(
        '{"version":1,"enabledMap":{"builtin_daily_news":false},'
        '"customPlugins":[]}',
      );

      // 能走到这里即说明未被护栏误拦
      expect(host.allPlugins, isNotEmpty);
    });

    test('空快照覆盖非空配置需显式 allowEmpty，默认应拒绝', () async {
      final host = await _hostWithCustom('snapshot_guard_empty_deny');

      await expectLater(
        host.importSnapshotJson('{"version":1,"enabledMap":{},"customPlugins":[]}'),
        throwsA(isA<FormatException>()),
        reason: '用空快照覆盖非空配置等于清库，必须显式声明意图',
      );

      expect(
        host.allPlugins.where((p) => p.id == 'custom_guard_a'),
        isNotEmpty,
        reason: '默认拒绝后，原有插件必须完好',
      );
    });
  });
}
