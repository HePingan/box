import 'package:box/novel/pages/reader/reader_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 顶栏布局契约。
///
/// 截图暴露的问题：正文（章节标题那行）从顶栏背后透出来，看着像水印重影。
/// 根因不是「顶栏透明」——它有 0.92 的底色——而是：
///   1. 底色 alpha 0.92 在浅色主题下压不住底下的深色文字；
///   2. 顶栏只在 margin 外圈留白，圆角卡片之外那圈仍然直接露出正文。
///
/// 这里锁死的是「顶栏必须遮住底下内容」这个可测的结构契约，
/// 以及右侧图标间距、标题不贴边这些排版约束。
void main() {
  Widget host(
    Widget child, {
    EdgeInsets viewPadding = const EdgeInsets.only(top: 44),
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(padding: viewPadding),
        child: Stack(
          children: [
            // 模拟底下的正文：顶栏必须把它遮住
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Text('第三节：请一边玩蛋去'),
            ),
            Positioned(top: 0, left: 0, right: 0, child: child),
          ],
        ),
      ),
    );
  }

  ReaderTopBar bar({
    String title = '蛊真人',
    String chapter = '第三节：请一边玩蛋去',
    bool bookmarked = false,
  }) {
    return ReaderTopBar(
      bookTitle: title,
      chapterTitle: chapter,
      hasBookmark: bookmarked,
      bgColor: const Color(0xFFDDEBD2),
      textColor: const Color(0xFF161F1A),
      onBack: () {},
    );
  }

  group('遮挡契约', () {
    testWidgets('底色不透明，不让正文透出来', (tester) async {
      await tester.pumpWidget(host(bar()));

      final decorated = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ReaderTopBar),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = decorated.decoration! as BoxDecoration;

      expect(
        decoration.color!.a,
        1.0,
        reason: '半透明底色压不住底下的深色正文，就是截图里那圈重影',
      );
    });

    testWidgets('顶栏横向铺满，不在两侧漏出正文', (tester) async {
      await tester.pumpWidget(host(bar()));

      final barBox = tester.getRect(find.byType(ReaderTopBar));
      final screen = tester.getRect(find.byType(MaterialApp));

      expect(barBox.left, 0, reason: '左侧留白会漏出底下的正文');
      expect(barBox.right, screen.right, reason: '右侧留白会漏出底下的正文');
    });

    testWidgets('顶栏高度覆盖状态栏安全区', (tester) async {
      await tester.pumpWidget(host(bar()));

      final barBox = tester.getRect(find.byType(ReaderTopBar));
      expect(
        barBox.height,
        greaterThan(44),
        reason: '必须把 viewPadding.top 算进高度，否则内容顶到状态栏里',
      );
    });

    testWidgets('刘海高度变化时跟着变，不写死', (tester) async {
      await tester.pumpWidget(host(bar()));
      final short = tester.getRect(find.byType(ReaderTopBar)).height;

      await tester.pumpWidget(
        host(bar(), viewPadding: const EdgeInsets.only(top: 88)),
      );
      final tall = tester.getRect(find.byType(ReaderTopBar)).height;

      expect(tall - short, 44, reason: '高度必须随安全区线性增长');
    });
  });

  group('排版', () {
    testWidgets('显示书名，并把章节名作为副标题', (tester) async {
      await tester.pumpWidget(host(bar()));

      expect(find.text('蛊真人'), findsOneWidget);
      expect(
        find.text('第三节：请一边玩蛋去'),
        findsNWidgets(2),
        reason: '一个是底下模拟的正文，一个是顶栏副标题',
      );
    });

    testWidgets('章节名为空时不占位，只显示书名', (tester) async {
      await tester.pumpWidget(host(bar(chapter: '')));

      expect(find.text('蛊真人'), findsOneWidget);
      // 副标题不该渲染成空行撑高顶栏
      final texts = tester.widgetList<Text>(
        find.descendant(
          of: find.byType(ReaderTopBar),
          matching: find.byType(Text),
        ),
      );
      expect(texts.length, 1, reason: '空章节名应整体省略，而不是渲染空 Text');
    });

    testWidgets('超长书名截断，不把图标挤出屏幕', (tester) async {
      await tester.pumpWidget(
        host(bar(title: '书名' * 60, chapter: '章节名' * 60)),
      );

      expect(tester.takeException(), isNull);
      // 三个按钮都还在屏幕内
      for (final icon in [
        Icons.arrow_back_ios_new_rounded,
        Icons.menu_book_rounded,
        Icons.bookmark_border_rounded,
      ]) {
        final r = tester.getRect(find.byIcon(icon));
        expect(r.right, lessThanOrEqualTo(800), reason: '$icon 被挤出屏幕');
      }
    });

    testWidgets('标题不与返回箭头重叠', (tester) async {
      await tester.pumpWidget(host(bar()));

      final back = tester.getRect(find.byIcon(Icons.arrow_back_ios_new_rounded));
      final title = tester.getRect(find.text('蛊真人'));

      expect(title.left, greaterThanOrEqualTo(back.right), reason: '标题压到返回箭头上了');
    });

    testWidgets('右侧两个图标间距均匀', (tester) async {
      await tester.pumpWidget(host(bar()));

      final dict = tester.getRect(find.byIcon(Icons.menu_book_rounded));
      final mark = tester.getRect(find.byIcon(Icons.bookmark_border_rounded));
      final screen = tester.getRect(find.byType(MaterialApp));

      final between = mark.left - dict.right;
      final edge = screen.right - mark.right;

      expect(
        (between - edge).abs(),
        lessThan(12),
        reason: '图标间距与右边距差太多，视觉重心会偏散（截图里的问题）',
      );
    });
  });

  group('书签态', () {
    testWidgets('已加书签显示实心图标', (tester) async {
      await tester.pumpWidget(host(bar(bookmarked: true)));

      expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_border_rounded), findsNothing);
    });

    testWidgets('未加书签显示描边图标', (tester) async {
      await tester.pumpWidget(host(bar()));

      expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_rounded), findsNothing);
    });
  });

  group('回调', () {
    testWidgets('三个按钮分别触发各自回调', (tester) async {
      var back = 0, dict = 0, mark = 0;
      await tester.pumpWidget(
        host(
          ReaderTopBar(
            bookTitle: '蛊真人',
            chapterTitle: '第三节',
            hasBookmark: false,
            bgColor: const Color(0xFFDDEBD2),
            textColor: const Color(0xFF161F1A),
            onBack: () => back++,
            onDictionary: () => dict++,
            onBookmark: () => mark++,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.tap(find.byIcon(Icons.menu_book_rounded));
      await tester.tap(find.byIcon(Icons.bookmark_border_rounded));
      await tester.pump();

      expect([back, dict, mark], [1, 1, 1]);
    });

    testWidgets('回调为 null 时点击不抛异常', (tester) async {
      await tester.pumpWidget(
        host(
          ReaderTopBar(
            bookTitle: '蛊真人',
            chapterTitle: '第三节',
            hasBookmark: false,
            bgColor: const Color(0xFFDDEBD2),
            textColor: const Color(0xFF161F1A),
            onBack: () {},
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.menu_book_rounded));
      await tester.tap(find.byIcon(Icons.bookmark_border_rounded));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('主题', () {
    testWidgets('深色主题下底色仍不透明', (tester) async {
      await tester.pumpWidget(
        host(
          ReaderTopBar(
            bookTitle: '蛊真人',
            chapterTitle: '第三节',
            hasBookmark: false,
            bgColor: const Color(0xFF1E2028),
            textColor: const Color(0xFFD0C8B8),
            onBack: () {},
          ),
        ),
      );

      final decorated = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ReaderTopBar),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((decorated.decoration! as BoxDecoration).color!.a, 1.0);
    });
  });
}
