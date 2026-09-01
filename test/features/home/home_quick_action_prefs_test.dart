// 首页快捷入口「自选」的持久化契约。
//
// 需求：快捷入口不再是四个硬编码的 Tab 跳转，而是用户从插件里自己挑。
// 这里钉住选择本身的行为，不依赖 UI。
import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/home/data/home_quick_action_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  HomeQuickActionPrefs makePrefs([String ns = 'qa_test']) =>
      HomeQuickActionPrefs(cache: CacheStore.inMemory(ns));

  group('默认状态', () {
    test('首次使用返回默认选择而不是空', () async {
      final prefs = makePrefs('qa_default');
      final ids = await prefs.readSelectedIds();
      expect(
        ids,
        isNotEmpty,
        reason: '全新安装的首页不该是空的，要有一套合理默认',
      );
    });

    test('默认选择数量不超过上限', () async {
      final prefs = makePrefs('qa_default_limit');
      final ids = await prefs.readSelectedIds();
      expect(ids.length, lessThanOrEqualTo(HomeQuickActionPrefs.maxSlots));
    });
  });

  group('保存与读回', () {
    test('保存后能原样读回，且保持顺序', () async {
      final prefs = makePrefs('qa_roundtrip');
      await prefs.saveSelectedIds(<String>['b', 'a', 'c']);
      expect(
        await prefs.readSelectedIds(),
        <String>['b', 'a', 'c'],
        reason: '顺序是用户排的，不能被重排',
      );
    });

    test('超过上限的部分被截断', () async {
      final prefs = makePrefs('qa_cap');
      final many = List<String>.generate(30, (i) => 'p$i');
      await prefs.saveSelectedIds(many);
      final ids = await prefs.readSelectedIds();
      expect(ids.length, HomeQuickActionPrefs.maxSlots);
      expect(ids.first, 'p0');
    });

    test('重复 id 被去重且保留首次出现的位置', () async {
      final prefs = makePrefs('qa_dedup');
      await prefs.saveSelectedIds(<String>['a', 'b', 'a', 'c', 'b']);
      expect(await prefs.readSelectedIds(), <String>['a', 'b', 'c']);
    });

    test('空白 id 被丢弃', () async {
      final prefs = makePrefs('qa_blank');
      await prefs.saveSelectedIds(<String>['a', '', '   ', 'b']);
      expect(await prefs.readSelectedIds(), <String>['a', 'b']);
    });

    test('可以清空到一个都不选', () async {
      final prefs = makePrefs('qa_clear');
      await prefs.saveSelectedIds(<String>['a']);
      await prefs.saveSelectedIds(<String>[]);
      expect(
        await prefs.readSelectedIds(),
        isEmpty,
        reason: '用户显式清空后不该又被塞回默认值',
      );
    });
  });

  group('损坏数据容错', () {
    test('缓存里是非法结构时回落到默认', () async {
      final cache = CacheStore.inMemory('qa_corrupt');
      await cache.write(HomeQuickActionPrefs.storageKey, 'not-json{{{');
      final prefs = HomeQuickActionPrefs(cache: cache);
      final ids = await prefs.readSelectedIds();
      expect(ids, isNotEmpty, reason: '坏数据应回落默认，不能让首页空掉');
    });

    test('列表里混入非字符串元素时只取字符串', () async {
      final cache = CacheStore.inMemory('qa_mixed');
      await cache.write(
        HomeQuickActionPrefs.storageKey,
        '{"version":1,"ids":["a",1,null,{"x":1},"b"]}',
      );
      final prefs = HomeQuickActionPrefs(cache: cache);
      expect(await prefs.readSelectedIds(), <String>['a', 'b']);
    });
  });

  group('增删单项', () {
    test('add 追加到末尾', () async {
      final prefs = makePrefs('qa_add');
      await prefs.saveSelectedIds(<String>['a']);
      await prefs.add('b');
      expect(await prefs.readSelectedIds(), <String>['a', 'b']);
    });

    test('add 已存在的 id 不产生重复', () async {
      final prefs = makePrefs('qa_add_dup');
      await prefs.saveSelectedIds(<String>['a', 'b']);
      await prefs.add('a');
      expect(await prefs.readSelectedIds(), <String>['a', 'b']);
    });

    test('达到上限后 add 不再追加', () async {
      final prefs = makePrefs('qa_add_full');
      final full = List<String>.generate(
        HomeQuickActionPrefs.maxSlots,
        (i) => 'p$i',
      );
      await prefs.saveSelectedIds(full);
      await prefs.add('overflow');
      final ids = await prefs.readSelectedIds();
      expect(ids.length, HomeQuickActionPrefs.maxSlots);
      expect(ids.contains('overflow'), isFalse);
    });

    test('remove 删掉指定项且不影响其余顺序', () async {
      final prefs = makePrefs('qa_remove');
      await prefs.saveSelectedIds(<String>['a', 'b', 'c']);
      await prefs.remove('b');
      expect(await prefs.readSelectedIds(), <String>['a', 'c']);
    });

    test('remove 不存在的 id 是无操作', () async {
      final prefs = makePrefs('qa_remove_missing');
      await prefs.saveSelectedIds(<String>['a']);
      await prefs.remove('zzz');
      expect(await prefs.readSelectedIds(), <String>['a']);
    });
  });

  group('重排', () {
    test('reorder 把一项移到新位置', () async {
      final prefs = makePrefs('qa_reorder');
      await prefs.saveSelectedIds(<String>['a', 'b', 'c']);
      await prefs.reorder(0, 2);
      expect(await prefs.readSelectedIds(), <String>['b', 'c', 'a']);
    });

    test('reorder 越界索引不改动也不抛异常', () async {
      final prefs = makePrefs('qa_reorder_oob');
      await prefs.saveSelectedIds(<String>['a', 'b']);
      await prefs.reorder(5, 0);
      await prefs.reorder(0, 99);
      expect(await prefs.readSelectedIds(), <String>['a', 'b']);
    });
  });
}
