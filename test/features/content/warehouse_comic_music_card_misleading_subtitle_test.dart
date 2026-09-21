// 红灯测试：漫画卡片「导入收藏」副标题会误导用户（说是导入，实际是手填表单）。
// 修完此问题：副标题改为「手动添加」或「本地导入/添加」，或加明确标签。
library;

import 'package:box/features/content/presentation/widgets/warehouse_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    '漫画卡副标题不应写「导入收藏」（误导：不是导入，是手填表单）',
    (tester) async {
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

      final subtitleFinder = find.byWidgetPredicate(
        (w) => w is Text && w.data == '导入收藏',
      );

      expect(
        subtitleFinder,
        findsNothing,
        reason: '「导入收藏」误导用户以为是导入功能，实际是手填表单；副标题应明确「手动添加」或「本地导入」',
      );
    },
  );

  testWidgets(
    '音乐卡副标题不应写「导入收藏」（同上误导）',
    (tester) async {
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

      final subtitleFinder = find.byWidgetPredicate(
        (w) => w is Text && w.data == '导入收藏',
      );

      expect(
        subtitleFinder,
        findsNothing,
        reason: '音乐卡同样误导',
      );
    },
  );
}
