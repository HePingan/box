// 漫画阅读器页面行为回归锁。
//
// 锁住三条真实用户可感知的契约：
//   1. 点击页面不能直接退出阅读器（原实现 onTap 直接 Navigator.pop）
//   2. 有已保存进度时，打开阅读器 PageView 必须真的停在那一页（原实现只改了
//      controller 的 index，PageView 不跟着跳，续读形同失效）
//   3. 翻页只由 PageView 处理一次，不能出现「滑一下跳两页」
library;

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/comic/domain/comic_book.dart';
import 'package:box/features/comic/domain/comic_library_store.dart';
import 'package:box/features/comic/domain/comic_reader_state.dart';
import 'package:box/features/comic/presentation/comic_reader_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ComicBook _book({int pageCount = 10}) {
  return ComicBook(
    id: 'reader-page-test',
    title: '阅读器页面测试',
    coverPath: '/tmp/nonexistent-cover.jpg',
    sourceType: ComicSourceType.folder,
    folderPath: '/tmp/nonexistent',
    pages: List.generate(pageCount, (i) => '/tmp/nonexistent/$i.jpg'),
    pageCount: pageCount,
    createdAt: 0,
  );
}

void main() {
  late ComicLibraryStore store;

  setUp(() {
    store = ComicLibraryStore(
      cacheStore: CacheStore.inMemory('comic_reader_page_test'),
    );
  });

  testWidgets('点击页面不应退出阅读器', (tester) async {
    final book = _book();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ComicReaderPage(
                      comicBook: book,
                      libraryStore: store,
                    ),
                  ),
                ),
                child: const Text('打开阅读器'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开阅读器'));
    await tester.pumpAndSettle();

    expect(find.byType(ComicReaderPage), findsOneWidget);

    // 点一下漫画页面区域
    await tester.tap(find.byType(PageView));
    await tester.pumpAndSettle();

    expect(
      find.byType(ComicReaderPage),
      findsOneWidget,
      reason: '点击页面只应切换沉浸态，不能把用户踢出阅读器',
    );
  });

  testWidgets('有已保存进度时 PageView 必须真的停在那一页', (tester) async {
    final book = _book(pageCount: 10);

    // 预置进度：停在第 5 页（index 4）
    await store.saveProgress(
      ComicReaderState(
        comicBookId: book.id,
        currentPageIndex: 4,
        totalPages: 10,
        isScrollMode: false,
        lastReadAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ComicReaderPage(comicBook: book, libraryStore: store),
      ),
    );
    await tester.pumpAndSettle();

    final pageView = tester.widget<PageView>(find.byType(PageView));
    expect(
      pageView.controller?.page?.round(),
      4,
      reason: '续读要真的生效：PageController 必须跳到已保存的那一页',
    );

    // 底部页码也要一致
    expect(find.text('5 / 10'), findsWidgets);
  });

  testWidgets('滑动一次只翻一页（不得双重翻页）', (tester) async {
    final book = _book(pageCount: 10);

    await tester.pumpWidget(
      MaterialApp(
        home: ComicReaderPage(comicBook: book, libraryStore: store),
      ),
    );
    await tester.pumpAndSettle();

    // 向左滑一次
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    final pageView = tester.widget<PageView>(find.byType(PageView));
    expect(
      pageView.controller?.page?.round(),
      1,
      reason: '一次滑动只应前进一页；若 PageView 与手势回调各翻一次会变成 2',
    );
  });
}
