import 'dart:convert';

import 'package:box/features/cloud_sync/data/book_source_cloud_sync.dart';
import 'package:box/features/cloud_sync/data/cloud_sync_client.dart';
import 'package:box/novel/pages/source_manager/book_source_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// 统计 SharedPreferences 写入次数的探针。
///
/// 目的：把「同步 N 条书源写盘 N 次」这件事变成可断言的数字，
/// 而不是靠肉眼读代码判断。
class _CountingPrefsStore extends InMemorySharedPreferencesStore {
  _CountingPrefsStore.withData(super.data) : super.withData();

  int setStringCalls = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    // 只统计书源列表这一个大 key，避免把版本号/时间戳等小写入混进来。
    if (key.contains(BookSourceManager.storageKey)) setStringCalls++;
    return super.setValue(valueType, key, value);
  }
}

Map<String, dynamic> _cloudSource({
  required String id,
  required String name,
  required String url,
  bool removed = false,
}) {
  if (removed) return {'id': id, 'removed': true};
  return {
    'id': id,
    'name': name,
    'url': url,
    'group': '云端',
    'enabled': true,
    'weight': 0,
    'rawJson': jsonEncode({
      'bookSourceName': name,
      'bookSourceUrl': url,
      'searchUrl': '$url/search?kw={{key}}',
    }),
    'updatedAt': '2026-08-30T10:00:00.000Z',
    'removed': false,
  };
}

MockClient _clientFor(List<Map<String, dynamic>> sources, {int version = 1}) {
  return MockClient((request) async {
    return http.Response(
      jsonEncode({
        'version': version,
        'changed': true,
        'count': sources.length,
        'publishedAt': '2026-08-30T10:00:00.000Z',
        'sources': sources,
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

void main() {
  late SharedPreferences prefs;
  late _CountingPrefsStore store;

  setUp(() async {
    // 先装计数探针，再取 SharedPreferences 实例，保证所有写入都被记到。
    SharedPreferences.resetStatic();
    store = _CountingPrefsStore.withData(<String, Object>{});
    SharedPreferencesStorePlatform.instance = store;
    prefs = await SharedPreferences.getInstance();
    store.setStringCalls = 0;
  });

  group('云端书源同步的写盘成本', () {
    test('落地 30 条书源只写盘一次，不是每条一次', () async {
      final sources = List.generate(
        30,
        (i) => _cloudSource(
          id: 'c$i',
          name: '书源$i',
          url: 'https://s$i.example.com',
        ),
      );

      final manager = BookSourceManager(prefs);
      await manager.load();
      store.setStringCalls = 0;

      final result = await BookSourceCloudSyncService(
        client: CloudSyncClient(httpClient: _clientFor(sources)),
      ).sync(prefs: prefs, manager: manager);

      expect(result.added, 30, reason: '30 条都应落地');
      expect(manager.items.length, 30);

      // 关键断言：save() 是整表 jsonEncode + 写盘，N 条写 N 次是 O(N^2)。
      // 批量落地后应只写一次。
      expect(
        store.setStringCalls,
        1,
        reason: '30 条书源应合并成 1 次写盘，实测 ${store.setStringCalls} 次',
      );
    });

    test('删除 + 新增混合时也只写盘一次', () async {
      // 先铺两条本地已存在的云端书源。
      final initial = [
        _cloudSource(id: 'c1', name: '甲', url: 'https://a.example.com'),
        _cloudSource(id: 'c2', name: '乙', url: 'https://b.example.com'),
      ];
      final manager = BookSourceManager(prefs);
      await manager.load();
      await BookSourceCloudSyncService(
        client: CloudSyncClient(httpClient: _clientFor(initial)),
      ).sync(prefs: prefs, manager: manager);
      expect(manager.items.length, 2);

      // 铺底阶段的写入不计入本次断言。
      store.setStringCalls = 0;

      // 第二批：删掉 c1，改名 c2，新增 c3。
      final second = [
        _cloudSource(id: 'c1', name: '甲', url: 'https://a.example.com', removed: true),
        _cloudSource(id: 'c2', name: '乙改名', url: 'https://b2.example.com'),
        _cloudSource(id: 'c3', name: '丙', url: 'https://c.example.com'),
      ];
      final result = await BookSourceCloudSyncService(
        client: CloudSyncClient(httpClient: _clientFor(second, version: 2)),
      ).sync(prefs: prefs, manager: manager, force: true);

      expect(result.removed, 1, reason: 'c1 应被删除');
      expect(
        store.setStringCalls,
        1,
        reason: '删除+新增+改名应合并成 1 次写盘，实测 ${store.setStringCalls} 次',
      );
      // 只关心集合内容，顺序由 manager 的权重排序决定，不在本用例的断言范围内。
      expect(
        manager.items.map((e) => e.bookSourceName),
        unorderedEquals(['乙改名', '丙']),
      );
    });

    test('同步期间只通知一次监听者，避免列表 UI 抖 N 次', () async {
      final sources = List.generate(
        12,
        (i) => _cloudSource(
          id: 'c$i',
          name: '书源$i',
          url: 'https://s$i.example.com',
        ),
      );
      final manager = BookSourceManager(prefs);
      await manager.load();

      var notifications = 0;
      manager.addListener(() => notifications++);

      await BookSourceCloudSyncService(
        client: CloudSyncClient(httpClient: _clientFor(sources)),
      ).sync(prefs: prefs, manager: manager);

      expect(manager.items.length, 12);
      expect(
        notifications,
        1,
        reason: '12 条书源应只触发 1 次 notifyListeners，实测 $notifications 次',
      );
    });
  });

  group('批量落地不能破坏既有语义', () {
    test('当前选中书源被云端删除后会自动修复到其他可用书源', () async {
      final initial = [
        _cloudSource(id: 'c1', name: '甲', url: 'https://a.example.com'),
        _cloudSource(id: 'c2', name: '乙', url: 'https://b.example.com'),
      ];
      final manager = BookSourceManager(prefs);
      await manager.load();
      await BookSourceCloudSyncService(
        client: CloudSyncClient(httpClient: _clientFor(initial)),
      ).sync(prefs: prefs, manager: manager);

      // 把当前源指向即将被删的那条。
      final doomed = manager.items.firstWhere((e) => e.bookSourceName == '甲');
      await manager.setCurrentSource(doomed.id);
      expect(manager.currentSourceId, doomed.id);

      await BookSourceCloudSyncService(
        client: CloudSyncClient(
          httpClient: _clientFor([
            _cloudSource(id: 'c1', name: '甲', url: 'https://a.example.com', removed: true),
            _cloudSource(id: 'c2', name: '乙', url: 'https://b.example.com'),
          ], version: 2),
        ),
      ).sync(prefs: prefs, manager: manager, force: true);

      expect(manager.items.length, 1);
      expect(
        manager.currentSourceId,
        isNot(doomed.id),
        reason: '选中的书源被删后必须改指向，不能悬空',
      );
      expect(manager.currentSourceId, manager.items.single.id);
    });

    test('落地结果真的持久化了（重建 manager 后还在）', () async {
      final sources = List.generate(
        5,
        (i) => _cloudSource(
          id: 'c$i',
          name: '书源$i',
          url: 'https://s$i.example.com',
        ),
      );
      final manager = BookSourceManager(prefs);
      await manager.load();
      await BookSourceCloudSyncService(
        client: CloudSyncClient(httpClient: _clientFor(sources)),
      ).sync(prefs: prefs, manager: manager);

      final reloaded = BookSourceManager(prefs);
      await reloaded.load();
      expect(reloaded.items.length, 5, reason: '批量写盘后必须能读回来');
    });
  });
}
