// 章节目录列表：几百话的书要能**快速翻到某一话**（快速滑动 / 跳话 / 正序倒序）。
//
// 起因（2026-10-02 用户）：目录只能一行行划，且固定从第 1 话往下排。
library;

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/comic/domain/comic_online_service.dart';
import 'package:box/features/comic/domain/comic_reader_prefs.dart';
import 'package:box/features/comic/presentation/comic_chapter_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<ComicChapterRef> chapters(int n) => [
  for (var i = 1; i <= n; i++)
    ComicChapterRef(title: '话$i', url: 'https://yemancomic.com/book/96/$i.html'),
];

Future<void> pumpList(
  WidgetTester tester, {
  required ComicReaderPrefs prefs,
  String? currentUrl,
  void Function(ComicChapterRef)? onPick,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 400,
          child: ComicChapterList(
            chapters: chapters(300),
            currentUrl: currentUrl,
            prefs: prefs,
            onPick: onPick,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late CacheStore store;
  late ComicReaderPrefs prefs;

  setUp(() {
    store = CacheStore.inMemory('chapter_list');
    prefs = ComicReaderPrefs(cacheStore: store);
  });

  testWidgets('默认正序：第一行是第 1 话，行首是真实话数', (tester) async {
    await pumpList(tester, prefs: prefs);

    expect(find.text('话1'), findsOneWidget);
    expect(find.text('话300'), findsNothing, reason: '300 话的书，第一屏不会有最后一话');
    // 行首编号：第 1 话 → "1"
    expect(find.descendant(of: find.byType(ListTile).first, matching: find.text('1')),
        findsOneWidget);
  });

  testWidgets('点「倒序」：最新的排最上面，行首仍是真实话数（不是行号）', (tester) async {
    await pumpList(tester, prefs: prefs);

    await tester.tap(find.text('正序'));
    await tester.pumpAndSettle();

    expect(find.text('倒序'), findsOneWidget, reason: '按钮状态要跟着变');
    expect(find.text('话300'), findsOneWidget);
    expect(find.text('话1'), findsNothing);
    expect(
      find.descendant(of: find.byType(ListTile).first, matching: find.text('300')),
      findsOneWidget,
      reason: '倒序时第一行的编号必须是 300，显示行号 1 就骗人了',
    );
    expect(await prefs.chapterDescending(), isTrue, reason: '选择要记在本机');
  });

  testWidgets('记住选择：下次打开就是倒序', (tester) async {
    await prefs.setChapterDescending(true);
    await pumpList(tester, prefs: prefs);

    expect(find.text('话300'), findsOneWidget);
    expect(find.text('倒序'), findsOneWidget);
  });

  testWidgets('打开就滚到「正在读」那一话（300 话里第 180 话不在首屏）', (tester) async {
    final url180 = chapters(300)[179].url;
    await pumpList(tester, prefs: prefs, currentUrl: url180);

    expect(find.text('话180'), findsOneWidget, reason: '打开目录就该停在正在读的那一话');
    expect(find.text('正在读'), findsOneWidget);
  });

  testWidgets('倒序下也滚到「正在读」那一话', (tester) async {
    await prefs.setChapterDescending(true);
    final url180 = chapters(300)[179].url;
    await pumpList(tester, prefs: prefs, currentUrl: url180);

    expect(find.text('话180'), findsOneWidget);
  });

  testWidgets('快速滑动：滚动条是可拖动的（几百话全靠它）', (tester) async {
    await pumpList(tester, prefs: prefs);

    final bar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(bar.interactive, isTrue, reason: '不可拖就只能一行行划');
    expect(bar.thumbVisibility, isTrue, reason: '拇指要一直看得见，否则不知道能拖');
  });

  testWidgets('跳话：输 250 直接滚到第 250 话', (tester) async {
    await pumpList(tester, prefs: prefs);

    await tester.tap(find.text('跳话'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '250');
    await tester.tap(find.text('跳过去'));
    await tester.pumpAndSettle();

    expect(find.text('话250'), findsOneWidget);
  });

  testWidgets('跳话：一键到「最新一话」', (tester) async {
    await pumpList(tester, prefs: prefs);

    await tester.tap(find.text('跳话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('最新一话'));
    await tester.pumpAndSettle();

    expect(find.text('话300'), findsOneWidget);
  });

  testWidgets('点某一话就把这一话交给调用方（阅读器里=跳过去）', (tester) async {
    ComicChapterRef? picked;
    await pumpList(tester, prefs: prefs, onPick: (c) => picked = c);

    await tester.tap(find.text('话3'));
    await tester.pumpAndSettle();

    expect(picked?.title, '话3');
  });

  testWidgets('已下载的那一话有标记', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: ComicChapterList(
              chapters: chapters(300),
              downloaded: {chapters(300)[1].url},
              prefs: prefs,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已下载'), findsOneWidget);
  });
}
