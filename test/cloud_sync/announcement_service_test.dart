import 'dart:convert';

import 'package:box/features/cloud_sync/data/announcement_service.dart';
import 'package:box/features/cloud_sync/data/cloud_sync_client.dart';
import 'package:box/features/cloud_sync/domain/cloud_sync_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> ann({
  required String id,
  String title = '标题',
  String body = '正文',
  String level = 'info',
  bool pinned = false,
  String publishedAt = '2026-08-30T10:00:00.000Z',
}) => {
  'id': id,
  'title': title,
  'body': body,
  'level': level,
  'pinned': pinned,
  'publishedAt': publishedAt,
  'linkUrl': '',
};

MockClient annClient(List<Map<String, dynamic>> items) => MockClient(
  (_) async => http.Response(
    jsonEncode({'announcements': items, 'count': items.length}),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  ),
);

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  AnnouncementService serviceWith(http.Client client) => AnnouncementService(
    client: CloudSyncClient(httpClient: client),
    prefs: prefs,
  );

  test('拉取公告：全部未读，红点计数等于条目数', () async {
    final state = await serviceWith(
      annClient([ann(id: 'a1'), ann(id: 'a2')]),
    ).load();

    expect(state.items, hasLength(2));
    expect(state.unreadCount, 2);
    expect(state.hasUnread, isTrue);
    expect(state.fromCache, isFalse);
  });

  test('标记已读后红点消失，且已读状态跨次拉取保留（可回看）', () async {
    final service = serviceWith(annClient([ann(id: 'a1'), ann(id: 'a2')]));
    await service.load();
    await service.markRead('a1');

    final second = await service.load();
    expect(second.unreadCount, 1);
    expect(second.isRead('a1'), isTrue);
    expect(second.items, hasLength(2), reason: '已读公告仍在列表中可回看');

    await service.markAllRead(['a1', 'a2']);
    final third = await service.load();
    expect(third.hasUnread, isFalse);
    expect(third.items, hasLength(2));
  });

  test('已读集合会收敛：云端删除的公告 id 不再保留', () async {
    final service1 = serviceWith(annClient([ann(id: 'a1'), ann(id: 'a2')]));
    await service1.load();
    await service1.markAllRead(['a1', 'a2']);
    expect(
      prefs.getStringList(AnnouncementService.readIdsKey),
      containsAll(['a1', 'a2']),
    );

    // 云端把 a1 删了
    final service2 = serviceWith(annClient([ann(id: 'a2')]));
    await service2.load();

    expect(prefs.getStringList(AnnouncementService.readIdsKey), ['a2']);
  });

  test('网络失败时回落缓存并标记 fromCache', () async {
    await serviceWith(annClient([ann(id: 'a1', title: '缓存标题')])).load();

    final offline = serviceWith(MockClient((_) async => http.Response('x', 500)));
    final state = await offline.load();

    expect(state.fromCache, isTrue);
    expect(state.items.single.title, '缓存标题');
  });

  test('无缓存且网络失败时抛出，交由 UI 显示错误', () async {
    final offline = serviceWith(MockClient((_) async => http.Response('x', 500)));
    expect(offline.load(), throwsA(isA<CloudSyncException>()));
  });

  test('loadCachedOnly 不打网络，用于入口红点首帧', () async {
    await serviceWith(annClient([ann(id: 'a1')])).load();

    var called = false;
    final service = serviceWith(
      MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );
    final state = await service.loadCachedOnly();

    expect(called, isFalse);
    expect(state.items, hasLength(1));
    expect(state.unreadCount, 1);
  });

  test('排序：置顶优先，其余按发布时间倒序', () {
    final state = AnnouncementState(
      items: [
        AnnouncementEntry.fromJson(
          ann(id: 'old', publishedAt: '2026-01-01T00:00:00.000Z'),
        ),
        AnnouncementEntry.fromJson(
          ann(id: 'new', publishedAt: '2026-08-01T00:00:00.000Z'),
        ),
        AnnouncementEntry.fromJson(
          ann(
            id: 'pinned',
            pinned: true,
            publishedAt: '2025-01-01T00:00:00.000Z',
          ),
        ),
      ],
      readIds: const <String>{},
      fetchedAt: null,
      fromCache: false,
    );

    expect(state.sorted.map((e) => e.id), ['pinned', 'new', 'old']);
  });

  test('非法 level 归一化为 info，脏 id 被丢弃', () async {
    final state = await serviceWith(
      annClient([
        ann(id: 'a1', level: 'CRITICAL'),
        ann(id: '', title: '没有 id'),
      ]),
    ).load();

    expect(state.items, hasLength(1));
    expect(state.items.single.level, 'info');
  });
}
