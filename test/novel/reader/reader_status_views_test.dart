import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/novel/core/models.dart';
import 'package:box/novel/pages/reader/reader_status_views.dart';
import 'package:box/novel/pages/reader/reader_theme.dart';

/// 这些 widget 原本是 reader_page.dart 里的私有 `_buildXxx` 方法，
/// 想测就得先构造出整个 ReaderPage（需要网络、SharedPreferences、
/// ReaderController），实际上等于测不了。抽成独立 widget 后只要
/// pumpWidget 就行——本文件即阶段 1 拆分换来的回归网。

/// 把被测 widget 套进最小可渲染环境。
Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

void main() {
  group('ReaderPalette', () {
    test('三种主题各自返回不同的背景与前景色', () {
      const modes = ReaderThemeMode.values;
      final backgrounds = modes.map((m) => ReaderPalette.of(m).background).toSet();
      final texts = modes.map((m) => ReaderPalette.of(m).text).toSet();

      // 三套主题不能有任何两套撞色，否则用户切了主题看不出变化
      expect(backgrounds.length, modes.length);
      expect(texts.length, modes.length);
    });

    test('每种主题的前景与背景有足够亮度差', () {
      for (final mode in ReaderThemeMode.values) {
        final palette = ReaderPalette.of(mode);
        final delta = (palette.background.computeLuminance() -
                palette.text.computeLuminance())
            .abs();
        // 正文必须能读——亮度差过小说明配色表被改坏了
        expect(
          delta,
          greaterThan(0.3),
          reason: '$mode 的前景背景亮度差只有 $delta，正文会看不清',
        );
      }
    });

    test('dark 主题背景比 paper / warm 更暗', () {
      final dark = ReaderPalette.of(ReaderThemeMode.dark);
      final paper = ReaderPalette.of(ReaderThemeMode.paper);
      final warm = ReaderPalette.of(ReaderThemeMode.warm);

      expect(
        dark.background.computeLuminance(),
        lessThan(paper.background.computeLuminance()),
      );
      expect(
        dark.background.computeLuminance(),
        lessThan(warm.background.computeLuminance()),
      );
    });

    test('of 对同一 mode 返回稳定值（可用于 const 比较）', () {
      expect(
        ReaderPalette.of(ReaderThemeMode.dark),
        same(ReaderPalette.of(ReaderThemeMode.dark)),
      );
    });
  });

  group('ReaderTopProgressBar', () {
    // 这是最容易出「假完成」的地方：分母是章节总数，
    // 早期实现用 current/total 导致第 1 章就显示 0，最后一章显示不满。
    testWidgets('单章书不渲染进度条', (tester) async {
      await tester.pumpWidget(_host(
        const ReaderTopProgressBar(
          textColor: Colors.black,
          chapterIndex: 0,
          totalChapters: 1,
        ),
      ));

      expect(find.byType(FractionallySizedBox), findsNothing);
      expect(find.byType(SizedBox), findsWidgets); // 收成 shrink
    });

    testWidgets('总章数为 0 时也不崩（目录未加载）', (tester) async {
      await tester.pumpWidget(_host(
        const ReaderTopProgressBar(
          textColor: Colors.black,
          chapterIndex: 0,
          totalChapters: 0,
        ),
      ));

      expect(tester.takeException(), isNull);
      expect(find.byType(FractionallySizedBox), findsNothing);
    });

    testWidgets('第 1 章（index 0）宽度不为 0', (tester) async {
      await tester.pumpWidget(_host(
        const ReaderTopProgressBar(
          textColor: Colors.black,
          chapterIndex: 0,
          totalChapters: 10,
        ),
      ));

      final box = tester.widget<FractionallySizedBox>(
        find.byType(FractionallySizedBox),
      );
      // 用 (index+1)/total 而非 index/total：第一章要有可见进度
      expect(box.widthFactor, closeTo(0.1, 1e-9));
    });

    testWidgets('最后一章填满', (tester) async {
      await tester.pumpWidget(_host(
        const ReaderTopProgressBar(
          textColor: Colors.black,
          chapterIndex: 9,
          totalChapters: 10,
        ),
      ));

      final box = tester.widget<FractionallySizedBox>(
        find.byType(FractionallySizedBox),
      );
      expect(box.widthFactor, closeTo(1.0, 1e-9));
    });

    testWidgets('chapterIndex 越界时 clamp 到 1.0 而不是溢出', (tester) async {
      await tester.pumpWidget(_host(
        const ReaderTopProgressBar(
          textColor: Colors.black,
          chapterIndex: 99,
          totalChapters: 10,
        ),
      ));

      final box = tester.widget<FractionallySizedBox>(
        find.byType(FractionallySizedBox),
      );
      expect(box.widthFactor, 1.0);
      expect(tester.takeException(), isNull);
    });
  });

  group('ReaderErrorState', () {
    testWidgets('显示错误文案并能触发重试', (tester) async {
      var retried = 0;
      await tester.pumpWidget(_host(
        ReaderErrorState(
          textColor: Colors.black,
          message: '章节加载失败：超时',
          onRetry: () => retried++,
        ),
      ));

      expect(find.text('章节加载失败：超时'), findsOneWidget);

      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(retried, 1);
    });

    testWidgets('超长错误信息不溢出', (tester) async {
      await tester.pumpWidget(_host(
        ReaderErrorState(
          textColor: Colors.black,
          message: '解析失败：' * 80,
          onRetry: () {},
        ),
      ));

      expect(tester.takeException(), isNull);
    });
  });

  group('ReaderChapterTransitionOverlay', () {
    testWidgets('显示目标章标题与取消提示', (tester) async {
      await tester.pumpWidget(_host(
        ReaderChapterTransitionOverlay(
          bgColor: Colors.white,
          textColor: Colors.black,
          title: '第十二章 夜行',
          onCancel: () {},
        ),
      ));
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.text('第十二章 夜行'), findsOneWidget);
      expect(find.text('点击取消'), findsOneWidget);
    });

    testWidgets('点击遮罩触发 onCancel', (tester) async {
      var cancelled = 0;
      await tester.pumpWidget(_host(
        ReaderChapterTransitionOverlay(
          bgColor: Colors.white,
          textColor: Colors.black,
          title: '第十二章',
          onCancel: () => cancelled++,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 120));

      await tester.tap(find.text('点击取消'));
      await tester.pump();
      expect(cancelled, 1);
    });

    testWidgets('遮罩不做全遮挡（上限 0.55），底下正文仍可见', (tester) async {
      await tester.pumpWidget(_host(
        ReaderChapterTransitionOverlay(
          bgColor: Colors.white,
          textColor: Colors.black,
          title: '第十二章',
          onCancel: () {},
        ),
      ));
      // 显式 pump 过 220ms 取终态。不能用 pumpAndSettle：
      // 遮罩里的 CircularProgressIndicator 永久循环，永远不会 settle。
      await tester.pump(const Duration(milliseconds: 300));

      final opacity = tester.widget<Opacity>(find.byType(Opacity));
      expect(opacity.opacity, lessThanOrEqualTo(0.55));
    });

    testWidgets('超长章节标题截断为最多两行', (tester) async {
      await tester.pumpWidget(_host(
        ReaderChapterTransitionOverlay(
          bgColor: Colors.white,
          textColor: Colors.black,
          title: '第一章 ' * 60,
          onCancel: () {},
        ),
      ));
      await tester.pump(const Duration(milliseconds: 120));

      final text = tester.widget<Text>(find.textContaining('第一章').first);
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });
  });

  group('ReaderLoadingSkeleton / ReaderPaginatingBadge', () {
    testWidgets('骨架屏渲染标题占位 + 5 行文字占位 + spinner', (tester) async {
      await tester.pumpWidget(_host(
        const ReaderLoadingSkeleton(textColor: Colors.black),
      ));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // 1 个标题占位 + 5 行文字占位
      expect(find.byType(Container), findsNWidgets(6));
    });

    testWidgets('分页角标显示排版中文案', (tester) async {
      await tester.pumpWidget(_host(
        const ReaderPaginatingBadge(
          bgColor: Colors.white,
          textColor: Colors.black,
        ),
      ));

      expect(find.text('排版中…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('三套主题下骨架屏都能渲染', (tester) async {
      for (final mode in ReaderThemeMode.values) {
        await tester.pumpWidget(_host(
          ReaderLoadingSkeleton(textColor: ReaderPalette.of(mode).text),
        ));
        expect(tester.takeException(), isNull, reason: '$mode 下骨架屏渲染失败');
      }
    });
  });
}
