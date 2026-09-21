// 内容页漫画入口的可见性回归锁。
//
// 背景：用户报告「以前可以看漫画，现在漫画入口不见了」。这些测试锁住内容页
// 顶部「内容入口」宫格里漫画卡的存在，以及它点下去应该真的能进漫画功能。
library;

import 'package:box/design_system/app_tokens.dart';
import 'package:box/features/content/presentation/widgets/warehouse_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('内容入口宫格：漫画卡', () {
    testWidgets('漫画卡必须渲染在内容入口里', (tester) async {
      var comicTapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: AppTokens.background,
            body: SingleChildScrollView(
              child: ContentEntryGrid(
                onOpenVideoCenter: () {},
                onOpenNovelLibrary: () {},
                onOpenComics: () => comicTapped++,
                onOpenMusic: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('漫画'), findsOneWidget);

      await tester.tap(find.text('漫画'));
      await tester.pumpAndSettle();
      expect(comicTapped, 1);
    });

    testWidgets('副标题承诺的四类内容都要有对应入口', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ContentEntryGrid(
                onOpenVideoCenter: () {},
                onOpenNovelLibrary: () {},
                onOpenComics: () {},
                onOpenMusic: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 「内容入口」副标题写的是「影视 / 小说 / 漫画 / 音乐」，
      // 四类都必须能在宫格里找到落点，不能只是文案承诺。
      expect(find.text('影视'), findsOneWidget);
      // 六合四后「小说搜索」与「书架」合并为单个「小说」入口
      expect(find.text('小说'), findsOneWidget);
      expect(find.text('漫画'), findsOneWidget);
      expect(find.text('音乐'), findsOneWidget);
    });
  });
}
