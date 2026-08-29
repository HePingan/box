import 'package:box/core/storage/cache_store.dart';
import 'package:box/novel/core/bookshelf_manager.dart';
import 'package:box/novel/core/models.dart';
import 'package:box/novel/core/novel_exceptions.dart';
import 'package:box/novel/core/novel_repository.dart';
import 'package:box/novel/core/novel_source.dart';
import 'package:box/novel/controllers/novel_detail_controller.dart';
import 'package:box/novel/novel_module.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A1：给 controllers/ 层建回归网。
///
/// 这一层此前零测试覆盖，而「缓存进度条走到 300/300 但实际只成功 270」
/// 就是从这里漏出去的。本文件锁死缓存进度语义、取消语义与书源重映射。
void main() {
  // CacheStore / SharedPreferences 走 platform channel，必须先初始化 binding。
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    BookshelfManager.instance.resetForTest();
    NovelModule.resetForTest();
  });

  tearDown(() => NovelModule.resetForTest());

  group('缓存进度统计', () {
    test('全部成功：cacheFailed 为 0，进度走满', () async {
      final c = await _controllerWith(_FakeSource(chapterCount: 5));

      await c.toggleCache();

      expect(c.cacheFailed, 0);
      expect(c.cacheTotal, 5);
      expect(c.isCaching, isFalse);
    });

    test('部分章节失败时 cacheFailed 必须反映真实失败数（核心回归）', () async {
      // 第 1、3 章抛异常 → 3 成功 2 失败
      final source = _FakeSource(
        chapterCount: 5,
        failChapterIndexes: {1, 3},
      );
      final c = await _controllerWith(source);

      await c.toggleCache();

      expect(
        c.cacheFailed,
        2,
        reason: '以前 catch (_) {} 静默吞掉，用户看到「完成」进阅读器才发现空白',
      );
      expect(c.cacheTotal, 5);
    });

    test('全部失败时 cacheFailed == cacheTotal', () async {
      final c = await _controllerWith(
        _FakeSource(chapterCount: 4, failChapterIndexes: {0, 1, 2, 3}),
      );

      await c.toggleCache();

      expect(c.cacheFailed, 4);
      expect(c.cacheFailed, c.cacheTotal);
    });

    test('重新缓存会重置上一轮的失败计数', () async {
      final source = _FakeSource(chapterCount: 3, failChapterIndexes: {0, 1, 2});
      final c = await _controllerWith(source);

      await c.toggleCache();
      expect(c.cacheFailed, 3);

      // 第二轮全部成功
      source.failChapterIndexes = <int>{};
      await c.toggleCache();
      expect(c.cacheFailed, 0, reason: '不清零会把历史失败数累加，越缓存越离谱');
    });
  });

  group('缓存取消语义', () {
    test('缓存中再次调用 toggleCache 即取消，isCaching 立刻转 false', () async {
      final source = _FakeSource(chapterCount: 200, delayPerChapter: const Duration(milliseconds: 5));
      final c = await _controllerWith(source);

      final running = c.toggleCache();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(c.isCaching, isTrue);

      await c.toggleCache(); // 取消
      expect(c.isCaching, isFalse);

      await running;
      expect(
        source.fetchedChapters.length,
        lessThan(200),
        reason: '取消后不该把 200 章全部下完',
      );
    });

    test('dispose 会中断在途缓存', () async {
      final source = _FakeSource(chapterCount: 200, delayPerChapter: const Duration(milliseconds: 5));
      final c = await _controllerWith(source);

      final running = c.toggleCache();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      c.dispose();
      await running;

      expect(source.fetchedChapters.length, lessThan(200));
    });

    test('dispose 后在途缓存不得再 notifyListeners（否则崩）', () async {
      final source = _FakeSource(
        chapterCount: 200,
        delayPerChapter: const Duration(milliseconds: 5),
      );
      final c = await _controllerWith(source);

      final running = c.toggleCache();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      c.dispose();

      // 修复前这里抛 'A NovelDetailController was used after being disposed'
      await expectLater(running, completes);
    });

    test('dispose 后 refreshProgress 不崩', () async {
      final c = await _controllerWith(_FakeSource(chapterCount: 2));
      c.dispose();
      await expectLater(c.refreshProgress(), completes);
    });

    test('空章节列表时 toggleCache 不启动也不崩', () async {
      final c = await _controllerWith(_FakeSource(chapterCount: 0));

      await c.toggleCache();

      expect(c.isCaching, isFalse);
      expect(c.cacheTotal, 0);
    });
  });

  group('书源不兼容时的重映射', () {
    test('详情抛 NovelException 且搜不到同名书 → 给出可操作的错误文案', () async {
      final c = await _controllerWith(
        _FakeSource(chapterCount: 3, failDetail: true),
        waitForLoad: true,
      );

      expect(c.error, contains('书源已更换'));
      expect(c.loading, isFalse);
    });

    test('详情失败但能按书名搜到 → 自动重映射且不报错', () async {
      final source = _FakeSource(
        chapterCount: 3,
        failDetail: true,
        remapTitle: '测试书名',
      );
      final c = await _controllerWith(source, waitForLoad: true);

      expect(c.error, isEmpty, reason: '重映射成功不该给用户看错误');
      expect(c.hasDetail, isTrue);
    });
  });

  group('书架联动', () {
    test('缓存时若书不在书架会自动加入', () async {
      final c = await _controllerWith(_FakeSource(chapterCount: 2));
      expect(c.inBookshelf, isFalse);

      await c.toggleCache();

      expect(c.inBookshelf, isTrue, reason: '离线缓存的书必须在书架可见，否则用户找不回');
    });

    test('toggleBookshelf 双向切换', () async {
      final c = await _controllerWith(_FakeSource(chapterCount: 2));

      await c.toggleBookshelf();
      expect(c.inBookshelf, isTrue);

      await c.toggleBookshelf();
      expect(c.inBookshelf, isFalse);
    });
  });

  test('toggleReverse 翻转章节顺序标记', () async {
    final c = await _controllerWith(_FakeSource(chapterCount: 2));

    expect(c.reverse, isFalse);
    c.toggleReverse();
    expect(c.reverse, isTrue);
  });
}

// ---------------------------------------------------------------------------

Future<NovelDetailController> _controllerWith(
  _FakeSource source, {
  bool waitForLoad = true,
}) async {
  NovelModule.injectRepositoryForTest(
    NovelRepository(
      source: source,
      // inMemory 避开 path_provider 原生插件，纯内存，测试间互不污染
      cache: CacheStore.inMemory('test_detail_ctrl_${_seq++}'),
    ),
  );

  final c = NovelDetailController(
    entryBook: const NovelBook(
      id: 'b1',
      title: '测试书名',
      author: '作者',
      intro: '简介占位，避免触发 _silentPatchMissingMetadata 的后台补全',
      coverUrl: '',
      detailUrl: 'http://x/detail/1',
    ),
  );

  if (waitForLoad) {
    // 构造器里发起异步 _load，等它落地
    for (var i = 0; i < 40 && c.loading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }
  return c;
}

int _seq = 0;

class _FakeSource implements NovelSource {
  _FakeSource({
    required this.chapterCount,
    this.failChapterIndexes = const <int>{},
    this.delayPerChapter = Duration.zero,
    this.failDetail = false,
    this.remapTitle,
  });

  final int chapterCount;
  Set<int> failChapterIndexes;
  final Duration delayPerChapter;

  /// fetchDetail 首次是否抛 NovelException（模拟书源切换后 URL 不兼容）
  final bool failDetail;

  /// 非 null 时 searchBooks 返回这个书名的结果，供重映射路径使用
  final String? remapTitle;

  final List<int> fetchedChapters = <int>[];
  int _detailCalls = 0;

  List<NovelChapter> get _chapters => List.generate(
        chapterCount,
        (i) => NovelChapter(title: '第${i + 1}章', url: 'http://x/c$i'),
      );

  @override
  Future<List<NovelBook>> searchBooks(String keyword, {int page = 1}) async {
    if (remapTitle == null) return <NovelBook>[];
    return [
      NovelBook(
        id: 'remapped',
        title: remapTitle!,
        author: '作者',
        intro: '简介',
        coverUrl: '',
        detailUrl: 'http://y/detail/1',
      ),
    ];
  }

  @override
  Future<List<NovelBook>> fetchByPath(String path) async => <NovelBook>[];

  @override
  Future<NovelDetail> fetchDetail({
    required String bookId,
    String? detailUrl,
  }) async {
    _detailCalls++;
    // 只让第一次（原始 detailUrl）失败，重映射后的第二次成功
    if (failDetail && _detailCalls == 1) {
      throw ParseException('detail url 不兼容');
    }
    return NovelDetail(
      book: NovelBook(
        id: bookId,
        title: '测试书名',
        author: '作者',
        intro: '简介',
        coverUrl: '',
        detailUrl: detailUrl ?? '',
      ),
      chapters: _chapters,
    );
  }

  @override
  Future<ChapterContent> fetchChapter({
    required NovelDetail detail,
    required int chapterIndex,
  }) async {
    if (delayPerChapter > Duration.zero) {
      await Future<void>.delayed(delayPerChapter);
    }
    if (failChapterIndexes.contains(chapterIndex)) {
      throw HttpException('章节下载失败');
    }
    fetchedChapters.add(chapterIndex);
    return ChapterContent(
      title: '第${chapterIndex + 1}章',
      content: '正文' * 200,
      chapterIndex: chapterIndex,
      sourceUrl: 'http://x/c$chapterIndex',
    );
  }
}
