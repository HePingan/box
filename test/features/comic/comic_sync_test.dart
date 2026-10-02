// 漫画跨设备同步：合并规则 + 落本地/推回（2026-10-02，第三批）。
//
// 全程用内存 store + 假 HTTP：这些用例盯的是**合并与传播的规则**，
// 不是网络也不是磁盘（真网络那条路已经在服务端自检 + 公网探针里验过了）。
import 'dart:convert';

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/comic/domain/comic_book.dart';
import 'package:box/features/comic/domain/comic_library_store.dart';
import 'package:box/features/comic/domain/comic_online_progress.dart';
import 'package:box/features/comic/domain/comic_sync.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _book(String url, String name, String ts, {bool removed = false}) => {
  'id': url,
  'title': name,
  'sourceType': 'online',
  'onlineUrl': url,
  'bookUrl': url,
  'createdAt': DateTime.parse(ts).millisecondsSinceEpoch,
  'pages': <String>[],
  'updatedAt': ts,
  if (removed) 'removed': true,
};

Map<String, dynamic> _prog(String url, String chapter, String ts) => {
  'bookUrl': url,
  'chapterUrl': chapter,
  'chapterTitle': chapter,
  'index': 0,
  'updatedAt': ts,
};

/// 假服务器：记住收到的每一次 POST，GET 回 [remote]。
class _FakeOps {
  _FakeOps(this.remote);
  Map<String, dynamic> remote;
  final List<Map<String, dynamic>> posted = <Map<String, dynamic>>[];

  OpsApiClient client({String token = 'tok'}) => OpsApiClient(
    baseUrl: 'https://sync.test/opsapi',
    token: token,
    client: MockClient((req) async {
      // 必须走 bytes + utf8：http.Response 的字符串构造器按 latin-1 编码，
      // 书名里只要有一个汉字就抛 "Contains invalid characters"（假服务器踩过一次）。
      // 线上服务端回的就是这个头（验过：application/json; charset=utf-8）；
      // 假服务器漏掉 charset 的话，`res.body` 按 latin-1 解，汉字书名会变成乱码
      // —— 那正是真机上的 user-visible bug，用例要按线上的样子造。
      http.Response json(Object body) => http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
      if (req.method == 'GET') {
        return json(remote);
      }
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      posted.add(body);
      // 真服务端是"合一次再回全量"：这里照同一套规则做，避免假服务器比真服务器宽松。
      final merged = ComicSyncMerge.merge(
        ComicSyncDoc.fromJson(remote),
        ComicSyncDoc.fromJson(body),
      );
      remote = merged.toJson();
      return json(remote);
    }),
  );
}

void main() {
  group('合并规则（与服务端同一组事实）', () {
    test('按 bookUrl 并集，同一本听 updatedAt 新的那份', () {
      final a = ComicSyncDoc(books: [_book('/b/1/', '旧', '2026-10-02T09:00:00+08:00')]);
      final b = ComicSyncDoc(books: [
        _book('/b/1/', '新', '2026-10-02T11:00:00+08:00'),
        _book('/b/2/', '另一台加的', '2026-10-02T11:00:00+08:00'),
      ]);
      final m = ComicSyncMerge.merge(a, b);
      final names = {for (final e in m.books) e['bookUrl']: e['title']};
      expect(names, {'/b/1/': '新', '/b/2/': '另一台加的'});
    });

    test('更旧的改动不会把新名字顶掉（反方向也成立）', () {
      final a = ComicSyncDoc(books: [_book('/b/1/', '新', '2026-10-02T11:00:00+08:00')]);
      final b = ComicSyncDoc(books: [_book('/b/1/', '旧', '2026-10-02T09:00:00+08:00')]);
      expect(ComicSyncMerge.merge(a, b).books.single['title'], '新');
      expect(ComicSyncMerge.merge(b, a).books.single['title'], '新');
    });

    test('删除墓碑比本地收藏新 → 删掉；墓碑更旧 → 本地留着', () {
      final gone = _book('/b/1/', '', '2026-10-02T12:00:00+08:00', removed: true);
      final oldTomb = _book('/b/1/', '', '2026-10-02T08:00:00+08:00', removed: true);
      final local = ComicSyncDoc(books: [_book('/b/1/', '书', '2026-10-02T10:00:00+08:00')]);
      expect(ComicSyncMerge.merge(local, ComicSyncDoc(books: [gone])).books.single['removed'], true);
      final kept = ComicSyncMerge.merge(local, ComicSyncDoc(books: [oldTomb])).books.single;
      expect(kept['removed'], isNot(true));
      expect(kept['title'], '书');
    });

    test('进度逐条听时间新的', () {
      final a = ComicSyncDoc(progress: {'/b/1/': _prog('/b/1/', '/c/1', '2026-10-02T09:00:00+08:00')});
      final b = ComicSyncDoc(progress: {
        '/b/1/': _prog('/b/1/', '/c/9', '2026-10-02T11:00:00+08:00'),
        '/b/2/': _prog('/b/2/', '/c/3', '2026-10-02T11:00:00+08:00'),
      });
      final m = ComicSyncMerge.merge(a, b);
      expect(m.progress['/b/1/']!['chapterUrl'], '/c/9');
      expect(m.progress.keys.toSet(), {'/b/1/', '/b/2/'});
    });
  });

  group('同步服务', () {
    test('没配令牌 → skipped，不算同步失败', () async {
      final fake = _FakeOps(<String, dynamic>{});
      final svc = ComicSyncService(
        api: fake.client(token: ''),
        libraryStore: ComicLibraryStore(cacheStore: CacheStore.inMemory('lib')),
        progressStore: ComicOnlineProgressStore(cacheStore: CacheStore.inMemory('prog')),
        cacheStore: CacheStore.inMemory('sync'),
      );
      final r = await svc.syncNow();
      expect(r.skipped, isTrue);
      expect(r.ok, isFalse);
      expect(fake.posted, isEmpty);
    });

    test('别处新增的收藏与进度落到本机，并把合并结果推回', () async {
      final lib = ComicLibraryStore(cacheStore: CacheStore.inMemory('lib'));
      final prog = ComicOnlineProgressStore(cacheStore: CacheStore.inMemory('prog'));
      final fake = _FakeOps({
        'books': [_book('/b/1/', '别处的书', '2026-10-02T11:00:00+08:00')],
        'progress': {'/b/1/': _prog('/b/1/', '/c/7', '2026-10-02T11:00:00+08:00')},
        'updatedAt': '2026-10-02T11:00:00+08:00',
      });
      final svc = ComicSyncService(
        api: fake.client(),
        libraryStore: lib,
        progressStore: prog,
        cacheStore: CacheStore.inMemory('sync'),
      );
      final r = await svc.syncNow();
      expect(r.ok, isTrue);
      expect(r.addedBooks, 1);
      expect((await lib.fetch()).map((b) => b.title), contains('别处的书'));
      expect((await prog.all())['/b/1/']!.chapterUrl, '/c/7');
      expect(fake.posted, hasLength(1));
      expect(await svc.lastSyncAt(), isNotNull);
      expect(await svc.lastMessage(), contains('新增 1 本'));
    });

    test('别处删掉的书，本机也删（删除传得出去，不会复活）', () async {
      final lib = ComicLibraryStore(cacheStore: CacheStore.inMemory('lib'));
      await lib.add(
        ComicBook(
          id: '/b/1/',
          title: '本机的书',
          sourceType: ComicSourceType.online,
          onlineUrl: '/b/1/',
          createdAt: DateTime.parse('2026-10-02T10:00:00+08:00').millisecondsSinceEpoch,
        ),
      );
      final fake = _FakeOps({
        'books': [_book('/b/1/', '', '2026-10-02T12:00:00+08:00', removed: true)],
        'updatedAt': '2026-10-02T12:00:00+08:00',
      });
      final svc = ComicSyncService(
        api: fake.client(),
        libraryStore: lib,
        progressStore: ComicOnlineProgressStore(cacheStore: CacheStore.inMemory('prog')),
        cacheStore: CacheStore.inMemory('sync'),
      );
      final r = await svc.syncNow();
      expect(r.removedBooks, 1);
      expect(await lib.fetch(), isEmpty);
    });

    test('本地记了墓碑 → 删掉的书会传给服务器（不靠猜）', () async {
      final svc = ComicSyncService(
        api: _FakeOps(<String, dynamic>{'books': [_book('/b/1/', '书', '2026-10-02T11:00:00+08:00')]}).client(),
        libraryStore: ComicLibraryStore(cacheStore: CacheStore.inMemory('lib')),
        progressStore: ComicOnlineProgressStore(cacheStore: CacheStore.inMemory('prog')),
        cacheStore: CacheStore.inMemory('sync'),
      );
      // 界面里删收藏时会来记一笔墓碑（模拟"我在这台机器上删了它"）
      await svc.recordRemoved('/b/1/');
      final doc = await svc.localDoc();
      final tomb = doc.books.firstWhere((b) => b['bookUrl'] == '/b/1/');
      expect(tomb['removed'], isTrue);
    });

    test('本地文件的书不参与同步（换台机器打不开）', () async {
      final lib = ComicLibraryStore(cacheStore: CacheStore.inMemory('lib'));
      await lib.add(
        const ComicBook(
          id: 'local-1',
          title: '本机导入的漫画',
          sourceType: ComicSourceType.folder,
          folderPath: '/sdcard/comic/foo',
          createdAt: 1,
        ),
      );
      await lib.add(
        const ComicBook(
          id: '/b/2/',
          title: '在线书',
          sourceType: ComicSourceType.online,
          onlineUrl: '/b/2/',
          createdAt: 2,
        ),
      );
      final svc = ComicSyncService(
        api: OpsApiClient(baseUrl: 'https://sync.test/opsapi', token: 't'),
        libraryStore: lib,
        progressStore: ComicOnlineProgressStore(cacheStore: CacheStore.inMemory('prog')),
        cacheStore: CacheStore.inMemory('sync'),
      );
      final doc = await svc.localDoc();
      expect(doc.books.map((b) => b['bookUrl']), ['/b/2/']);
    });
  });
}
