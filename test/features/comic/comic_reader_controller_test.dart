// 漫画阅读器：翻页、长条模式、进度保存
//
// 注意：页数一律由 ComicBook.pages 真实推导，不通过测试专用 setter 伪造，
// 避免测试通过了、真实数据路径却没被覆盖。
library;

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/comic/domain/comic_book.dart';
import 'package:box/features/comic/domain/comic_library_store.dart';
import 'package:box/features/comic/domain/comic_reader_state.dart';
import 'package:box/features/comic/presentation/comic_reader_controller.dart';
import 'package:flutter_test/flutter_test.dart';

ComicBook _bookWithPages(int count, {String id = 'reader-test-1'}) {
  return ComicBook(
    id: id,
    title: '阅读器测试',
    coverPath: '/covers/test.jpg',
    sourceType: ComicSourceType.file,
    pages: List.generate(count, (i) => '/pages/$i.jpg'),
    pageCount: count,
    createdAt: DateTime.now().millisecondsSinceEpoch,
  );
}

void main() {
  late ComicLibraryStore testStore;

  ComicReaderController controllerFor(
    ComicBook book, {
    int initialPageIndex = 0,
  }) {
    return ComicReaderController(
      comicBook: book,
      initialPageIndex: initialPageIndex,
      libraryStore: testStore,
    );
  }

  setUp(() {
    testStore = ComicLibraryStore(
      cacheStore: CacheStore.inMemory('comic_reader_test'),
    );
  });

  test('ComicReaderController 初始化', () {
    final book = _bookWithPages(0);
    final controller = controllerFor(book);

    expect(controller.comicBook, book);
    expect(controller.currentPageIndex, 0);
    expect(controller.totalPages, 0); // 空列表时为 0
    expect(controller.isScrollMode, isFalse);
  });

  test('总页数由 ComicBook.pages 推导', () {
    final controller = controllerFor(_bookWithPages(10));
    expect(controller.totalPages, 10);
  });

  test('翻页：下一页', () {
    final controller = controllerFor(_bookWithPages(10));
    controller.goNext();
    expect(controller.currentPageIndex, 1);
  });

  test('翻页：上一页', () {
    final controller = controllerFor(_bookWithPages(10), initialPageIndex: 5);
    controller.goPrevious();
    expect(controller.currentPageIndex, 4);
  });

  test('翻页边界：不能翻到负数', () {
    final controller = controllerFor(_bookWithPages(10));
    controller.goPrevious();
    expect(controller.currentPageIndex, 0);
  });

  test('翻页边界：不能翻到超过总数', () {
    final controller = controllerFor(_bookWithPages(10), initialPageIndex: 9);
    controller.goNext();
    expect(controller.currentPageIndex, 9);
  });

  test('setPage 会被夹紧到合法范围', () {
    final controller = controllerFor(_bookWithPages(10));
    controller.setPage(99);
    expect(controller.currentPageIndex, 9);
    controller.setPage(-5);
    expect(controller.currentPageIndex, 0);
  });

  test('切换翻页/长条模式', () {
    final controller = controllerFor(_bookWithPages(3));
    expect(controller.isScrollMode, isFalse);
    controller.toggleScrollMode();
    expect(controller.isScrollMode, isTrue);
    controller.toggleScrollMode();
    expect(controller.isScrollMode, isFalse);
  });

  test('保存/恢复阅读进度', () async {
    final controller = controllerFor(
      _bookWithPages(20),
      initialPageIndex: 5,
    );
    await controller.saveProgress();

    final state = await controller.loadProgress();
    expect(state, isNotNull);
    expect(state!.currentPageIndex, 5);
    expect(state.totalPages, 20);
  });

  test('进度按漫画 id 隔离，不会串台', () async {
    final a = controllerFor(_bookWithPages(20, id: 'book-a'), initialPageIndex: 7);
    final b = controllerFor(_bookWithPages(20, id: 'book-b'), initialPageIndex: 2);
    await a.saveProgress();
    await b.saveProgress();

    expect((await a.loadProgress())!.currentPageIndex, 7);
    expect((await b.loadProgress())!.currentPageIndex, 2);
  });

  test('长条模式也会随进度一起持久化', () async {
    final controller = controllerFor(_bookWithPages(12), initialPageIndex: 3);
    controller.toggleScrollMode();
    await controller.saveProgress();

    final state = await controller.loadProgress();
    expect(state!.isScrollMode, isTrue);
  });

  test('ComicReaderState 可序列化', () {
    final state = ComicReaderState(
      comicBookId: 'test-1',
      currentPageIndex: 3,
      totalPages: 10,
      isScrollMode: false,
      lastReadAt: DateTime.now().millisecondsSinceEpoch,
    );

    final json = state.toJson();
    final restored = ComicReaderState.fromJson(json);

    expect(restored.comicBookId, state.comicBookId);
    expect(restored.currentPageIndex, state.currentPageIndex);
    expect(restored.totalPages, state.totalPages);
    expect(restored.isScrollMode, state.isScrollMode);
  });
}
