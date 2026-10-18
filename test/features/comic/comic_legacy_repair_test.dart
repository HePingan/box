// 旧漫画「页图丢失」提示条 + 书架接线回归锁。
//
// 锁住的是**呈现层的判断口径**（判定逻辑由 domain 侧注入，本文件只测"给什么书显示什么"）：
//   1. 没有坏书 → 完全不占位（不许为了一个"可能有用"的提示条挤掉书架空间）
//   2. 有坏书 → 说清楚"几本 / 为什么 / 能怎么办"，且是**提示条**不是弹窗（不拦操作）
//   3. 文案必须诚实：重新导入会新增一本，不假装能自动替换旧的
//   4. 「暂不处理」只关本次运行；没有关闭回调时**不画**这个按钮（按了不响比不画更糟）
//   5. 书架页把判定结果交给提示条；关掉后不再出现，重算后清零就自动消失
library;

import 'dart:io';

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/comic/domain/comic_book.dart';
import 'package:box/features/comic/domain/comic_image_cache.dart';
import 'package:box/features/comic/domain/comic_library_store.dart';
import 'package:box/features/comic/domain/comic_online_progress.dart';
import 'package:box/features/comic/domain/comic_page_health.dart';
import 'package:box/features/comic/presentation/comic_legacy_repair_banner.dart';
import 'package:box/features/comic/presentation/comic_library_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ComicBook _book({
  required String id,
  required String title,
  ComicSourceType sourceType = ComicSourceType.file,
  int pageCount = 30,
}) {
  return ComicBook(
    id: id,
    title: title,
    sourceType: sourceType,
    filePath: '/tmp/none/$id.cbz',
    pages: List.generate(pageCount, (i) => '/tmp/none/$id/$i.jpg'),
    pageCount: pageCount,
    createdAt: DateTime.now().millisecondsSinceEpoch,
  );
}

/// 只包一层可滚动的壳，让提示条在最朴素的宿主里也不会因为无界高度报错。
Future<void> _pumpBanner(
  WidgetTester tester, {
  required List<ComicBook> affected,
  VoidCallback? onReimport,
  Future<void> Function()? onDismiss,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            ComicLegacyRepairBanner(
              affectedBooks: affected,
              onReimportRequested: onReimport ?? () {},
              onDismiss: onDismiss,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('提示条', () {
    testWidgets('没有坏书时不占位（零高度、不出任何字）', (tester) async {
      await _pumpBanner(tester, affected: const <ComicBook>[]);

      // 组件本身还在树里（它是无状态的"给什么画什么"），但渲染出来是个零尺寸的
      // SizedBox —— 默认 finder 会把它当 offstage 跳过，所以这里显式包含 offstage。
      expect(
        find.byType(ComicLegacyRepairBanner, skipOffstage: false),
        findsOneWidget,
      );
      final box = tester.getSize(find.byType(ComicLegacyRepairBanner, skipOffstage: false));
      expect(box.height, 0, reason: '没有坏书就不该占位：白提醒一次也是提醒');
      expect(
        find.textContaining('图片丢了', skipOffstage: false),
        findsNothing,
      );
      expect(find.text('重新导入', skipOffstage: false), findsNothing);
    });

    testWidgets('有坏书时说明本数与原因，并且不是弹窗', (tester) async {
      await _pumpBanner(
        tester,
        affected: [
          _book(id: 'a', title: '旧书甲'),
          _book(id: 'b', title: '旧书乙'),
        ],
      );

      expect(find.text('有 2 本旧漫画的图片丢了'), findsOneWidget);
      // 说清楚"为什么"：临时目录被系统清理。不给原因的提示等于让用户猜。
      expect(find.textContaining('临时目录'), findsOneWidget);
      expect(find.textContaining('白页'), findsOneWidget);

      // 点名是哪几本：只说"有 2 本坏了"，用户还得自己一本本点开试。
      expect(find.textContaining('《旧书甲》'), findsOneWidget);
      expect(find.textContaining('《旧书乙》'), findsOneWidget);

      // 提示条不是弹窗：页面上不该出现 AlertDialog / Dialog 这种打断式容器。
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('文案写明"会新增一本"，不假装自动替换', (tester) async {
      await _pumpBanner(tester, affected: [_book(id: 'a', title: '旧书甲')]);

      expect(
        find.textContaining('重新导入后会多出一本'),
        findsOneWidget,
        reason: '对不上旧书就要如实说会多一本，不能暗示"点了就修好了"',
      );
    });

    testWidgets('点「重新导入」把请求交给页面（本组件不自己导）', (tester) async {
      var taps = 0;
      await _pumpBanner(
        tester,
        affected: [_book(id: 'a', title: '旧书甲')],
        onReimport: () => taps++,
      );

      await tester.tap(find.text('重新导入'));
      await tester.pumpAndSettle();

      expect(taps, 1);
    });

    testWidgets('「暂不处理」触发注入的关闭回调', (tester) async {
      var dismissed = 0;
      await _pumpBanner(
        tester,
        affected: [_book(id: 'a', title: '旧书甲')],
        onDismiss: () async => dismissed++,
      );

      await tester.tap(find.text('暂不处理'));
      await tester.pumpAndSettle();

      expect(dismissed, 1, reason: '关闭决定要交出去落盘，不能只在本组件里消失');
    });

    testWidgets('没有关闭回调就不画「暂不处理」（按了不响比不画更糟）', (tester) async {
      await _pumpBanner(tester, affected: [_book(id: 'a', title: '旧书甲')]);

      expect(find.text('暂不处理'), findsNothing);
      expect(find.text('重新导入'), findsOneWidget, reason: '没有关闭的路也不该把修复的路一起藏掉');
    });
  });

  testWidgets('窄屏 / 矮屏上提示条不溢出（正文会折行，按钮会换行）', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpBanner(
      tester,
      affected: [
        _book(id: 'a', title: '旧书甲'),
        _book(id: 'b', title: '旧书乙'),
        _book(id: 'c', title: '旧书丙'),
      ],
      onDismiss: () async {},
    );

    expect(tester.takeException(), isNull);
    expect(find.text('有 3 本旧漫画的图片丢了'), findsOneWidget);
  });

  testWidgets('坏书很多时只点前三本，其余用"等 N 本"收尾', (tester) async {
    await _pumpBanner(
      tester,
      affected: [
        for (var i = 1; i <= 5; i++) _book(id: 'b$i', title: '旧书$i'),
      ],
      onDismiss: () async {},
    );

    expect(find.textContaining('《旧书1》《旧书2》《旧书3》'), findsOneWidget);
    // 第四本以后不再逐个列：提示条不该被书名撑满
    expect(find.textContaining('《旧书4》'), findsNothing);
    expect(find.textContaining('等 5 本'), findsOneWidget);
  });

  group('书架接线', () {
    late ComicLibraryStore store;

    setUp(() {
      store = ComicLibraryStore(
        cacheStore: CacheStore.inMemory('comic_legacy_repair_test'),
      );
    });

    late ComicPageHealthNoticeStore noticeStore;

    setUp(() {
      noticeStore = ComicPageHealthNoticeStore(
        cacheStore: CacheStore.inMemory('comic_legacy_repair_notice'),
      );
    });

    Future<void> pumpPage(
      WidgetTester tester, {
      Future<List<ComicBook>> Function(List<ComicBook>)? probe,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ComicLibraryPage(
            libraryStore: store,
            pageHealthNoticeStore: noticeStore,
            // 在线进度与封面都注入内存/假实现：真实现要走 path_provider，
            // widget 测试里没人应答平台调用。
            onlineProgressStore: ComicOnlineProgressStore(
              cacheStore: CacheStore.inMemory('comic_legacy_repair_progress'),
            ),
            coverCache: _FakeCoverCache(),
            missingPagesProbe: probe,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('判定给出坏书 → 书架顶部出现提示条（书照常可点）', (tester) async {
      await store.add(_book(id: 'legacy', title: '丢图的书'));

      await pumpPage(
        tester,
        probe: (books) async => books.where((b) => b.id == 'legacy').toList(),
      );

      expect(find.text('有 1 本旧漫画的图片丢了'), findsOneWidget);
      // 提示条不该把书架挤掉：书还在
      expect(find.text('丢图的书'), findsOneWidget);
    });

    testWidgets('判定为空 → 不打扰（正常书架不出现修复提示）', (tester) async {
      await store.add(_book(id: 'ok', title: '好好的书'));

      await pumpPage(
        tester,
        probe: (books) async => const <ComicBook>[],
      );

      expect(find.text('好好的书'), findsOneWidget);
      expect(find.textContaining('图片丢了'), findsNothing);
    });

    testWidgets('未接判定（生产默认）→ 不显示，也不报错', (tester) async {
      await store.add(_book(id: 'ok', title: '好好的书'));

      await pumpPage(tester);

      expect(find.text('好好的书'), findsOneWidget);
      expect(find.textContaining('图片丢了'), findsNothing);
    });

    testWidgets('点「暂不处理」后提示条消失，书架还在', (tester) async {
      await store.add(_book(id: 'legacy', title: '丢图的书'));

      await pumpPage(
        tester,
        probe: (books) async => books.where((b) => b.id == 'legacy').toList(),
      );
      expect(find.text('有 1 本旧漫画的图片丢了'), findsOneWidget);

      await tester.tap(find.text('暂不处理'));
      await tester.pumpAndSettle();

      expect(find.textContaining('图片丢了'), findsNothing);
      expect(find.text('丢图的书'), findsOneWidget, reason: '关的是提示，不是书');
    });

    testWidgets('「重新导入」走既有的导入对话框，而不是自己再发明一条路', (tester) async {
      await store.add(_book(id: 'legacy', title: '丢图的书'));

      await pumpPage(
        tester,
        probe: (books) async => books.where((b) => b.id == 'legacy').toList(),
      );

      await tester.tap(find.text('重新导入'));
      await tester.pumpAndSettle();

      // 走进既有流程：同一个「选择导入方式」对话框（CBZ/ZIP 或文件夹）
      expect(find.text('选择导入方式'), findsOneWidget);
      expect(find.text('CBZ/ZIP 文件'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      // 取消后提示条仍在：没修好就不该自己消失
      expect(find.text('有 1 本旧漫画的图片丢了'), findsOneWidget);
    });
  });

  // ── 集成后的接线：判定结果 → 提示条，且「已提示过」真的会抑制 ──
  //
  // 上面那组只验证"给什么书就显示什么"。这里锁集成后新增的两件事：
  //   ① 页图丢失的结论来自 `_loadBooksWithMissingPages()`（判定可注入，生产走
  //      domain 的 ComicPageHealthChecker）；
  //   ② 用户点过「暂不处理」之后，**重建整个页面**也不再提示 —— 靠
  //      ComicPageHealthNoticeStore 落盘，而不是一个进程内 bool。
  //
  // 为什么用注入的 probe 而不是真实 `File.exists()`：`testWidgets` 跑在假时钟里，
  // 真实文件 IO 的 Future 永远不会完成（实测会挂到 10 分钟超时）。真实 IO 只在
  // 真机上验证；domain 判定本身在 comic_page_health_test.dart 里用注入探针覆盖了。
  group('书架接线（判定 + 已提示持久化）', () {
    late ComicLibraryStore store;
    late ComicPageHealthNoticeStore noticeStore;

    setUp(() {
      store = ComicLibraryStore(
        cacheStore: CacheStore.inMemory('comic_legacy_real_store'),
      );
      noticeStore = ComicPageHealthNoticeStore(
        cacheStore: CacheStore.inMemory('comic_legacy_real_notice'),
      );
    });

    Future<void> pump(
      WidgetTester tester, {
      required Future<List<ComicBook>> Function(List<ComicBook>)? probe,
      String progressNs = 'comic_legacy_real_progress',
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ComicLibraryPage(
            libraryStore: store,
            onlineProgressStore: ComicOnlineProgressStore(
              cacheStore: CacheStore.inMemory(progressNs),
            ),
            coverCache: _FakeCoverCache(),
            pageHealthNoticeStore: noticeStore,
            missingPagesProbe: probe,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('判定给出坏书 → 顶部提示条出现，书照常可读', (tester) async {
      await store.add(_book(id: 'legacy', title: '丢图的书'));

      await pump(
        tester,
        probe: (books) async => books.where((b) => b.id == 'legacy').toList(),
      );

      expect(find.text('有 1 本旧漫画的图片丢了'), findsOneWidget);
      expect(find.text('丢图的书'), findsOneWidget, reason: '提示条不该把书架挤掉');
    });

    testWidgets('点过「暂不处理」后整页重建也不再提示（跨进程记忆）', (tester) async {
      await store.add(_book(id: 'legacy', title: '丢图的书'));

      Future<List<ComicBook>> badProbe(List<ComicBook> books) async =>
          books.where((b) => b.id == 'legacy').toList();

      await pump(tester, probe: badProbe);
      expect(find.text('有 1 本旧漫画的图片丢了'), findsOneWidget);

      await tester.tap(find.text('暂不处理'));
      await tester.pumpAndSettle();
      expect(find.textContaining('图片丢了'), findsNothing);

      // 模拟"下次进书架"：整棵树拆掉重建。如果只用了进程内 bool，这里会重新冒出来。
      await tester.pumpWidget(const SizedBox());
      await pump(
        tester,
        probe: badProbe,
        progressNs: 'comic_legacy_real_progress_b',
      );

      expect(
        find.textContaining('图片丢了'),
        findsNothing,
        reason: '已经告诉过用户的书不该每次进书架都再弹一次',
      );
      expect(find.text('丢图的书'), findsOneWidget, reason: '书本身还在书架上');
    });

    testWidgets('判定为空 → 不打扰，也不往存储里写任何东西', (tester) async {
      await store.add(_book(id: 'ok', title: '好好的书'));

      await pump(tester, probe: (books) async => const <ComicBook>[]);

      expect(find.text('好好的书'), findsOneWidget);
      expect(find.textContaining('图片丢了'), findsNothing);
      expect(await noticeStore.notifiedIds(), isEmpty);
    });

    testWidgets('坏书被删掉后提示条自动消失（不会留一条指向空书的提示）', (tester) async {
      await store.add(_book(id: 'legacy', title: '丢图的书'));

      await pump(
        tester,
        probe: (books) async => books.where((b) => b.id == 'legacy').toList(),
      );
      expect(find.text('有 1 本旧漫画的图片丢了'), findsOneWidget);

      // 书没了，判定自然也就给不出坏书。
      await store.remove('legacy');
      // 先拆树再重建：同一个 widget 类型原地更新会复用 State，
      // initState 不会重跑，测不到"重新算一遍"这条路径。
      await tester.pumpWidget(const SizedBox());
      await pump(
        tester,
        probe: (books) async => const <ComicBook>[],
        progressNs: 'comic_legacy_real_progress_c',
      );

      expect(find.textContaining('图片丢了'), findsNothing);
    });
  });
}

/// 假封面缓存：本组用不到封面（本地书走 Image.file），给一份不联网的实现即可。
class _FakeCoverCache extends ComicImageCache {
  @override
  Future<File> fetch(
    String url, {
    bool lowPriority = false,
    File? dest,
    int? maxAttempts,
  }) async {
    throw ComicImageException('测试环境不联网');
  }

  @override
  Future<File?> cachedFile(String url) async => null;
}