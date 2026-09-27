// 漫画源自检页的界面用例（假取数，不联网、不起 WebView）。
//
// 守三条底线：
//   ① 三步都要逐条显示，失败项必须写出原因（不能只给一个红叉）；
//   ② 全通过时要有明确结论，并且「复制结论」拿得到完整报告（用户要贴回来当证据）；
//   ③ 跑的过程中不许出现"永远转圈"的假等待。
import 'package:box/features/comic/domain/comic_source.dart';
import 'package:box/features/comic/domain/comic_source_diagnostics.dart';
import 'package:box/features/comic/domain/comic_source_engine.dart';
import 'package:box/features/comic/domain/sources/seed_comic_source.dart';
import 'package:box/features/comic/presentation/comic_source_check_page.dart';
import 'package:flutter/material.dart';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

class _FakeTarget implements ComicSourceTarget {
  _FakeTarget({this.title = '正常页面', this.cards = 77});

  final String title;
  final int cards;

  @override
  ComicLoadFailure? get lastLoadError => null;

  @override
  Future<void> open(String url, {Map<String, String>? headers}) async {}

  @override
  Future<String> currentUrl() async => 'https://cn.baozimhcn.com/x';

  @override
  Future<String> pageTitle() async => title;

  @override
  Future<int> countOf(String css) async =>
      css.contains('comics-card') ? cards : 0;

  @override
  Future<String?> attrOf(String css, String attr) async => null;

  @override
  Future<List<String>> attrsOf(String css, String attr) async => const [];

  @override
  Future<String?> sampleHtml(String css) async => null;

  @override
  Future<String> fetchInPage(
    String url, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 15),
  }) async {
    throw ComicProbeException('自检流程不用在页面里发请求（$url）');
  }

  @override
  Future<String> evalRaw(String script) async =>
      // 与真机同形状：Android 会把 JS 返回的字符串再编码一层。
      jsonEncode('{"values":[]}');
}

/// 判"自检跑完了"要看**按钮**回到「开始自检」（跑的时候是「自检中…」）。
/// 盯转圈不行：第一项一结束转圈就消失了，那会儿整体还没跑完。
/// 推满上限还在跑 = 页面卡住了，后面的断言就该失败（这正是要抓的"假等待"）。
Future<void> drainRun(WidgetTester tester, {int maxSteps = 3000}) async {
  for (var i = 0; i < maxSteps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.text('开始自检').evaluate().isNotEmpty) return;
  }
}

void main() {
  testWidgets('一进页面就说清用途与边界（含"只代表这台手机"）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ComicSourceCheckPage(targetOverride: _FakeTarget())),
    );
    await tester.pumpAndSettle();

    expect(find.text('漫画源自检'), findsOneWidget);
    final source = ComicSource.tryParse(kSeedComicSourceJson)!;
    expect(find.text(source.name), findsOneWidget, reason: '要显示源名');
    expect(find.textContaining('这台手机'), findsWidgets, reason: '边界必须写清楚');
    expect(find.text('开始自检'), findsOneWidget);
    expect(find.text('复制结论'), findsNothing, reason: '没跑之前没有报告可复制');
  });

  testWidgets('卡片 0 命中时：三步都列出来，第一项写出原因', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ComicSourceCheckPage(
          targetOverride: _FakeTarget(title: '🐴 502 Bad Gateway', cards: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始自检'));
    await tester.pump();
    await drainRun(tester);

    expect(find.text('搜索'), findsOneWidget);
    expect(find.text('详情'), findsOneWidget);
    expect(find.text('章节取图'), findsOneWidget);
    expect(find.textContaining('502'), findsWidgets, reason: '502 要显示出来');
    // 结论段在列表下方（列表是懒构建的，屏幕外的 widget 根本不存在）→ 先滚下去。
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pump();
    expect(find.textContaining('结论：'), findsOneWidget);
    expect(find.text('复制结论'), findsOneWidget);
  });

  testWidgets('跑完后不残留"永远转圈"', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ComicSourceCheckPage(
          targetOverride: _FakeTarget(title: '🐴 502 Bad Gateway', cards: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始自检'));
    await drainRun(tester);

    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: '跑完还在转圈 = 假等待',
    );
  });
}
