import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/extensions/core/home_plugin_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真缺陷回归：拖动重排**内置**插件，重启后顺序还原。
///
/// 原因：`_buildCurrentSnapshot()` 只写 enabledMap，内置插件的排序没有任何落地
/// 位置（customPlugins 只收非内置项），而 `_applySnapshot()` 用
/// `_buildDefaultPlugins()` 重建内置项、只套用 enabled。同一个拖动交互，
/// 自定义插件能保住顺序、内置插件保不住。
///
/// 修法：快照 v2 增加 orderMap（id → sort，内置与自定义统一），v1 仍可读。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  HomePluginHost newHost(CacheStore cache) =>
      HomePluginHost(persistence: HomePluginPersistence(cache: cache));

  List<String> idsOf(HomePluginHost host, HomePluginArea area) =>
      host.pluginsOf(area, onlyEnabled: false).map((p) => p.id).toList();

  test('内置插件重排后重启仍保持顺序（快照 v2 orderMap）', () async {
    final cache = CacheStore.inMemory('reorder_persist');
    final host = newHost(cache);
    await host.bootstrap();

    final before = idsOf(host, HomePluginArea.center);
    expect(
      before.length,
      greaterThanOrEqualTo(4),
      reason: '工具区内置插件不足 4 个，用例前提不成立',
    );

    await host.reorderPlugin(HomePluginArea.center, 0, 3);
    final expected = idsOf(host, HomePluginArea.center);
    expect(
      expected,
      isNot(equals(before)),
      reason: '重排必须真的改变顺序，否则这个用例证明不了任何事',
    );

    final reborn = newHost(cache);
    await reborn.bootstrap();

    expect(
      idsOf(reborn, HomePluginArea.center),
      expected,
      reason: '内置插件顺序必须随快照持久化 —— 此前重启即丢',
    );
  });

  test('快照里内置插件也带 sort（这正是缺陷的直接证据）', () async {
    final cache = CacheStore.inMemory('order_map_builtin');
    final host = newHost(cache);
    await host.bootstrap();

    final snapshot = host.snapshot();
    final builtinIds =
        host.pluginsOf(HomePluginArea.center, onlyEnabled: false)
            .where((p) => p.builtIn)
            .map((p) => p.id);

    expect(builtinIds, isNotEmpty);
    for (final id in builtinIds) {
      expect(
        snapshot.orderMap.containsKey(id),
        isTrue,
        reason: '$id 是内置插件，顺序也必须记进快照',
      );
    }
  });

  test('v1 快照仍可导入（向后兼容，顺序回落默认）', () {
    final v1 = HomePluginSnapshot.fromJson(const {
      'version': 1,
      'enabledMap': {'builtin_daily_news': false},
      'customPlugins': [],
    });

    expect(v1.enabledMap['builtin_daily_news'], isFalse);
    expect(
      v1.orderMap,
      isEmpty,
      reason: 'v1 没有 orderMap 字段，读出来是空表而不是报错',
    );
  });

  test('v2 快照 orderMap 往返不丢', () {
    const snapshot = HomePluginSnapshot(
      enabledMap: {'a': true},
      orderMap: {'a': 100, 'b': 200},
      customPlugins: [],
    );

    final restored = HomePluginSnapshot.fromJson(snapshot.toJson());

    expect(restored.orderMap, const {'a': 100, 'b': 200});
    expect(snapshot.toJson()['version'], kPluginSnapshotVersion);
    expect(kSupportedPluginSnapshotVersions.contains(1), isTrue);
  });
}
