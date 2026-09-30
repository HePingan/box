// 自检的第 1/2 步必须跑 **App 实际那条路**（页面内取 HTML 文本 + 规则引擎解析），
// 快路不通才退到"打开页面、等渲染、在 DOM 里查"。
//
// 为什么要锁这条：站点给"取文本"和给"渲染后的 DOM"的东西不保证一样。只验渲染那条路
// 就会出现「自检说通过、App 却读不了」，或者反过来把一份好源判死 —— 而自检的全部价值
// 就是"这一步过了，App 就能用"。

import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/comic/domain/comic_source.dart';
import 'package:box/features/comic/domain/comic_source_diagnostics.dart';

import 'fake_comic_target.dart';

/// 一份规则简单、可控的测试源（键名与内置源同形）。
const String _sourceJson = r'''
{
  "bookSourceName": "测试源",
  "bookSourceUrl": "https://t.test",
  "bookSourceType": 2,
  "searchUrl": "https://t.test/search?q={{key}}",
  "ruleSearch": {
    "bookList": "class.comic-item",
    "name": "class.title@text",
    "bookUrl": "tag.a.0@href"
  },
  "ruleBookInfo": {
    "name": "class.book-title@text",
    "author": "class.author@text",
    "tocUrl": "class.chapter-list@tag.a@text"
  },
  "ruleToc": {
    "chapterName": "tag.a@text",
    "chapterUrl": "tag.a@href"
  }
}
''';

const String _searchHtml = '''
<html><body>
  <div class="comic-item"><a href="/comic/1"><span class="title">海贼王</span></a></div>
  <div class="comic-item"><a href="/comic/2"><span class="title">火影忍者</span></a></div>
</body></html>
''';

const String _detailHtml = '''
<html><body>
  <h1 class="book-title">海贼王</h1>
  <span class="author">尾田荣一郎</span>
  <div class="chapter-list"><a href="/c/1">第1话</a></div>
  <div class="chapter-list"><a href="/c/2">第2话</a></div>
</body></html>
''';

void main() {
  final source = ComicSource.tryParse(_sourceJson)!;
  final searchUrl = source.searchUrlFor('海贼')!;

  Future<ComicProbeReport> run(FakeComicTarget target) => runComicSourceProbe(
    target: target,
    source: source,
    key: '海贼',
    waitTimeout: const Duration(milliseconds: 50),
    pollInterval: const Duration(milliseconds: 1),
  );

  test('快路能通：搜索/详情都走「取 HTML 文本 + 规则引擎」，说明里写明是这条路', () async {
    final fake = FakeComicTarget(
      responses: {searchUrl: _searchHtml, 'https://t.test/comic/1': _detailHtml},
    );

    final report = await run(fake);

    final search = report.steps[0];
    expect(search.name, '搜索');
    expect(search.ok, isTrue);
    expect(search.note, contains('快路'));
    expect(search.note, contains('与 App 搜索同一条路'));
    expect(search.samples, ['海贼王', '火影忍者']);
    expect(report.firstBookUrl, 'https://t.test/comic/1');

    final detail = report.steps[1];
    expect(detail.name, '详情');
    expect(detail.ok, isTrue);
    expect(detail.note, contains('与 App 打开详情页同一条路'));
    expect(detail.note, contains('书名「海贼王」'));
    expect(detail.note, contains('章节 2 条'));
    expect(report.tocCount, 2);
    expect(report.firstChapterUrl, 'https://t.test/c/1');

    // 关键：既然快路通了，就不该再去打开页面渲染（DOM 那条路一次都不该走）。
    expect(
      fake.opened.where((u) => u == searchUrl || u.contains('/comic/1')),
      isEmpty,
      reason: '快路通了还去开页面，等于自检跑的不是 App 那条路',
    );
  });

  test('快路不通：如实写上"快路没走通"的原因，再退到渲染后查 DOM（并仍能得出结论）', () async {
    // 不准备 responses ⇒ fetchInPage 抛错 ⇒ 快路不通。
    final cardCss = cssFromComicRule(source.searchRules['bookList']!)!;
    final detailCss = cssFromComicRule(source.bookInfoRules['name']!)!;
    final tocCss = firstSelectorCss(source.bookInfoRules['tocUrl']!)!;
    final chapterCss = '$tocCss a[href]';
    final fake = FakeComicTarget(
      counts: {cardCss: 2, detailCss: 1, chapterCss: 2},
      values: {
        source.searchRules['name']!: ['海贼王', '火影忍者'],
        source.searchRules['bookUrl']!: ['/comic/1', '/comic/2'],
        source.bookInfoRules['name']!: ['海贼王'],
        source.bookInfoRules['author']!: ['尾田荣一郎'],
      },
      attrs: {'$chapterCss|href': ['/c/1']},
    );

    final report = await run(fake);

    final search = report.steps[0];
    expect(search.ok, isTrue, reason: '老路走通了仍算通过（实际说明：${search.note}）');
    expect(search.note, contains('快路没走通'));
    expect(search.note, contains('退到渲染后查 DOM'));
    expect(fake.opened, contains(searchUrl), reason: '这次才该真去打开页面');

    final detail = report.steps[1];
    expect(detail.ok, isTrue);
    expect(detail.note, contains('快路没走通'));
    expect(report.firstChapterUrl, 'https://t.test/c/1');
  });

  test('快路取回来的不是搜索结果（挑战页）：不硬说通过，退回 DOM 并把原因带上', () async {
    final fake = FakeComicTarget(
      // 挑战页是合法 HTML，但里面没有书链 —— 必须被当成"快路没通"，而不是"这本书没有"。
      responses: {searchUrl: '<html><body>Just a moment…</body></html>'},
      counts: {cssFromComicRule(source.searchRules['bookList']!)!: 0},
    );

    final report = await run(fake);

    final search = report.steps[0];
    expect(search.ok, isFalse);
    expect(search.note, contains('快路没走通'));
    expect(search.note, contains('没解析出书链'));
  });

  test('源里没有独立假数据的测试跑不了 → 至少别把"跳过"说成"通过"', () async {
    // 搜索地址为空：这一步必须如实报"没法搜"，不能因为后面没跑就默认通过。
    final noSearch = ComicSource.tryParse(
      _sourceJson.replaceAll(
        '"searchUrl": "https://t.test/search?q={{key}}",',
        '"searchUrl": "",',
      ),
    )!;
    final report = await runComicSourceProbe(
      target: FakeComicTarget(),
      source: noSearch,
      waitTimeout: const Duration(milliseconds: 50),
      pollInterval: const Duration(milliseconds: 1),
    );

    expect(report.steps[0].ok, isFalse);
    expect(report.steps[0].note, contains('没法搜'));
    expect(report.allOk, isFalse);
  });
}
