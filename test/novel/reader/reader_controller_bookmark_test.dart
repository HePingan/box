import 'package:box/novel/core/models.dart';
import 'package:box/novel/pages/reader/reader_bookmark_service.dart';
import 'package:box/novel/pages/reader/reader_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A1：ReaderController 书签乐观更新回归。
///
/// service 层持久化语义已由 bookmark_cache_invalidation_test 锁死（7/7 绿），
/// 所以这里专攻 controller 的三处连锁缺陷：
///   1. bookmarks getter 用 `_cachedBookmarks.isNotEmpty` 当缓存有效性判据
///      → 删掉最后一条后判定「缓存无效」回落读盘，书签复活
///   2. removeBookmark 的回滚判据 `existing.any(id)` 查的是删除前的旧列表，
///      那条必然还在 → stillExists 恒 true → 每次删除都误判失败并回滚
///   3. `existing` 与 `before` 是同一引用，回滚是空操作
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferencesReaderBookmarkService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service = SharedPreferencesReaderBookmarkService(
      await SharedPreferences.getInstance(),
    );
  });

  test('删除书签必须返回 true（回滚判据不能恒真）', () async {
    final c = _controller(service);
    await c.addBookmark();

    final id = c.bookmarks.single.id;
    final ok = await c.removeBookmark(id);

    expect(ok, isTrue, reason: 'existing.any(id) 查旧列表 → 恒真 → 永远返回 false');
  });

  test('删掉最后一条书签后列表必须为空，不得从磁盘复活', () async {
    final c = _controller(service);
    await c.addBookmark();
    expect(c.bookmarks, hasLength(1));

    await c.removeBookmark(c.bookmarks.single.id);

    expect(
      c.bookmarks,
      isEmpty,
      reason: '_cachedBookmarks 变空 → isNotEmpty 判定缓存无效 → 回落读盘 → 书签复活',
    );
  });

  test('删空后 hasBookmarkForCurrent 必须转 false（书签按钮状态）', () async {
    final c = _controller(service);
    await c.addBookmark();
    expect(c.hasBookmarkForCurrent, isTrue);

    await c.removeBookmark(c.bookmarks.single.id);

    expect(c.hasBookmarkForCurrent, isFalse, reason: '按钮还亮着 = 用户以为没删掉');
  });

  test('多条书签删其中一条，剩余数量正确', () async {
    final c = _controller(service);
    await c.addBookmark();
    c.chapterIndex = 1;
    await c.addBookmark();
    c.chapterIndex = 2;
    await c.addBookmark();
    expect(c.bookmarks, hasLength(3));

    final target = c.bookmarks[1].id;
    expect(await c.removeBookmark(target), isTrue);

    expect(c.bookmarks, hasLength(2));
    expect(c.bookmarks.any((b) => b.id == target), isFalse);
  });

  test('删除会持久化到磁盘（不只是内存缓存）', () async {
    final c = _controller(service);
    await c.addBookmark();
    final id = c.bookmarks.single.id;

    await c.removeBookmark(id);

    expect(service.loadForBook('b1'), isEmpty);
  });

  test('同章重复添加返回 false 且不产生第二条', () async {
    final c = _controller(service);
    expect(await c.addBookmark(), isTrue);
    expect(await c.addBookmark(), isFalse);
    expect(c.bookmarks, hasLength(1));
  });

  test('添加会通知监听者（UI 需要重建）', () async {
    final c = _controller(service);
    var notified = 0;
    c.addListener(() => notified++);

    await c.addBookmark();

    expect(notified, greaterThan(0));
  });

  test('删除会通知监听者', () async {
    final c = _controller(service);
    await c.addBookmark();

    var notified = 0;
    c.addListener(() => notified++);
    await c.removeBookmark(c.bookmarks.single.id);

    expect(notified, greaterThan(0));
  });

  test('initBookmarkService 必须让书签缓存失效', () async {
    // 复现启动时序：先 Noop（恒空），UI 读一次把缓存钉成空，再换真服务
    await service.add(
      ReaderBookmark(
        id: 'pre-existing',
        bookId: 'b1',
        chapterIndex: 0,
        chapterTitle: '第1章',
        createdAt: DateTime.now(),
      ),
    );

    final c = _controller(const NoopReaderBookmarkService());
    expect(c.bookmarks, isEmpty); // 这一读会写入缓存

    c.initBookmarkService(service);

    expect(
      c.bookmarks,
      hasLength(1),
      reason: '不清缓存 → 有书签的书打开阅读器却看不到书签',
    );
  });

  test('clearBookmarks 清空缓存与磁盘', () async {
    final c = _controller(service);
    await c.addBookmark();
    c.chapterIndex = 1;
    await c.addBookmark();
    expect(c.bookmarks, hasLength(2));

    await c.clearBookmarks();

    expect(c.bookmarks, isEmpty);
    expect(service.loadForBook('b1'), isEmpty);
  });

  test('clearBookmarks 后可重新添加', () async {
    final c = _controller(service);
    await c.addBookmark();
    await c.clearBookmarks();

    expect(await c.addBookmark(), isTrue);
  });

  test('清空后再添加能正常工作（缓存不残留脏数据）', () async {
    final c = _controller(service);
    await c.addBookmark();
    await c.removeBookmark(c.bookmarks.single.id);

    expect(await c.addBookmark(), isTrue, reason: '删空后应能重新加同一章');
    expect(c.bookmarks, hasLength(1));
  });
}

ReaderController _controller(ReaderBookmarkService service) {
  return ReaderController(
    detail: NovelDetail(
      book: const NovelBook(
        id: 'b1',
        title: '测试书',
        author: '作者',
        intro: '',
        coverUrl: '',
        detailUrl: '',
      ),
      chapters: List.generate(
        5,
        (i) => NovelChapter(title: '第${i + 1}章', url: 'http://x/c$i'),
      ),
    ),
    initialChapterIndex: 0,
    bookmarkService: service,
  );
}
