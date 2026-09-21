// 漫画库页面（书架）行为回归锁。
//
// 锁住：
//   1. 空库时给出引导，而不是白屏
//   2. 书架卡片显示真实阅读进度角标（task 6 的「书架进度角标」）
//   3. 没有进度的书不显示角标（不能凭空造一个 0%）
//   4. 删除必须二次确认（长按直接删是数据丢失风险）
library;

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/comic/domain/comic_book.dart';
import 'package:box/features/comic/domain/comic_library_store.dart';
import 'package:box/features/comic/domain/comic_reader_state.dart';
import 'package:box/features/comic/presentation/comic_library_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ComicBook _book({
  required String id,
  required String title,
  int pageCount = 100,
}) {
  return ComicBook(
    id: id,
    title: title,
    sourceType: ComicSourceType.folder,
    folderPath: '/tmp/none/$id',
    pages: List.generate(pageCount, (i) => '/tmp/none/$id/$i.jpg'),
    pageCount: pageCount,
    createdAt: DateTime.now().millisecondsSinceEpoch,
  );
}

void main() {
  late ComicLibraryStore store;

  setUp(() {
    store = ComicLibraryStore(
      cacheStore: CacheStore.inMemory('comic_library_page_test'),
    );
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ComicLibraryPage(libraryStore: store)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('空库时给出导入引导', (tester) async {
    await pumpPage(tester);

    expect(find.text('还没有漫画'), findsOneWidget);
    expect(find.text('导入漫画'), findsOneWidget);
  });

  testWidgets('书架卡片显示真实阅读进度角标', (tester) async {
    await store.add(_book(id: 'b1', title: '有进度的书', pageCount: 100));
    await store.saveProgress(
      ComicReaderState(
        comicBookId: 'b1',
        currentPageIndex: 24, // 第 25 页 / 100 => 25%
        totalPages: 100,
        isScrollMode: false,
        lastReadAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    await pumpPage(tester);

    expect(find.text('有进度的书'), findsOneWidget);
    expect(
      find.text('25%'),
      findsOneWidget,
      reason: '书架必须展示真实进度，而不是只有一个「已读」眼睛图标',
    );
  });

  testWidgets('没有进度的书不显示进度角标', (tester) async {
    await store.add(_book(id: 'b2', title: '没读过的书'));

    await pumpPage(tester);

    expect(find.text('没读过的书'), findsOneWidget);
    expect(
      find.textContaining('%'),
      findsNothing,
      reason: '没读过就不该凭空造一个进度出来',
    );
  });

  testWidgets('删除漫画必须二次确认', (tester) async {
    await store.add(_book(id: 'b3', title: '待删除的书'));
    await pumpPage(tester);

    await tester.longPress(find.text('待删除的书'));
    await tester.pumpAndSettle();

    // 必须先弹确认框，且此时书还在
    expect(find.textContaining('删除'), findsWidgets);
    expect((await store.fetch()).length, 1, reason: '确认前不得真的删掉');

    // 取消 → 书仍在
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect((await store.fetch()).length, 1);

    // 再来一次，确认删除
    await tester.longPress(find.text('待删除的书'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pumpAndSettle();

    expect((await store.fetch()), isEmpty, reason: '确认后应真的删掉');
    expect(find.text('还没有漫画'), findsOneWidget);
  });
}
