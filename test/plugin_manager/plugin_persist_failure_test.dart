import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/extensions/core/home_plugin_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// FIX-06：消除两处静默失败。
///
/// ① `_persist()` 原先 `catch (_) {}` —— 落盘失败（磁盘满/序列化异常）对调用方
///    完全不可见，UI 照常提示成功。
/// ② `readSnapshot()` 解析异常一律返回空快照 —— 坏数据会在下一次写入时被覆盖成
///    默认，用户的自定义插件与顺序静默丢失，没有线索。
/// 写盘必炸的持久化，用来模拟磁盘满/序列化失败。
class _ExplodingPersistence extends HomePluginPersistence {
  _ExplodingPersistence({required super.cache});

  @override
  Future<void> writeSnapshot(HomePluginSnapshot snapshot) async {
    throw StateError('disk full（测试模拟）');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  HomeCustomPluginConfig config(String id) =>
      HomeCustomPluginConfig.fromJson(<String, dynamic>{
        'id': id,
        'title': '落盘用例',
        'area': HomePluginArea.center.name,
        'action': HomePluginActionType.toast.name,
      });

  test('落盘失败不再静默：lastPersistFailed 置位且留日志', () async {
    final logs = <String>[];
    final prev = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() => debugPrint = prev);

    final cache = CacheStore.inMemory('persist_fail');
    final host = HomePluginHost(
      persistence: _ExplodingPersistence(cache: cache),
    );
    await host.bootstrap();
    await host.addCustomPlugin(config('persist_fail_plugin'));
    await host.toggleEnabled('persist_fail_plugin', false);

    expect(
      host.lastPersistFailed,
      isTrue,
      reason: '写盘失败必须对调用方可见 —— 原先 catch (_) {} 把 UI 骗成成功',
    );
    expect(
      logs.any((l) => l.contains('快照落盘失败')),
      isTrue,
      reason: '失败要留痕，不然磁盘满这种事没人查得到',
    );
  });

  test('坏快照先备份再回落，原文不丢', () async {
    final cache = CacheStore.inMemory('corrupt_backup');
    const key = 'plugin_snapshot_v1';
    await cache.write(key, '{ 这不是合法 JSON');

    final persistence = HomePluginPersistence(cache: cache);
    final snapshot = await persistence.readSnapshot();

    expect(
      snapshot.customPlugins,
      isEmpty,
      reason: '坏数据要能安全降级，不能把启动卡死',
    );

    final backupKey = persistence.lastCorruptBackupKey;
    expect(
      backupKey,
      isNotNull,
      reason: '必须留下一个可查的备份键，否则用户数据丢了连取证都没法做',
    );
    expect(
      await cache.read(backupKey!),
      '{ 这不是合法 JSON',
      reason: '备份的应当是原始文本，不是"某个空快照"',
    );
  });

  test('正常快照不产生备份键（避免噪音）', () async {
    final cache = CacheStore.inMemory('corrupt_noise');
    final persistence = HomePluginPersistence(cache: cache);
    await persistence.writeSnapshot(
      const HomePluginSnapshot(enabledMap: {}, customPlugins: []),
    );

    final snapshot = await persistence.readSnapshot();

    expect(snapshot.enabledMap, isEmpty);
    expect(
      persistence.lastCorruptBackupKey,
      isNull,
      reason: '没坏就别建备份键',
    );
  });
}
