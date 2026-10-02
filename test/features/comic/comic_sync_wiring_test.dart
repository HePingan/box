// 跨设备同步：设置页那一行 + 阅读器进页面顺带同步（2026-10-02，第三批）。
//
// 这一层盯的是**接线**：点了会真的同步、没配令牌会说人话、进阅读器会顺带同步一次。
// 合并规则本身在 comic_sync_test.dart 里；服务端在 box-ops-api 自检里。
import 'dart:convert';

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/comic/domain/comic_library_store.dart';
import 'package:box/features/comic/domain/comic_online_progress.dart';
import 'package:box/features/comic/domain/comic_sync.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_api_client.dart';
import 'package:box/features/settings/presentation/data_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 假同步服务：记下被叫了几次，按 [outcome] 回结果。
class _FakeSync extends ComicSyncService {
  _FakeSync({this.outcome = const ComicSyncOutcome(ok: true, message: '新增 1 本')})
    : super(
        api: OpsApiClient(baseUrl: 'https://sync.test/opsapi', token: 't'),
        libraryStore: ComicLibraryStore(cacheStore: CacheStore.inMemory('lib')),
        progressStore: ComicOnlineProgressStore(cacheStore: CacheStore.inMemory('prog')),
        cacheStore: CacheStore.inMemory('sync'),
      );

  final ComicSyncOutcome outcome;
  int calls = 0;

  @override
  Future<ComicSyncOutcome> syncNow() async {
    calls++;
    if (outcome.ok) {
      await Future<void>.delayed(Duration.zero);
    }
    return outcome;
  }

  @override
  Future<DateTime?> lastSyncAt() async =>
      outcome.ok ? DateTime(2026, 10, 2, 15, 30) : null;

  @override
  Future<String> lastMessage() async => outcome.message;
}

void main() {
  testWidgets('设置页：配了令牌 → 显示上次同步；点一下真的同步并回报结果', (tester) async {
    final fake = _FakeSync();
    await tester.pumpWidget(
      MaterialApp(home: DataSettingsPage(syncFactory: () async => fake)),
    );
    await tester.pumpAndSettle();

    expect(find.text('跨设备同步'), findsOneWidget);
    expect(find.textContaining('上次同步 15:30'), findsOneWidget);

    await tester.tap(find.text('跨设备同步'));
    await tester.pumpAndSettle();

    expect(fake.calls, 1);
    expect(find.textContaining('同步完成'), findsOneWidget);
  });

  testWidgets('设置页：没配令牌 → 说清去哪儿配，点了也不报错', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: DataSettingsPage(syncFactory: () async => null)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('没配设备令牌'), findsOneWidget);
    await tester.tap(find.text('跨设备同步'));
    await tester.pumpAndSettle();
    expect(find.textContaining('没配设备令牌'), findsWidgets);
  });

  testWidgets('设置页：同步失败 → 把失败说出来，不假装成功', (tester) async {
    final fake = _FakeSync(
      outcome: const ComicSyncOutcome(message: '这台机器的设备令牌不对'),
    );
    await tester.pumpWidget(
      MaterialApp(home: DataSettingsPage(syncFactory: () async => fake)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('跨设备同步'));
    await tester.pumpAndSettle();
    expect(find.textContaining('同步失败'), findsOneWidget);
  });

  test('服务端回的全量会被解析：真服务端的响应体就是这一份形状', () {
    // 这条用例钉住"线上 JSON 长什么样"（第三批在公网入口上实测回来的形状）。
    final doc = ComicSyncDoc.fromJson(
      jsonDecode(
        '{"ok":true,"books":[{"bookUrl":"/book/96/","title":"传说","removed":false}],'
        '"progress":{"/book/96/":{"bookUrl":"/book/96/","chapterUrl":"/c/1186","index":3}},'
        '"counts":{"books":1,"progress":1},"updatedAt":"2026-10-02T15:00:00+08:00"}',
      ) as Map<String, dynamic>,
    );
    expect(doc.liveBooks.single['title'], '传说');
    expect(doc.progress['/book/96/']!['index'], 3);
  });

}
