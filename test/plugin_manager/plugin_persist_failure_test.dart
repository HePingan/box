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

/// 读快照必炸的持久化，用来模拟"启动阶段读取异常"。
class _ExplodingReadPersistence extends HomePluginPersistence {
  _ExplodingReadPersistence({required super.cache});

  @override
  Future<HomePluginSnapshot> readSnapshot() async {
    throw StateError('读取失败（测试模拟）');
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

  test('启动读快照失败：降级为默认插件但留痕（bootstrapFailed）', () async {
    // 用户看到的是"我的插件没了"，以前日志里一个字都没有 —— 排查只能靠猜。
    final logs = <String>[];
    final prev = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() => debugPrint = prev);

    final host = HomePluginHost(
      persistence: _ExplodingReadPersistence(
        cache: CacheStore.inMemory('read-boom'),
      ),
    );
    await host.bootstrap();

    expect(host.bootstrapFailed, isTrue, reason: '降级必须留痕');
    expect(
      logs.any((l) => l.contains('退回默认插件')),
      isTrue,
      reason: '日志里要有这条，否则等于没留痕',
    );
    expect(
      host.pluginsOf(HomePluginArea.center).isNotEmpty ||
          host.pluginsOf(HomePluginArea.recommend).isNotEmpty,
      isTrue,
      reason: '降级后仍要能用（不能因为读盘失败就白屏）',
    );
  });

  test('正常启动不置位（控制组）', () async {
    final host = HomePluginHost(
      persistence: HomePluginPersistence(cache: CacheStore.inMemory('read-ok')),
    );
    await host.bootstrap();
    expect(
      host.bootstrapFailed,
      isFalse,
      reason: '控制组：没坏就不该触发降级标志，否则这个信号没有意义',
    );
  });
}
