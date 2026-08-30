import 'dart:convert';

import 'package:box/features/cloud_sync/data/book_source_cloud_sync.dart';
import 'package:box/features/cloud_sync/data/cloud_sync_client.dart';
import 'package:box/novel/pages/source_manager/book_source_manager.dart';
import 'package:box/novel/pages/source_manager/book_source_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 构造一条云端书源 JSON。
Map<String, dynamic> cloudSource({
  required String id,
  required String name,
  required String url,
  String group = '云端',
  bool enabled = true,
  int weight = 0,
  bool removed = false,
  Map<String, dynamic>? extraRule,
}) {
  if (removed) {
    return {'id': id, 'removed': true};
  }
  final rule = <String, dynamic>{
    'bookSourceName': name,
    'bookSourceUrl': url,
    'searchUrl': '$url/search?kw={{key}}',
    ...?extraRule,
  };
  return {
    'id': id,
    'name': name,
    'url': url,
    'group': group,
    'enabled': enabled,
    'weight': weight,
    'rawJson': jsonEncode(rule),
    'updatedAt': '2026-08-30T10:00:00.000Z',
    'removed': false,
  };
}

/// 返回一个假的 /api/book-sources 响应，并记录收到的 since 参数。
({MockClient client, List<String?> sinceLog}) bundleClient(
  List<Map<String, dynamic>> Function(String? since) sourcesFor, {
  int version = 1,
  bool? changed,
}) {
  final sinceLog = <String?>[];
  final client = MockClient((request) async {
    sinceLog.add(request.url.queryParameters['since']);
    final sources = sourcesFor(request.url.queryParameters['since']);
    return http.Response(
      jsonEncode({
        'version': version,
        'changed': changed ?? true,
        'count': sources.length,
        'publishedAt': '2026-08-30T10:00:00.000Z',
        'sources': sources,
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
  return (client: client, sinceLog: sinceLog);
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  BookSourceCloudSyncService serviceWith(MockClient client) =>
      BookSourceCloudSyncService(
        client: CloudSyncClient(httpClient: client),
      );

  test('首次同步：云端书源落地到本地，版本号被记住', () async {
    final fake = bundleClient(
      (_) => [
        cloudSource(id: 'c1', name: '书源甲', url: 'https://a.example.com'),
        cloudSource(id: 'c2', name: '书源乙', url: 'https://b.example.com'),
      ],
      version: 7,
    );
    final manager = BookSourceManager(prefs);
    await manager.load();

    final result = await serviceWith(
      fake.client,
    ).sync(prefs: prefs, manager: manager);

    expect(result.added, 2);
    expect(result.updated, 0);
    expect(result.removed, 0);
    expect(result.version, 7);
    expect(manager.items.map((e) => e.bookSourceName), containsAll(['书源甲', '书源乙']));
    expect(prefs.getInt(BookSourceCloudSyncService.versionKey), 7);
    // 首次同步没有本地版本，不应带 since
    expect(fake.sinceLog.single, isNull);
  });

  test('增量同步：第二次带上 since=已知版本', () async {
    final fake = bundleClient(
      (since) => since == null
          ? [cloudSource(id: 'c1', name: '书源甲', url: 'https://a.example.com')]
          : const <Map<String, dynamic>>[],
      version: 3,
    );
    final manager = BookSourceManager(prefs);
    await manager.load();
    final service = serviceWith(fake.client);

    await service.sync(prefs: prefs, manager: manager);
    await service.sync(prefs: prefs, manager: manager);

    expect(fake.sinceLog, [null, '3']);
  });

  test('changed=false 时不动本地数据，只推进版本号', () async {
    final manager = BookSourceManager(prefs);
    await manager.load();
    await manager.addOrUpdate(
      BookSourceModel.fromJson({
        'bookSourceName': '本地源',
        'bookSourceUrl': 'https://local.example.com',
      }),
    );
    await manager.save();
    final before = manager.items.map((e) => e.id).toList();

    final fake = bundleClient(
      (_) => const <Map<String, dynamic>>[],
      version: 9,
      changed: false,
    );
    final result = await serviceWith(
      fake.client,
    ).sync(prefs: prefs, manager: manager);

    expect(result.upToDate, isTrue);
    expect(result.hasChanges, isFalse);
    expect(manager.items.map((e) => e.id), before);
    expect(prefs.getInt(BookSourceCloudSyncService.versionKey), 9);
  });

  test('云端为准：同 id 改名后不留重复条目（本地派生 id 会变）', () async {
    final manager = BookSourceManager(prefs);
    await manager.load();

    // 第一轮：落地「旧名」
    final first = bundleClient(
      (_) => [cloudSource(id: 'c1', name: '旧名', url: 'https://a.example.com')],
      version: 1,
    );
    await serviceWith(first.client).sync(prefs: prefs, manager: manager);
    expect(manager.items, hasLength(1));
    final oldLocalId = manager.items.single.id;

    // 第二轮：同一个云端 id，改名 + 换域名 → 本地派生 id 变了
    final second = bundleClient(
      (_) => [cloudSource(id: 'c1', name: '新名', url: 'https://z.example.com')],
      version: 2,
    );
    final result = await serviceWith(
      second.client,
    ).sync(prefs: prefs, manager: manager, force: true);

    expect(manager.items, hasLength(1), reason: '改名不能产生重复书源');
    expect(manager.items.single.bookSourceName, '新名');
    expect(manager.items.single.id, isNot(oldLocalId));
    expect(result.removed, 0, reason: '这是替换而非删除，不该计入 removed');
  });

  test('墓碑条目 removed=true 会删掉本地书源', () async {
    final manager = BookSourceManager(prefs);
    await manager.load();

    final first = bundleClient(
      (_) => [cloudSource(id: 'c1', name: '待删源', url: 'https://a.example.com')],
      version: 1,
    );
    await serviceWith(first.client).sync(prefs: prefs, manager: manager);
    expect(manager.items, hasLength(1));

    final second = bundleClient(
      (_) => [cloudSource(id: 'c1', name: '', url: '', removed: true)],
      version: 2,
    );
    final result = await serviceWith(
      second.client,
    ).sync(prefs: prefs, manager: manager, force: true);

    expect(result.removed, 1);
    expect(manager.items, isEmpty);
  });

  test('云端脏数据被跳过，不影响其他书源落地', () async {
    final fake = bundleClient(
      (_) => [
        // rawJson 不是合法 JSON 且 name/url 为空 → 跳过
        {'id': 'bad1', 'name': '', 'url': '', 'rawJson': '{{{'},
        // 没有 id → 跳过
        {'id': '', 'name': '无 id', 'url': 'https://x.example.com'},
        cloudSource(id: 'ok', name: '正常源', url: 'https://ok.example.com'),
      ],
      version: 4,
    );
    final manager = BookSourceManager(prefs);
    await manager.load();

    final result = await serviceWith(
      fake.client,
    ).sync(prefs: prefs, manager: manager);

    expect(result.added, 1);
    expect(result.skipped, 2);
    expect(manager.items.single.bookSourceName, '正常源');
  });

  test('本地不存在但映射残留时，墓碑不会误报 removed', () async {
    final manager = BookSourceManager(prefs);
    await manager.load();
    final first = bundleClient(
      (_) => [cloudSource(id: 'c1', name: '源', url: 'https://a.example.com')],
      version: 1,
    );
    await serviceWith(first.client).sync(prefs: prefs, manager: manager);
    // 用户手动删掉了这个书源
    await manager.deleteById(manager.items.single.id);

    final second = bundleClient(
      (_) => [cloudSource(id: 'c1', name: '', url: '', removed: true)],
      version: 2,
    );
    final result = await serviceWith(
      second.client,
    ).sync(prefs: prefs, manager: manager, force: true);

    expect(result.removed, 0);
    expect(manager.items, isEmpty);
  });

  test('syncIfStale 在冷却期内跳过网络请求', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response(
        jsonEncode({'version': 1, 'changed': false, 'count': 0, 'sources': []}),
        200,
      );
    });
    final manager = BookSourceManager(prefs);
    await manager.load();
    final service = BookSourceCloudSyncService(
      client: CloudSyncClient(httpClient: client),
    );

    await service.syncIfStale(prefs: prefs, manager: manager);
    expect(calls, 1);
    await service.syncIfStale(prefs: prefs, manager: manager);
    expect(calls, 1, reason: '6 小时内不应重复打网络');
  });

  test('syncIfStale 网络失败时静默返回 null，不抛异常', () async {
    final client = MockClient((_) async => http.Response('boom', 500));
    final manager = BookSourceManager(prefs);
    await manager.load();
    final service = BookSourceCloudSyncService(
      client: CloudSyncClient(httpClient: client),
    );

    final result = await service.syncIfStale(prefs: prefs, manager: manager);
    expect(result, isNull);
  });

  test('sync 网络失败时抛 CloudSyncException 供 UI 展示', () async {
    final client = MockClient((_) async => http.Response('nope', 503));
    final manager = BookSourceManager(prefs);
    await manager.load();
    final service = BookSourceCloudSyncService(
      client: CloudSyncClient(httpClient: client),
    );

    expect(
      () => service.sync(prefs: prefs, manager: manager),
      throwsA(isA<CloudSyncException>()),
    );
  });
}
