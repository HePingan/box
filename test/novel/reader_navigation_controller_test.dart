import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/novel/core/models.dart';
import 'package:box/novel/pages/reader/reader_bookmark_service.dart';
import 'package:box/novel/pages/reader/reader_controller.dart';
import 'package:box/novel/pages/reader/reader_navigation_controller.dart';

/// 构造一个不依赖网络/DB 的最小 ReaderController
ReaderController _buildReaderController({int chapterCount = 3}) {
  final detail = NovelDetail(
    book: const NovelBook(
      id: 'test-book',
      title: '测试书',
      author: '作者',
      intro: '简介',
      coverUrl: '',
      detailUrl: 'https://example.invalid/book',
    ),
    chapters: List.generate(
      chapterCount,
      (i) => NovelChapter(title: '第 ${i + 1} 章', url: 'https://x.invalid/$i'),
    ),
  );

  return ReaderController(detail: detail, initialChapterIndex: 0);
}

ReaderNavigationController _buildNav(
  ReaderController reader, {
  List<String> pages = const ['p1', 'p2', 'p3'],
}) {
  return ReaderNavigationController(
    readerController: reader,
    pageController: PageController(initialPage: 1),
    scrollController: ScrollController(),
    getTextPages: () => pages,
    onResetPagedState: (_) {},
    scheduleScrollJump: () {},
  );
}

void main() {
  group('ReaderNavigationController 菜单状态', () {
    test('初始状态菜单关闭', () {
      final nav = _buildNav(_buildReaderController());
      expect(nav.menuVisible, isFalse);
    });

    test('toggleMenu 切换状态并通知监听者', () {
      final nav = _buildNav(_buildReaderController());
      var notified = 0;
      nav.addListener(() => notified++);

      nav.toggleMenu();
      expect(nav.menuVisible, isTrue);
      expect(notified, 1);

      nav.toggleMenu();
      expect(nav.menuVisible, isFalse);
      expect(notified, 2);
    });

    test('dismissMenu 在菜单已关闭时不产生多余通知', () {
      final nav = _buildNav(_buildReaderController());
      var notified = 0;
      nav.addListener(() => notified++);

      nav.dismissMenu();
      expect(nav.menuVisible, isFalse);
      expect(notified, 0, reason: '已关闭时应短路，避免无意义重建');

      nav.toggleMenu();
      nav.dismissMenu();
      expect(nav.menuVisible, isFalse);
      expect(notified, 2);
    });
  });

  group('菜单可见时点击正文应关闭菜单（回归）', () {
    testWidgets('handleScreenTap 在 menuVisible 时关闭菜单而不翻页', (tester) async {
      final reader = _buildReaderController();
      final nav = _buildNav(reader);
      nav.toggleMenu();
      expect(nav.menuVisible, isTrue);

      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.expand();
            },
          ),
        ),
      );

      // 点击屏幕右侧（分页模式下平时是"下一页"区域）
      await nav.handleScreenTap(
        TapUpDetails(
          kind: PointerDeviceKind.touch,
          globalPosition: const Offset(700, 400),
        ),
        ctx,
      );

      expect(
        nav.menuVisible,
        isFalse,
        reason: '菜单打开时的任意点击都应先关闭菜单',
      );
      expect(
        reader.chapterIndex,
        0,
        reason: '关闭菜单的点击不应同时触发翻页/切章',
      );
    });
  });

  group('进度保存不应触发重建（卡顿回归）', () {
    test('updateProgress 只写字段，不通知监听者', () {
      final reader = _buildReaderController();
      var notified = 0;
      reader.addListener(() => notified++);

      final progress = ReadingProgress(
        bookId: 'test-book',
        chapterIndex: 0,
        chapterTitle: '第 1 章',
        scrollOffset: 12.0,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      reader.updateProgress(progress);

      expect(reader.progress, same(progress), reason: '字段仍要被写入');
      expect(
        notified,
        0,
        reason: '高频落库若触发重建，会连带重建顶栏/底栏/PageView 造成滚动卡顿',
      );
    });

    test('连续高频保存不产生任何重建', () {
      final reader = _buildReaderController();
      var notified = 0;
      reader.addListener(() => notified++);

      for (var i = 0; i < 50; i++) {
        reader.updateProgress(
          ReadingProgress(
            bookId: 'test-book',
            chapterIndex: 0,
            chapterTitle: '第 1 章',
            scrollOffset: i.toDouble(),
            updatedAt: i,
          ),
        );
      }

      expect(notified, 0);
      expect(reader.progress?.scrollOffset, 49.0);
    });
  });

  group('合并重建信号', () {
    test('Listenable.merge 让菜单与内容变化都能触发重建', () {
      final reader = _buildReaderController();
      final nav = _buildNav(reader);
      final merged = Listenable.merge([reader, nav]);

      var rebuilds = 0;
      merged.addListener(() => rebuilds++);

      nav.toggleMenu();
      expect(rebuilds, 1, reason: '菜单变化必须能驱动重建');

      reader.initBookmarkService(const NoopReaderBookmarkService());
      expect(rebuilds, 2, reason: '内容侧变化同样要驱动重建');
    });
  });
}
