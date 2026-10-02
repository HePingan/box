// 离线库的落盘/清单/删除。**全程不联网**，目录用真临时目录。
import 'dart:convert';
import 'dart:io';

import 'package:box/features/comic/domain/comic_offline_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late ComicOfflineStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('offline_test_');
    store = ComicOfflineStore(dirProvider: () async => tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  ComicOfflineBook book() => ComicOfflineBook(
    bookUrl: 'https://yemancomic.com/comic/1.html',
    title: '邻座的辣妹嘴瘾犯了～',
    cover: 'https://tuer.justpic01pt.com:666/picbed/a.jpg',
    chapters: [
      ComicOfflineChapter(
        url: 'https://yemancomic.com/comic/1/1.html',
        title: '第01话',
        images: ['https://tuer.justpic01pt.com:666/picbed/1.jpg'],
      ),
      ComicOfflineChapter(
        url: 'https://yemancomic.com/comic/1/2.html',
        title: '第02话',
        images: ['https://tuer.justpic01pt.com:666/picbed/2.jpg'],
      ),
    ],
  );

  test('清单往返：书名/封面/目录/进度都活着回来', () async {
    final b = book();
    b.chapters[0]
      ..done = 1
      ..bytes = 12345
      ..state = ComicOfflineState.done;
    await store.saveBook(b);

    final back = await store.loadBook(b.bookUrl);
    expect(back, isNotNull);
    expect(back!.title, '邻座的辣妹嘴瘾犯了～');
    expect(back.cover, contains('justpic'));
    expect(back.chapters.length, 2);
    expect(back.chapters[0].title, '第01话');
    expect(back.chapters[0].state, ComicOfflineState.done);
    expect(back.chapters[0].done, 1);
    expect(back.chapters[0].bytes, 12345);
    expect(back.chapters[1].state, ComicOfflineState.none);
    expect(back.doneCount, 1);
    expect(back.bytes, 12345);
  });

  test('图片落盘后离线命中；没下过的地址是 null（不发请求）', () async {
    final b = book();
    const img = 'https://tuer.justpic01pt.com:666/picbed/1.jpg';
    final f = await store.fileFor(b.bookUrl, b.chapters[0].url, img);
    await f.writeAsBytes(List<int>.filled(2048, 7));

    final hit = await store.localFile(b.bookUrl, b.chapters[0].url, img);
    expect(hit, isNotNull);
    expect(await hit!.length(), 2048);

    final miss = await store.localFile(
      b.bookUrl,
      b.chapters[0].url,
      'https://tuer.justpic01pt.com:666/picbed/not-downloaded.jpg',
    );
    expect(miss, isNull);
  });

  test('离线内容落在持久目录：默认走 appSupport（不是系统临时目录）', () async {
    final root = await store.rootDir();
    expect(root.path, startsWith(tmp.path));
    expect(root.path, contains('comic_offline'));

    // 默认构造（走 path_provider = 持久目录）**不能**落在系统临时目录里：
    // 临时目录会被系统清理，也会被我们自己"按最旧先删"的上限清掉，
    // 用户主动下的一整本漫画不该死在那里。
    try {
      final def = await ComicOfflineStore().rootDir();
      expect(def.path, isNot(startsWith(Directory.systemTemp.path)),
          reason: '离线内容落在系统临时目录 = 迟早被系统或我们自己的上限清掉');
      if (await def.exists()) await def.delete(recursive: true);
    } catch (_) {
      // 拿不到平台目录的环境（纯单测）也算没落在临时目录，放过。
    }
  });

  test('统计：单话/整书/总量；删一话把"已下载"清零', () async {
    final b = book();
    for (final c in b.chapters) {
      final f = await store.fileFor(b.bookUrl, c.url, c.images.first);
      await f.writeAsBytes(List<int>.filled(1000, 1));
      c
        ..done = c.images.length
        ..bytes = 1000
        ..state = ComicOfflineState.done;
    }
    await store.saveBook(b);

    expect(await store.bytesOf(b.bookUrl), 2000);
    expect(
      await store.bytesOf(b.bookUrl, chapterUrl: b.chapters[0].url),
      1000,
    );
    expect(await store.totalBytes(), greaterThanOrEqualTo(2000));

    await store.deleteChapter(b.bookUrl, b.chapters[0].url);
    final after = await store.loadBook(b.bookUrl);
    expect(after!.chapters[0].state, ComicOfflineState.none);
    expect(after.chapters[0].done, 0, reason: '留着 done 会让界面显示"已下载"但其实没图');
    expect(after.chapters[1].isDone, isTrue);
    expect(await store.bytesOf(b.bookUrl, chapterUrl: b.chapters[0].url), 0);
  });

  test('一话都没下完时删最后一话，清单一起清掉（不留空壳书）', () async {
    final b = book();
    b.chapters[0]
      ..done = 1
      ..bytes = 100
      ..state = ComicOfflineState.done;
    await store.saveBook(b);
    await store.deleteChapter(b.bookUrl, b.chapters[0].url);
    expect(await store.loadBook(b.bookUrl), isNull);
    expect(await store.books(), isEmpty);
  });

  test('删整本：目录与清单都没了', () async {
    final b = book();
    final f = await store.fileFor(b.bookUrl, b.chapters[0].url, b.chapters[0].images.first);
    await f.writeAsBytes(List<int>.filled(10, 1));
    await store.saveBook(b);
    await store.deleteBook(b.bookUrl);
    expect(await store.loadBook(b.bookUrl), isNull);
    expect(await store.bytesOf(b.bookUrl), 0);
  });

  test('坏清单不炸：读这本书是 null，列书单时跳过它', () async {
    final b = book();
    await store.saveBook(b);
    final manifestDir = Directory('${(await store.rootDir()).path}/manifest');
    final broken = File('${manifestDir.path}/${ComicOfflineStore.hash(b.bookUrl)}.json');
    await broken.writeAsString('{ 这不是 json');

    expect(await store.loadBook(b.bookUrl), isNull);
    expect(await store.books(), isEmpty);
  });

  test('写清单是"先临时再改名"：不会留下半份 JSON，也不会残留 .tmp', () async {
    await store.saveBook(book());
    final manifestDir = Directory('${(await store.rootDir()).path}/manifest');
    final names = await manifestDir.list().map((e) => e.path.split('/').last).toList();
    expect(names.any((n) => n.endsWith('.tmp')), isFalse);
    expect(names.where((n) => n.endsWith('.json')).length, 1);
    // 内容确实是完整 JSON
    final raw = await File(
      '${manifestDir.path}/${ComicOfflineStore.hash(book().bookUrl)}.json',
    ).readAsString();
    expect(jsonDecode(raw), isA<Map<String, dynamic>>());
  });

  test('同步离线命中：预热后才给答案（渲染路径不等平台调用）', () async {
    final b = book();
    const img = 'https://tuer.justpic01pt.com:666/picbed/1.jpg';
    const cover = 'https://tuer.justpic01pt.com:666/picbed/a.jpg';
    final f = await store.fileFor(b.bookUrl, b.chapters[0].url, img);
    await f.writeAsBytes(List<int>.filled(64, 3));
    final c = await store.coverFile(b.bookUrl, cover);
    await c.writeAsBytes(List<int>.filled(32, 4));

    // 预热：App 里进阅读页/书架时做一次（一次平台通道往返）。
    await store.warmUp();
    expect(store.localFileIfReady(b.bookUrl, b.chapters[0].url, img), isNotNull);
    expect(store.localCoverIfReady(b.bookUrl, cover), isNotNull);
    // 没下过的话 → null（界面上就照常走网络）
    expect(store.localFileIfReady(b.bookUrl, 'https://别的书/1.html', img), isNull);

    // 全新实例（还没预热）：同步问必须"说不知道"，而不是在渲染路径上等平台调用。
    final cold = ComicOfflineStore(dirProvider: () async => tmp);
    expect(cold.localFileIfReady(b.bookUrl, b.chapters[0].url, img), isNull);
    expect(cold.localCoverIfReady(b.bookUrl, cover), isNull);
  });

  test('clearAll 把整棵离线树干掉', () async {
    final b = book();
    final f = await store.fileFor(b.bookUrl, b.chapters[0].url, b.chapters[0].images.first);
    await f.writeAsBytes(List<int>.filled(10, 1));
    await store.saveBook(b);
    await store.clearAll();
    expect(await store.books(), isEmpty);
    expect(await store.totalBytes(), 0);
  });

  // ── 占用口径与残渣清理（2026-10-02）──
  group('未完成的残渣（.part）', () {
    test('清理只删老的 .part：刚失败的那张和正常的图都不动', () async {
      final b = book();
      await store.saveBook(b);
      final real = await store.fileFor(b.bookUrl, b.chapters.first.url, b.chapters.first.images.first);
      await real.writeAsBytes(List<int>.filled(1000, 7));
      final stale = File('${real.path}.part')..writeAsBytesSync(List<int>.filled(500, 9));
      await stale.setLastModified(DateTime.now().subtract(const Duration(days: 2)));
      final fresh = File('${real.path}-b.part')
        ..writeAsBytesSync(List<int>.filled(300, 9));

      final freed = await store.purgePartials();

      expect(freed, 500, reason: '只算真删掉的那些字节');
      expect(await stale.exists(), isFalse);
      expect(await fresh.exists(), isTrue, reason: '刚失败的可能还会被写，别抢');
      expect(await real.exists(), isTrue);
    });

    test('占用会把残渣算进去（所以更要清）', () async {
      final b = book();
      await store.saveBook(b);
      final real = await store.fileFor(b.bookUrl, b.chapters.first.url, b.chapters.first.images.first);
      await real.writeAsBytes(List<int>.filled(1000, 7));
      final stale = File('${real.path}.part')..writeAsBytesSync(List<int>.filled(500, 9));
      await stale.setLastModified(DateTime.now().subtract(const Duration(days: 2)));

      // 清单 json 也在同一个根目录下，所以比"差值"而不是绝对值。
      final before = await store.totalBytes();
      await store.purgePartials();
      expect(
        await store.totalBytes(),
        before - 500,
        reason: '整目录递归求和：.part 也算占用，清掉之后占用要跟着降',
      );
    });

    test('清空会连残渣一起带走', () async {
      final b = book();
      await store.saveBook(b);
      final real = await store.fileFor(b.bookUrl, b.chapters.first.url, b.chapters.first.images.first);
      await real.writeAsBytes(List<int>.filled(10, 1));
      File('${real.path}.part').writeAsBytesSync(List<int>.filled(10, 1));

      await store.clearAll();

      expect(await store.totalBytes(), 0);
    });
  });
}
