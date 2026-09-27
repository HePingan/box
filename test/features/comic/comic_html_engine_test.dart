// HTML 规则引擎的用例（在**取到的 HTML 文本**上跑书源规则）。
//
// 片段按真页面形状写（来自 cn.baozimhcn.com 的真 HTML）：
//   卡片：<div class="comics-card pure-u-1-2 …"><a href="/comic/xxx" title="书名"><amp-img src="封面">…</a>…
//   目录：<div class="pure-u-1-1 … comics-chapters"><a href="/user/page_direct?…"><div><span>第N话</span></div></a></div>
//
// 重点：与页面里的 JS 引擎**同一语义**（同一份规则在两处跑出不同结果是最坏的情况）。
library;

import 'package:box/features/comic/domain/comic_html_engine.dart';
import 'package:flutter_test/flutter_test.dart';

const String _searchHtml = '''
<!DOCTYPE html><html><body>
<div class="comics-card pure-u-1-2 pure-u-sm-1-2 pure-u-md-1-4 pure-u-lg-1-6"
  ><a href="/comic/haizeiwang-weitianrongyilang" title="海贼王" class="comics-card__poster"
  ><amp-img alt="海贼王" width="150" height="200"
    src="https://static-tw.baozimhcn.com/cover/haizeiwang-weitianrongyilang.jpg?w=285&amp;h=375&amp;q=100"
    ></amp-img></a>
  <div class="comics-card__title text-truncate">海贼王</div>
  <div class="tags text-truncate">尾田荣一郎</div>
</div>
<div class="comics-card pure-u-1-2 pure-u-sm-1-2 pure-u-md-1-4 pure-u-lg-1-6"
  ><a href="/comic/zuqiumaomao-tumaofeng" title="足球猫猫" class="comics-card__poster"
  ><amp-img alt="足球猫猫" src="https://static-tw.baozimhcn.com/cover/zuqiumaomao.jpg"
    ></amp-img></a>
  <div class="comics-card__title text-truncate">足球猫猫</div>
  <div class="tags text-truncate">-土猫Feng-</div>
</div>
</body></html>
''';

const String _detailHtml = '''
<!DOCTYPE html><html><body>
<div class="comics-detail__title">航海王</div>
<div class="comics-detail__author">尾田荣一郎</div>
<div class="pure-u-1-1 pure-u-sm-1-2 pure-u-md-1-3 pure-u-lg-1-4 comics-chapters"
  ><a href="/user/page_direct?comic_id=x&amp;section_slot=0&amp;chapter_slot=1186"
      class="comics-chapters__item"><div><span>第1186话 再一次</span></div></a></div>
<div class="pure-u-1-1 pure-u-sm-1-2 pure-u-md-1-3 pure-u-lg-1-4 comics-chapters"
  ><a href="/user/page_direct?comic_id=x&amp;section_slot=0&amp;chapter_slot=1185"
      class="comics-chapters__item"><div><span>第1185话 伙伴</span></div></a></div>
<div class="pure-u-1-1 pure-u-sm-1-2 pure-u-md-1-3 pure-u-lg-1-4 comics-chapters"
  ><a href="/user/page_direct?comic_id=x&amp;section_slot=0&amp;chapter_slot=1184"
      class="comics-chapters__item"><div></div></a></div>
</body></html>
''';

// 书源里用到的规则原文
const String _cardRule =
    'class.comics-card pure-u-1-2 pure-u-sm-1-2 pure-u-md-1-4 pure-u-lg-1-6';
const String _tocRule =
    'class.pure-u-1-1 pure-u-sm-1-2 pure-u-md-1-3 pure-u-lg-1-4 comics-chapters';

void main() {
  group('搜索卡片（按卡片取字段）', () {
    test('书名 / 书链 / 封面 / 作者 各一张卡一个值，顺序一一对应', () {
      final doc = parseComicHtml(_searchHtml);
      final names = comicHtmlPerElement(doc, _cardRule, 'class.comics-card__title text-truncate@text');
      final links = comicHtmlPerElement(doc, _cardRule, '$_cardRule@tag.a@href');
      final covers = comicHtmlPerElement(doc, _cardRule, 'tag.amp-img.0@src');
      final authors = comicHtmlPerElement(doc, _cardRule, 'class.tags text-truncate@text');

      expect(names, ['海贼王', '足球猫猫']);
      // 每张卡里还有别的 <a>，按卡片取才对得上（拉平会错位）
      expect(links, [
        '/comic/haizeiwang-weitianrongyilang',
        '/comic/zuqiumaomao-tumaofeng',
      ]);
      expect(covers.first, contains('haizeiwang-weitianrongyilang.jpg?w=285&h=375&q=100'), reason: 'HTML 实体 &amp; 要还原成 &');
      expect(authors, ['尾田荣一郎', '-土猫Feng-']);
    });
  });

  group('章节目录（按卡片取字段）', () {
    test('标题与链接都按卡片取；某一话没有标题时补空串（不错位）', () {
      final doc = parseComicHtml(_detailHtml);
      final titles = comicHtmlPerElement(doc, _tocRule, 'tag.span@text');
      final links = comicHtmlPerElement(doc, _tocRule, 'tag.a@href');

      expect(titles.length, 3, reason: '第 3 项没有标题，也要占一位（否则与链接错位）');
      expect(titles[0], '第1186话 再一次');
      expect(titles[1], '第1185话 伙伴');
      expect(titles[2], '');
      expect(links.length, 3);
      expect(links.first, contains('chapter_slot=1186'));
    });

    test('整页取名/作者（不是按卡片）', () {
      final doc = parseComicHtml(_detailHtml);
      expect(comicHtmlExtract(doc, 'class.comics-detail__title@text'), ['航海王']);
      expect(comicHtmlExtract(doc, 'class.comics-detail__author@text'), ['尾田荣一郎']);
    });
  });

  group('与页面引擎同语义的几条硬规矩', () {
    test('取值步先判：`href` 当属性取，不会当成类选择器 .href', () {
      final doc = parseComicHtml(_searchHtml);
      final href = comicHtmlExtract(doc, 'tag.a@href');
      expect(href.first, '/comic/haizeiwang-weitianrongyilang');
    });

    test('取值步丢掉空值；`.0` 取第一个', () {
      final doc = parseComicHtml(_detailHtml);
      // 三个容器里只有两次有章节名 → 空的被丢掉
      expect(comicHtmlExtract(doc, 'tag.span@text'), ['第1186话 再一次', '第1185话 伙伴']);
      expect(comicHtmlExtract(doc, 'tag.span.0@text'), ['第1186话 再一次']);
    });

    test('只有选择器、没有取值步：报错（不静默返回空）', () {
      final doc = parseComicHtml(_detailHtml);
      expect(
        () => comicHtmlExtract(doc, _tocRule),
        throwsA(
          isA<ComicHtmlRuleException>().having(
            (e) => e.message,
            'message',
            contains('没有取值步'),
          ),
        ),
      );
    });

    test('不认识的规则段：如实报错，附上那一段', () {
      final doc = parseComicHtml(_detailHtml);
      expect(
        () => comicHtmlExtract(doc, 'class.a@tag.b@标签@text'),
        throwsA(
          isA<ComicHtmlRuleException>().having(
            (e) => e.message,
            'message',
            contains('不认识的规则段'),
          ),
        ),
      );
    });

    test('卡片规则取不到卡片 → 空表（界面按"没取到"显示，不编造）', () {
      final doc = parseComicHtml(_detailHtml);
      expect(comicHtmlPerElement(doc, 'class.没有这个类', 'tag.span@text'), isEmpty);
    });
  });
}
