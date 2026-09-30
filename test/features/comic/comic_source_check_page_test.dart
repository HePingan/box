// 漫画源自检页的界面用例（假取数，不联网、不起 WebView）。
//
// 守三条底线：
//   ① 三步都要逐条显示，失败项必须写出原因（不能只给一个红叉）；
//   ② 全通过时要有明确结论，并且「复制结论」拿得到完整报告（用户要贴回来当证据）；
//   ③ 跑的过程中不许出现"永远转圈"的假等待。
import 'package:box/features/comic/domain/comic_fetcher.dart';
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
    // 清单里**每一份**内置源都要能自检 —— 用户报过「自检里没有野蛮漫画」，
    // 而那一份正是 App 默认在用的。
    for (final json in kSeedComicSourcesJson) {
      final name = ComicSource.tryParse(json)!.name;
      expect(find.text(name), findsOneWidget, reason: '$name 要出现在可自检的源里');
    }
    final defaultSource = ComicSource.tryParse(kSeedComicSourcesJson.first)!;
    final chip = tester.widget<ChoiceChip>(
      find.ancestor(
        of: find.text(defaultSource.name),
        matching: find.byType(ChoiceChip),
      ),
    );
    expect(chip.selected, isTrue, reason: '默认要选中 App 实际用的那份源（清单第一份）');
    expect(find.textContaining('这台手机'), findsWidgets, reason: '边界必须写清楚');
    expect(find.text('开始自检'), findsOneWidget);
    expect(find.text('复制结论'), findsNothing, reason: '没跑之前没有报告可复制');
  });

  testWidgets('从在线页失败态进来时预选那份源', (tester) async {
    final second = ComicSource.tryParse(kSeedComicSourcesJson[1])!;

    await tester.pumpWidget(
      MaterialApp(
        home: ComicSourceCheckPage(
          targetOverride: _FakeTarget(),
          initialSourceName: second.name,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(
            find.ancestor(
              of: find.text(second.name),
              matching: find.byType(ChoiceChip),
            ),
          )
          .selected,
      isTrue,
      reason: '从哪份源点进来就自检哪份源（用户想问的就是"我现在这本读不了，是源的问题吗"）',
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.ancestor(
              of: find.text(ComicSource.tryParse(kSeedComicSourcesJson.first)!.name),
              matching: find.byType(ChoiceChip),
            ),
          )
          .selected,
      isFalse,
    );
  });

  testWidgets('预选的名字对不上（比如清单换了名字）→ 回落到清单第一份，不崩也不空选', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ComicSourceCheckPage(
          targetOverride: _FakeTarget(),
          initialSourceName: '没有这份源',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(
            find.ancestor(
              of: find.text(ComicSource.tryParse(kSeedComicSourcesJson.first)!.name),
              matching: find.byType(ChoiceChip),
            ),
          )
          .selected,
      isTrue,
    );
  });

  testWidgets('能换源；换源会把上一份源的结论清掉（不混着显示）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ComicSourceCheckPage(
          targetOverride: _FakeTarget(title: '🐴 502 Bad Gateway', cards: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final first = ComicSource.tryParse(kSeedComicSourcesJson.first)!;
    final second = ComicSource.tryParse(kSeedComicSourcesJson[1])!;

    await tester.tap(find.text('开始自检'));
    await drainRun(tester);
    // 报告在列表下方（懒构建）→ 滚到看得见再断言（别盯着屏幕外的东西）。
    await tester.dragUntilVisible(
      find.textContaining('结论：'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    expect(find.textContaining('结论：'), findsOneWidget);
    expect(find.textContaining('「${first.name}」'), findsWidgets, reason: '结论要写明是哪份源');

    // 回到顶部换到第二份源：旧结论必须消失（它不是这份源跑出来的）。
    await tester.dragUntilVisible(
      find.text(second.name),
      find.byType(ListView),
      const Offset(0, 200), // 往回滚到顶部（+y = 往下拖）
    );
    await tester.tap(find.text(second.name));
    await tester.pumpAndSettle();
    expect(find.textContaining('结论：'), findsNothing, reason: '换源后旧结论要清掉');
    expect(find.text(second.name), findsOneWidget);
    expect(find.text('复制结论'), findsNothing);
  });

  testWidgets('接口型源（野蛮漫画）：三步全通，第三步说明走的是站点的取图接口', (tester) async {
    final fetcher = _FakeApiFetcher(
      chapterHtml: "let read={aid:'7530',cid:'772668',picCount:7};",
      batches: [
        _picsJson(5, total: 7, from: 1),
        _picsJson(2, total: 7, from: 6),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ComicSourceCheckPage(
          targetOverride: _YemanTarget(),
          fetcherOverride: fetcher,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始自检'));
    await drainRun(tester);
    // 顶部：前两步的标题在场（列表懒构建，第三步这会儿可能还在屏幕外）。
    expect(find.text('搜索'), findsOneWidget);
    expect(find.text('详情'), findsOneWidget);
    // 跳到底：让第三步的说明与结论都建出来（跳到底后顶部的会被回收，所以先断言上面两条）。
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ).first,
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    // 不要 pumpAndSettle：页面上有一直在动的元素（可选中文本的光标等），settle 会超时。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('章节取图'), findsOneWidget);
    // 步骤说明用的是 SelectableText（真机上能长按复制去贴），普通 find.text 找不到它。
    expect(
      find.textContaining('取图接口', findRichText: true),
      findsOneWidget,
      reason: '要说清图是从接口来的（图不在 HTML 里）',
    );
    expect(find.textContaining('三步全通', findRichText: true), findsOneWidget);
    expect(fetcher.posted, hasLength(2), reason: '7 张 = 两批（5 + 2）');
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
    // 三步都是懒构建的列表项：新增了"快路没走通"的原因之后每格更高，
    // 靠下滑一格一格把它们翻出来（不能假设三格同时在屏内）。
    await tester.drag(find.byType(ListView), const Offset(0, -160));
    await tester.pump();
    expect(find.text('详情'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -160));
    await tester.pump();
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

/// 野蛮漫画那份源（接口型）的假取数：按它自己的规则作答，让三步真能跑通。
class _YemanTarget implements ComicSourceTarget {
  @override
  ComicLoadFailure? get lastLoadError => null;

  @override
  Future<void> open(String url, {Map<String, String>? headers}) async {}

  @override
  Future<String> currentUrl() async => 'https://www.yemancomic.com/x';

  @override
  Future<String> pageTitle() async => '野蛮漫画';

  @override
  Future<int> countOf(String css) async {
    if (css.contains('comic-chapter-item')) return 398; // 目录里的章链
    if (css.contains('js_comic-title')) return 1; // 详情页书名元素
    if (css.contains('comic-item')) return 21; // 搜索卡片
    return 0;
  }

  @override
  Future<String?> attrOf(String css, String attr) async =>
      css.contains('comic-chapter-item') ? '/chapter/7530/772668.html' : null;

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
  Future<String> evalRaw(String script) async {
    // 取值脚本里把规则原文抠出来（引擎跑在真机的 WebView 里，这里只做映射）。
    final m = RegExp(r'legadoExtract\("((?:[^"\\]|\\.)*)"\)').firstMatch(script);
    final rule = (m?.group(1) ?? '').replaceAll(r'\"', '"');
    final values = switch (rule) {
      'class.title@text' => ['海贼王'],
      'tag.a.0@href' => ['/comic/7530/'],
      'id.js_comic-title@text' => ['航海王'],
      'class.author@text' => ['尾田荣一郎'],
      _ => const <String>[],
    };
    // 与真机同形状：Android 会把 JS 返回的字符串再编码一层。
    return jsonEncode(jsonEncode({'values': values}));
  }
}

/// 假的取数器：接口型源的「章节取图」要「取章节页 → 打取图接口」。
class _FakeApiFetcher implements ComicFetcher {
  _FakeApiFetcher({required this.chapterHtml, required this.batches});

  final String chapterHtml;
  final List<String> batches;
  final List<String> posted = [];
  int _n = 0;

  @override
  Map<String, String> get headers => const {'User-Agent': 'phone-ua'};

  @override
  Map<String, String> headersFor(String url) => headers;

  @override
  Future<String> getText(String url) async => chapterHtml;

  @override
  Future<String> postForm(String url, Map<String, String> form) async {
    posted.add('${form['offset']}');
    if (_n >= batches.length) {
      throw StateError('取图接口被多打了一批（第 ${_n + 1} 批），用例只准备了 ${batches.length} 批');
    }
    return batches[_n++];
  }

  @override
  String wrap(String url) => url;

  @override
  void close() {}
}

/// 造一批取图接口的响应：`from` 张起、要 `count` 张，站点自报共 `total` 张。
String _picsJson(int count, {required int total, int from = 1}) => jsonEncode({
  'data': {
    'total': total,
    'pic': [
      for (var i = from; i < from + count; i++)
        {'pic': 'https://tuer.justpic01pt.com:666/comic/$i.jpg'},
    ],
  },
});
