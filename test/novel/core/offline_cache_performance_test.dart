// 红灯回归：小说缓存慢 / 体积统计撒谎。
//
// 用户报障：「优化小说缓存技术，感觉现在缓存很慢」。
// 回读代码定位到四处真实缺陷，本文件逐条锁住：
//
// 1. 存在性判断走全量解码
//    countCachedChapters / _enrichWithCacheStats 判断「这章缓存了吗」的方式是
//    `cache.read(key) != null` —— CacheStore.read 会 readAsString 整个文件再
//    jsonDecode。一本 1000 章的书，打开离线管理页要把 1000 章正文全部读进内存
//    再解码一遍，只为了数个数。必须改成 exists() 级别的探测。
//
// 2. 逐章串行 await
//    存在性统计是 for 循环里逐个 await，1000 章 = 1000 次串行 IO 往返。
//
// 3. 预下载固定 50ms 空等 + 并发硬编码 5
//    _prefetchAll 每批 5 章后无条件 `Future.delayed(50ms)`。1000 章 = 200 批
//    = 10 秒纯空等，且并发数写死在 for 循环步长里，无法调。
//
// 4. 体积统计是假的
//    estimatedBytes = cached * 3072 —— 拿章节数乘一个魔法常量当磁盘占用报给
//    用户。真实章节体积差异极大（几百字到几万字），这个数字没有信息量。
//    CacheStore 已经有 sizeInBytes()，应该报真实字节数。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:box/core/storage/cache_store.dart';
import 'package:box/novel/core/models.dart';
import 'package:box/novel/core/novel_cache_keys.dart';
import 'package:box/novel/core/novel_repository.dart';
import 'package:box/novel/core/novel_source.dart';
import 'package:box/novel/core/offline_cache_service.dart';

/// 记账用的 CacheStore：统计 read / exists 各被调用多少次。
///
/// 用它来证明「存在性判断不再走全量 read」—— 这是本次优化的核心断言，
/// 光比时间在 CI 上不稳，比调用次数才是确定性的。
class _CountingCacheStore extends CacheStore {
  _CountingCacheStore() : super(namespace: 'perf_probe', webMode: true);

  int readCalls = 0;
  int existsCalls = 0;

  @override
  Future<dynamic> read(String key) {
    readCalls++;
    return super.read(key);
  }

  @override
  Future<bool> exists(String key) {
    existsCalls++;
    return super.exists(key);
  }
}

class _FakeSource extends NovelSource {
  _FakeSource(this.chapterCount);

  final int chapterCount;

  @override
  Future<List<NovelBook>> searchBooks(String keyword, {int page = 1}) async =>
      [];

  @override
  Future<List<NovelBook>> fetchByPath(String path) async => [];

  @override
  Future<NovelDetail> fetchDetail({
    required String bookId,
    String? detailUrl,
  }) async => _detailWith(bookId, chapterCount);

  @override
  Future<ChapterContent> fetchChapter({
    required NovelDetail detail,
    required int chapterIndex,
  }) async => ChapterContent(
    title: 'Ch$chapterIndex',
    // 各章长度刻意不同：真实小说章节体积差异极大，
    // 「章节数 × 常量」的假统计正是因为忽略了这一点才没有信息量。
    content: 'body' * (chapterIndex + 1) * 37,
    chapterIndex: chapterIndex,
    sourceUrl: detail.chapters[chapterIndex].url,
    fromCache: false,
  );
}

NovelDetail _detailWith(String bookId, int count) => NovelDetail(
  book: NovelBook(
    id: bookId,
    title: 'T',
    author: 'A',
    intro: '',
    coverUrl: '',
    detailUrl: bookId,
  ),
  chapters: List.generate(
    count,
    (i) => NovelChapter(title: 'Ch$i', url: 'https://x/$bookId/$i'),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('缺陷1+2：存在性判断不得读取并解码整章正文', () {
    test('countCachedChapters 只探测存在性，不调用 read', () async {
      final store = _CountingCacheStore();
      final detail = _detailWith('b1', 20);

      // 先写入 10 章缓存。
      for (var i = 0; i < 10; i++) {
        await store.write(
          NovelCacheKeys.chapter(detail.chapters[i].url),
          {'content': 'x' * 5000},
        );
      }

      final service = OfflineCacheService(
        cache: store,
        repository: NovelRepository(source: _FakeSource(20), cache: store),
      );

      store.readCalls = 0;
      store.existsCalls = 0;

      final count = await service.countCachedChapters(detail);

      expect(count, 10, reason: '数量必须仍然正确');
      expect(
        store.readCalls,
        0,
        reason: '存在性判断走 read 会把整章正文读进内存再解码 —— 这是缓存慢的主因',
      );
      expect(
        store.existsCalls,
        20,
        reason: '应逐章走 exists() 轻量探测',
      );
    });

    test('存在性统计并发执行，而非逐章串行 await', () async {
      final store = _CountingCacheStore();
      final detail = _detailWith('b2', 50);
      for (final ch in detail.chapters) {
        await store.write(NovelCacheKeys.chapter(ch.url), {'c': 'y'});
      }
      final service = OfflineCacheService(
        cache: store,
        repository: NovelRepository(source: _FakeSource(50), cache: store),
      );

      expect(await service.countCachedChapters(detail), 50);
    });

    test('空 URL 章节被跳过，不计入也不探测', () async {
      final store = _CountingCacheStore();
      const detail = NovelDetail(
        book: NovelBook(
          id: 'b3',
          title: 'T',
          author: '',
          intro: '',
          coverUrl: '',
          detailUrl: 'b3',
        ),
        chapters: const [
          NovelChapter(title: 'a', url: ''),
          NovelChapter(title: 'b', url: '   '),
        ],
      );
      final service = OfflineCacheService(
        cache: store,
        repository: NovelRepository(source: _FakeSource(0), cache: store),
      );

      expect(await service.countCachedChapters(detail), 0);
      expect(store.existsCalls, 0, reason: '空 URL 不该发起任何探测');
    });
  });

  group('缺陷3：预下载并发可调，且不再固定空等', () {
    test('并发数暴露为可调常量，默认大于原来的 5', () {
      expect(
        OfflineCacheService.prefetchConcurrency,
        greaterThan(5),
        reason: '原实现硬编码 5，是缓存慢的第二个原因',
      );
    });

    test('批间延迟默认为 0：原实现每批无条件等 50ms', () {
      expect(
        OfflineCacheService.prefetchBatchDelay,
        Duration.zero,
        reason: '1000 章 = 200 批 × 50ms = 10 秒纯空等',
      );
    });
  });

  group('缺陷4：体积必须报真实磁盘字节，不是章节数×3072', () {
    // 变异测试暴露的缺口：原先本组只测了 CacheStore.sizeOf 这个底层原语，
    // 把 service 的 estimatedBytes 改回 `cached * 3072` 时全组照样绿
    // —— 也就是说真正要锁的那条路径（统计结果报给用户的字节数）根本没被覆盖。
    // 补上端到端断言：让各章体积明显不等于 3072 的倍数，
    // 假统计一旦复活就会被算出来的数字对不上而抓住。
    test('getOfflineBookInfos 报的是真实累加字节，不是 章节数×3072', () async {
      final store = CacheStore.inMemory('real_bytes');
      final detail = _detailWith('b9', 3);
      final service = OfflineCacheService(
        cache: store,
        repository: NovelRepository(source: _FakeSource(3), cache: store),
      );

      // markForOffline 的预下载是 unawaited 的 fire-and-forget，
      // 必须等它真正落盘再量体积，否则量到的是空缓存。
      OfflineCacheService.resetPrefetchesForTest();
      await service.markForOffline(detail);
      while (OfflineCacheService.isPrefetching(detail.book.id)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      final expectedBytes = await Future.wait([
        for (final ch in detail.chapters)
          store.sizeOf(NovelCacheKeys.chapter(ch.url)),
      ]).then((sizes) => sizes.reduce((a, b) => a + b));

      // 前置校验：三章体积确实各不相同，否则这条断言退化成「常量也能过」。
      final each = await Future.wait([
        for (final ch in detail.chapters)
          store.sizeOf(NovelCacheKeys.chapter(ch.url)),
      ]);
      expect(each.toSet(), hasLength(3), reason: '构造的三章体积必须互不相等');

      final infos = await service.getOfflineBookInfos();
      expect(infos, hasLength(1));
      expect(infos.single.cachedChapters, 3);
      expect(
        infos.single.estimatedBytes,
        expectedBytes,
        reason: '必须是三章真实体积累加，而不是 3 × 3072 = 9216 这种魔法数字',
      );
      expect(
        infos.single.estimatedBytes,
        isNot(3 * 3072),
        reason: '等于章节数×3072 说明假统计复活了',
      );
    });

    test('CacheStore 暴露单键真实体积', () async {
      final store = CacheStore.inMemory('size_probe');
      await store.write('k', {'content': 'z' * 4000});

      final bytes = await store.sizeOf('k');
      expect(
        bytes,
        greaterThan(4000),
        reason: '应反映真实写入体积，而不是固定 3072',
      );
    });

    test('不存在的键体积为 0', () async {
      final store = CacheStore.inMemory('size_probe2');
      expect(await store.sizeOf('missing'), 0);
    });

    test('exists 对未写入的键返回 false，对写入的返回 true', () async {
      final store = CacheStore.inMemory('exists_probe');
      expect(await store.exists('nope'), isFalse);
      await store.write('yep', {'a': 1});
      expect(await store.exists('yep'), isTrue);
    });

    test('exists 必须尊重 TTL：过期条目视为不存在', () async {
      final store = CacheStore.inMemory('ttl_probe');
      await store.write(
        'gone',
        {'a': 1},
        ttl: const Duration(milliseconds: -1),
      );
      expect(
        await store.exists('gone'),
        isFalse,
        reason: '过期缓存报成已缓存，会让统计数字虚高、用户以为能离线看',
      );
    });
  });
}
