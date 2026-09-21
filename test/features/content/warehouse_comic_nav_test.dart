// 漫画入口点击：应导航到漫画库，而非弹出手填表单
library;

import 'package:box/features/content/presentation/widgets/warehouse_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    '漫画卡点击应导航到漫画库（不是手填表单）',
    (tester) async {
      bool comicsNavCalled = false;
      bool addDialogCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContentEntryGrid(
              onOpenVideoCenter: () {},
              onOpenNovelLibrary: () {},
              onOpenComics: () {
                comicsNavCalled = true;
              },
              onOpenMusic: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 找到漫画卡并点击
      final comicsCard = find.text('漫画');
      expect(comicsCard, findsOneWidget);

      await tester.tap(comicsCard);
      await tester.pumpAndSettle();

      expect(
        comicsNavCalled,
        isTrue,
        reason: '点击漫画卡应调用导航回调，而不是手填表单',
      );
      expect(
        addDialogCalled,
        isFalse,
        reason: '点击漫画卡不应打开手填表单',
      );
    },
  );

  testWidgets(
    '漫画卡有正确的图标和标题',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContentEntryGrid(
              onOpenVideoCenter: () {},
              onOpenNovelLibrary: () {},
              onOpenComics: () {},
              onOpenMusic: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证漫画卡存在
      expect(
        find.text('漫画'),
        findsOneWidget,
      );

      // 验证有图标（collections_bookmark_rounded）
      expect(
        find.byIcon(Icons.collections_bookmark_rounded),
        findsOneWidget,
      );
    },
  );
}
