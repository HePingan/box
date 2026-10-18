// 老版本导入的漫画"页还在不在"的体检 + 提醒去重。
//
// 锁住三件事：
//   ① 在线书一律不参与判断（它的页在站点上，本机没有文件，参与就是误报）；
//   ② 判定为缺页是靠**采样**的：只要抽到的页全没了才算整本没了，抽到的页有任意一页
//      还在就不能催用户重新导入（误报的代价是把好书判死）；
//   ③ 「提醒过哪些书」要能跨启动记住，并且存储写坏时宁可多提醒一次。
library;

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/comic/domain/comic_book.dart';
import 'package:box/features/comic/domain/comic_page_health.dart';
import 'package:flutter_test/flutter_test.dart';

ComicBook book({
  required String id,
  required ComicSourceType type,
  List<String> pages = const <String>[],
  String? filePath,
  String? folderPath,
  String? onlineUrl,
  int createdAt = 1,
}) {
  return ComicBook(
    id: id,
    title: '书$id',
    sourceType: type,
    pages: pages,
    filePath: filePath,
    folderPath: folderPath,
    onlineUrl: onlineUrl,
    createdAt: createdAt,
  );
}

/// 造一本 file 类型的书，页路径是假的（探针自己决定存不存在）。
ComicBook fileBook(String id, {int pageCount = 10, String dir = '/tmp/comic_x'}) {
  return book(
    id: id,
    type: ComicSourceType.file,
    filePath: '/downloads/$id.cbz',
    pages: <String>[
      for (var i = 0; i < pageCount; i++) '$dir/$i.jpg',
    ],
  );
}

/// 记录探针被问过哪些路径 —— 用来证明"没有逐页扫"。
class ProbeLog {
  final List<String> asked = <String>[];

  Future<bool> Function(String) call(bool Function(String path) alive) {
    return (String path) async {
      asked.add(path);
      return alive(path);
    };
  }
}

void main() {
  group('ComicPageHealthChecker', () {
    test('空书架：什么都不查，也不算有人缺页', () async {
      final log = ProbeLog();
      final health = await ComicPageHealthChecker(
        probe: log.call((_) => true),
      ).check(const <ComicBook>[]);

      expect(health.total, 0);
      expect(health.checked, 0);
      expect(health.missing, 0);
      expect(health.missingBookIds, isEmpty);
      expect(health.hasMissing, isFalse);
      expect(log.asked, isEmpty);
    });

    test('全是在线书：整批跳过，连探针都不碰', () async {
      final log = ProbeLog();
      final health = await ComicPageHealthChecker(
        probe: log.call((_) => true),
      ).check(<ComicBook>[
        book(
          id: 'o1',
          type: ComicSourceType.online,
          onlineUrl: 'https://example.com/1.html',
          pages: const <String>['https://example.com/1.jpg'],
        ),
        book(
          id: 'o2',
          type: ComicSourceType.online,
          onlineUrl: 'https://example.com/2.html',
        ),
      ]);

      expect(health.total, 2);
      expect(health.checked, 0, reason: '在线书的页不在本机，不参与体检');
      expect(health.skipped, 2);
      expect(health.missing, 0);
      expect(health.missingBookIds, isEmpty);
      expect(log.asked, isEmpty, reason: '在线书连一次探针都不该触发');
    });

    test('file 书整本没页了（旧版临时目录被清）：判成缺页', () async {
      final health = await ComicPageHealthChecker(
        probe: (_) async => false,
      ).check(<ComicBook>[fileBook('f1')]);

      expect(health.checked, 1);
      expect(health.healthy, 0);
      expect(health.missing, 1);
      expect(health.missingBookIds, <String>['f1']);
      expect(health.hasMissing, isTrue);
      expect(health.isMissing('f1'), isTrue);
      expect(health.isMissing('别的书'), isFalse);
    });

    test('folder 书指向的文件夹被删：同样判成缺页', () async {
      final health = await ComicPageHealthChecker(
        probe: (_) async => false,
      ).check(<ComicBook>[
        book(
          id: 'd1',
          type: ComicSourceType.folder,
          folderPath: '/sdcard/漫画/某本',
          pages: const <String>['/sdcard/漫画/某本/1.jpg'],
        ),
      ]);

      expect(health.missingBookIds, <String>['d1']);
    });

    test('文件都在：healthy，且不进提醒列表', () async {
      final health = await ComicPageHealthChecker(
        probe: (_) async => true,
      ).check(<ComicBook>[fileBook('ok1'), fileBook('ok2')]);

      expect(health.checked, 2);
      expect(health.healthy, 2);
      expect(health.missing, 0);
      expect(health.missingBookIds, isEmpty);
    });

    test('好坏混在一起：只挑出真的没页的那本，顺序跟着传入顺序', () async {
      final health = await ComicPageHealthChecker(
        probe: (path) async => !path.startsWith('/bad/'),
      ).check(<ComicBook>[
        fileBook('good', dir: '/good'),
        fileBook('bad1', dir: '/bad'),
        book(id: 'online', type: ComicSourceType.online),
        fileBook('bad2', dir: '/bad'),
      ]);

      expect(health.total, 4);
      expect(health.checked, 3);
      expect(health.skipped, 1);
      expect(health.healthy, 1);
      expect(health.missingBookIds, <String>['bad1', 'bad2']);
    });

    test('没有页路径的本地书：无从判断，不算缺页也不催重新导入', () async {
      final log = ProbeLog();
      final health = await ComicPageHealthChecker(
        probe: log.call((_) => false),
      ).check(<ComicBook>[
        book(
          id: 'empty',
          type: ComicSourceType.file,
          filePath: '/downloads/empty.cbz',
        ),
        book(id: 'blank', type: ComicSourceType.folder, pages: const <String>['']),
      ]);

      expect(health.checked, 0);
      expect(health.skipped, 2);
      expect(health.missing, 0);
      expect(log.asked, isEmpty);
    });

    test('探针抛异常时按"还在"处理：不把用户好好的书报成丢页', () async {
      final health = await ComicPageHealthChecker(
        probe: (_) async => throw const FileSystemExceptionLike(),
      ).check(<ComicBook>[fileBook('x')]);

      expect(health.missing, 0, reason: '探不动不等于文件没了');
      expect(health.healthy, 1);
    });

    group('采样', () {
      test('1000 页的健康书只探 1 页就停 —— 同生共死，不必逐页 stat', () async {
        final log = ProbeLog();
        final health = await ComicPageHealthChecker(
          probe: log.call((_) => true),
        ).check(<ComicBook>[fileBook('big', pageCount: 1000)]);

        expect(health.healthy, 1);
        // 一命中就停：健康书只探 1 页。
        expect(log.asked.length, 1);
      });

      test('采样落点是头 / 中 / 尾，不是只探第一页', () async {
        final pages = <String>[for (var i = 0; i < 100; i++) 'p$i.jpg'];
        final picked = ComicPageHealthChecker().samplePages(pages);

        expect(picked.length, 3);
        expect(picked.first, 'p0.jpg');
        expect(picked.contains('p99.jpg'), isTrue, reason: '尾巴也要兜住');
        expect(picked, contains('p50.jpg'));
      });

      test('页数少于采样数时全探，不重复也不越界', () async {
        final checker = ComicPageHealthChecker();
        expect(checker.samplePages(<String>['a.jpg']), <String>['a.jpg']);
        expect(checker.samplePages(<String>['a.jpg', 'b.jpg']), <String>['a.jpg', 'b.jpg']);
      });

      test('只有中间那页还在也算健康 —— 少一页不等于整本没了', () async {
        final health = await ComicPageHealthChecker(
          // 头尾没了、中间还在：说明目录还在，不该催重新导入。
          probe: (path) async => path == '/tmp/comic_x/50.jpg',
        ).check(<ComicBook>[fileBook('half', pageCount: 100)]);

        expect(health.checked, 1);
        expect(health.missing, 0);
        expect(health.healthy, 1);
      });

      test('sampleCount 可调：全灭的书会探满抽到的页数', () async {
        final log = ProbeLog();
        final health = await ComicPageHealthChecker(
          probe: log.call((_) => false),
          sampleCount: 2,
        ).check(<ComicBook>[fileBook('two', pageCount: 500)]);

        expect(health.missing, 1);
        // 全灭的探针会把抽到的每一页都问一遍：证明抽了 2 页。
        expect(log.asked.length, 2);
        expect(log.asked.first, '/tmp/comic_x/0.jpg');
      });

      test('单页书：探一页就够', () async {
        final log = ProbeLog();
        final health = await ComicPageHealthChecker(
          probe: log.call((_) => false),
        ).check(<ComicBook>[fileBook('single', pageCount: 1)]);

        expect(health.missing, 1);
        expect(log.asked.length, 1);
      });
    });

    test('checkComicPageHealth 便利入口：真实文件系统也走同一条路', () async {
      final health = await checkComicPageHealth(<ComicBook>[
        book(
          id: 'nonexistent',
          type: ComicSourceType.file,
          // 这个路径在测试机上一定不存在。
          pages: const <String>['/box_test/definitely/not/here/0.jpg'],
        ),
      ]);

      expect(health.missingBookIds, <String>['nonexistent']);
    });
  });

  group('ComicPageHealthNoticeStore', () {
    late CacheStore cache;
    late ComicPageHealthNoticeStore store;

    setUp(() {
      cache = CacheStore.inMemory(
        'comic_page_health_test_${DateTime.now().microsecondsSinceEpoch}',
      );
      store = ComicPageHealthNoticeStore(cacheStore: cache);
    });

    const health = ComicPageHealth(
      total: 3,
      checked: 3,
      healthy: 1,
      missing: 2,
      missingBookIds: <String>['a', 'b'],
    );

    test('一开始没提醒过任何书', () async {
      expect(await store.notifiedIds(), isEmpty);
      expect(await store.pendingForNotice(health), <String>['a', 'b']);
    });

    test('记过之后同一批书不再提示（不然每次启动都弹）', () async {
      await store.markNotified(<String>['a', 'b']);

      expect(await store.notifiedIds(), <String>{'a', 'b'});
      expect(await store.pendingForNotice(health), isEmpty);
    });

    test('只记了一部分：没记过的仍然要提示', () async {
      await store.markNotified(<String>['a']);
      expect(await store.pendingForNotice(health), <String>['b']);
    });

    test('跨实例读得回来（提醒状态是全 App 一份，不是这个对象的字段）', () async {
      await store.markNotified(<String>['a', 'b']);
      final again = ComicPageHealthNoticeStore(cacheStore: cache);
      expect(await again.notifiedIds(), <String>{'a', 'b'});
    });

    test('没有缺页时不查存储也不提示', () async {
      const clean = ComicPageHealth(
        total: 1,
        checked: 1,
        healthy: 1,
        missing: 0,
        missingBookIds: <String>[],
      );
      expect(await store.pendingForNotice(clean), isEmpty);
    });

    test('重复标记不会把 id 存重（集合语义）', () async {
      await store.markNotified(<String>['a']);
      await store.markNotified(<String>['a', 'b']);

      final ids = await store.notifiedIds();
      expect(ids.length, 2);
      expect(ids, <String>{'a', 'b'});
    });

    test('空集合不写盘：不值得为一次空调用碰磁盘', () async {
      await store.markNotified(const <String>[]);
      await store.markNotified(const <String>['', '']);
      expect(await store.notifiedIds(), isEmpty);
    });

    test('书被删掉 / 修好了：旧 id 收敛掉，集合不无限长', () async {
      await store.markNotified(<String>['a', 'b', 'c']);
      await store.retainOnly(<String>['b', 'a', 'new']);

      expect(await store.notifiedIds(), <String>{'a', 'b'});
    });

    test('收敛后没有变化就不重写（少一次写盘）', () async {
      final counting = CountingCacheStore(
        'comic_page_health_write_${DateTime.now().microsecondsSinceEpoch}',
      );
      final quiet = ComicPageHealthNoticeStore(cacheStore: counting);
      await quiet.markNotified(<String>['a', 'b']);
      expect(counting.writes, 1);

      // 现存 id 全都还在缺页集合里：收敛结果是同一份，不该再写一次。
      await quiet.retainOnly(<String>['a', 'b', 'c']);
      expect(counting.writes, 1);

      // 真收敛掉一个 id 时才写。
      await quiet.retainOnly(<String>['a']);
      expect(counting.writes, 2);
      expect(await quiet.notifiedIds(), <String>{'a'});
    });

    test('存储里是坏类型（不是列表）：当没提醒过，宁可多提醒一次', () async {
      await cache.write('notified_ids', 'not-a-list');
      final bad = ComicPageHealthNoticeStore(cacheStore: cache);

      expect(await bad.notifiedIds(), isEmpty);
      expect(await bad.pendingForNotice(health), <String>['a', 'b']);
    });

    test('列表里混进非字符串项：只捞字符串，不整批作废', () async {
      await cache.write('notified_ids', <dynamic>['a', 42, null, '', 'b']);
      final mixed = ComicPageHealthNoticeStore(cacheStore: cache);

      expect(await mixed.notifiedIds(), <String>{'a', 'b'});
    });

    test('clear 之后从头开始提示', () async {
      await store.markNotified(<String>['a', 'b']);
      await store.clear();

      expect(await store.notifiedIds(), isEmpty);
      expect(await store.pendingForNotice(health), <String>['a', 'b']);
    });
  });
}

/// 数写盘次数的 CacheStore：用来证明"没变化就不重写"。
class CountingCacheStore extends CacheStore {
  CountingCacheStore(String namespace)
    : super(namespace: namespace, webMode: true);

  int writes = 0;

  @override
  Future<void> write(String key, dynamic data, {Duration? ttl}) {
    writes++;
    return super.write(key, data, ttl: ttl);
  }
}

/// 造一个和 `dart:io` 同形的异常，避免测试为了抛一次异常去引 dart:io。
class FileSystemExceptionLike implements Exception {
  const FileSystemExceptionLike();
}
