// 在线服务的用例：搜索 / 详情目录 / 章节取图。
//
// 不联网、不起 WebView：假目标按**引擎真实返回的形状**回答（Android 会再编码一层，
// 这里走 androidEncode，与真机见到的形状一致）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'dart:convert';

import 'package:box/features/comic/domain/comic_online_service.dart';
import 'package:box/features/comic/domain/comic_source.dart';
import 'package:box/features/comic/domain/comic_source_engine.dart';
import 'package:box/features/comic/domain/sources/seed_comic_source.dart';

import 'fake_comic_target.dart';

ComicSource _seed() => ComicSource.tryParse(kSeedComicSourceJson)!;

void main() {
  final source = _seed();
  final card = source.searchRules['bookList']!;
  final nameRule = source.searchRules['name']!;
  final urlRule = source.searchRules['bookUrl']!;
  final coverRule = source.searchRules['coverUrl']!;
  final authorRule = source.searchRules['author']!;

  group('搜索', () {
    test('按卡片取字段：书名/书链/封面/作者一一对应（77 卡 2 链也不许错位）', () async {
      final fake = FakeComicTarget(
        perElement: {
          '$card|$nameRule': ['海贼王', '海贼王yellow'],
          '$card|$urlRule': [
            '/comic/haizeiwang-weitianrongyilang',
            '/comic/haizeiwangyellow-weitianrongyilang',
          ],
          '$card|$coverRule': [
            'https://static-tw.baozimhcn.com/cover/a.jpg',
            'https://static-tw.baozimhcn.com/cover/b.jpg',
          ],
          '$card|$authorRule': ['尾田荣一郎', '-'],
        },
      );
      final service = ComicOnlineService(target: fake, source: source, listTimeout: const Duration(milliseconds: 20));
      final hits = await service.search('海贼');

      expect(hits.length, 2);
      expect(hits[0].name, '海贼王');
      expect(hits[0].bookUrl, 'https://cn.baozimhcn.com/comic/haizeiwang-weitianrongyilang');
      expect(hits[0].cover, contains('a.jpg'));
      expect(hits[1].name, '海贼王yellow');
      expect(hits[1].bookUrl, contains('haizeiwangyellow'));
      expect(hits[1].cover, contains('b.jpg'));
      // 去重前缀那条规则（书源里 bookUrl 自带卡片选择器）必须仍然取到值
      // 假目标不给 HTML（fetchInPage 抛错）⇒ 快路走不通，退到老路：打开搜索页取
      expect(fake.opened.first, source.baseUrl, reason: '快路要先把 WebView 停在站点上');
      expect(fake.opened, anyElement(contains('/search?q=')));
    });

    test('书链为空的条目宁可丢掉，也不张冠李戴', () async {
      final fake = FakeComicTarget(
        perElement: {
          '$card|$nameRule': ['甲', '乙'],
          '$card|$urlRule': ['/comic/jia', ''],
        },
      );
      final service = ComicOnlineService(target: fake, source: source, listTimeout: const Duration(milliseconds: 20));
      final hits = await service.search('x');
      expect(hits.length, 1);
      expect(hits.single.name, '甲');
    });

    test('书链一条都没取到：如实报错（不当成"没有结果"）', () async {
      final fake = FakeComicTarget(
        perElement: {
          '$card|$nameRule': ['甲'],
          '$card|$urlRule': [''],
        },
      );
      final service = ComicOnlineService(target: fake, source: source, listTimeout: const Duration(milliseconds: 20));
      await expectLater(
        service.search('x'),
        throwsA(
          isA<ComicProbeException>().having(
            (e) => e.message,
            'message',
            contains('书链一条都没取到'),
          ),
        ),
      );
    });

    test('打不开：把每条尝试都报出来', () async {
      final fake = FakeComicTarget(failOpen: true);
      final service = ComicOnlineService(
        target: fake,
        source: source,
        waitTimeout: const Duration(milliseconds: 1),
        listTimeout: const Duration(milliseconds: 20),
        openTimeout: const Duration(milliseconds: 200),
      );
      await expectLater(
        service.search('x'),
        throwsA(
          isA<ComicProbeException>().having(
            (e) => e.message,
            'message',
            contains('搜索页打不开'),
          ),
        ),
      );
    });
  });

  group('详情与章节目录', () {
    test('书名/作者/封面 + 目录按卡片取（容器只取第一段选择器）', () async {
      final tocRule = source.bookInfoRules['tocUrl']!;
      final container = firstSelectorRule(tocRule)!;
      final fake = FakeComicTarget(
        values: {
          source.bookInfoRules['name']!: ['航海王'],
          source.bookInfoRules['author']!: ['尾田荣一郎'],
          source.bookInfoRules['coverUrl']!: ['/cover/hzw.jpg'],
        },
        perElement: {
          '$container|${source.tocRules['chapterName']}': ['第1186话', '第1185话'],
          '$container|${source.tocRules['chapterUrl']}': ['/user/page_direct?chapter_slot=1186', '/user/page_direct?chapter_slot=1185'],
        },
      );
      final service = ComicOnlineService(target: fake, source: source, listTimeout: const Duration(milliseconds: 20));
      final book = await service.bookInfo('https://cn.baozimhcn.com/comic/x');

      expect(book.name, '航海王');
      expect(book.author, '尾田荣一郎');
      // 封面是相对路径 → 要拼成完整地址
      expect(book.cover, 'https://cn.baozimhcn.com/cover/hzw.jpg');
      expect(book.chapters.length, 2);
      expect(book.chapters[0].title, '第1186话');
      expect(book.chapters[0].url, contains('chapter_slot=1186'));
    });

    test('目录是渲染出来的：一开始只数到 0/1 条，要等它出来再取', () async {
      final tocRule = source.bookInfoRules['tocUrl']!;
      final container = firstSelectorRule(tocRule)!;
      final fake = FakeComicTarget(
        counts: {container: 3},
        perElement: {
          '$container|${source.tocRules['chapterName']}': ['第1话', '第2话', '第3话'],
          '$container|${source.tocRules['chapterUrl']}': ['/c/1', '/c/2', '/c/3'],
        },
      )..countsEmptyFirstNPolls = 2; // 前两次轮询：列表还没渲染出来

      final service = ComicOnlineService(
        target: fake,
        source: source,
        listTimeout: const Duration(milliseconds: 500),
        pollInterval: const Duration(milliseconds: 1),
      );
      final book = await service.bookInfo('https://cn.baozimhcn.com/comic/x');
      expect(
        book.chapters.length,
        3,
        reason: '不等列表渲染就取，真机上就会"斗破苍穹共 1 话"',
      );
    });

    test('分类列表：跑 exploreUrl 的 JS，拿回分类（标题 + 地址）', () async {
      final cats = [
        {'title': '全部', 'url': 'https://cn.baozimhcn.com/api/list?type=all&page={{page}}'},
        {'title': '恋爱', 'url': 'https://cn.baozimhcn.com/api/list?type=lianai&page={{page}}'},
      ];
      final fake = FakeComicTarget(jsSegment: jsonEncode(cats));
      final service = ComicOnlineService(
        target: fake,
        source: source,
        listTimeout: const Duration(milliseconds: 20),
      );

      final list = await service.categories();
      expect(list.map((c) => c.title), ['全部', '恋爱']);
      // `{{page}}` 已填成第 1 页
      expect(list.first.url, contains('page=1'));
      // 必须在站点自己的页面上跑（页面里发请求才带站点 cookie）
      expect(fake.opened.first, source.baseUrl);
    });

    test('分类列表：JS 段没跑出结果时如实报错（不静默当成"没有分类"）', () async {
      final fake = FakeComicTarget(jsSegment: '');
      final service = ComicOnlineService(
        target: fake,
        source: source,
        listTimeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        service.categories(),
        throwsA(
          isA<ComicProbeException>().having(
            (e) => e.message,
            'message',
            contains('没跑出结果'),
          ),
        ),
      );
    });

    test('分类取书：JSON 规则取字段（名字/作者/封面/书链），封面补成绝对地址', () async {
      const url = 'https://cn.baozimhcn.com/api/list?type=all&page=1';
      final body = jsonEncode({
        'items': [
          {
            'comic_id': 'hanghaiwang-weitianrongyilang',
            'name': '航海王',
            'author': '尾田荣一郎',
            'topic_img': 'hanghaiwang.jpg',
          },
          {'comic_id': 'zuqiumaomao', 'name': '足球猫猫'},
        ],
      });
      final fake = FakeComicTarget(responses: {url: body});
      final service = ComicOnlineService(
        target: fake,
        source: source,
        listTimeout: const Duration(milliseconds: 20),
      );

      final page = await service.explore(url);
      final hits = page.hits;
      expect(hits.length, 2);
      expect(hits.first.name, '航海王');
      expect(hits.first.author, '尾田荣一郎');
      expect(
        hits.first.bookUrl,
        'https://cn.baozimhcn.com/comic/hanghaiwang-weitianrongyilang',
      );
      expect(
        hits.first.cover,
        'https://static-tw.baozimhcn.com/cover/hanghaiwang.jpg',
      );
      // 第二条没有作者/封面：允许空，但不能编造
      expect(hits[1].author, isNull);
      expect(hits[1].cover, isNull);
      // 响应里没给 next → 不假装还有下一页
      expect(page.nextUrl, isNull);
    });

    test('分类取书：接口给了 next 就带回来（翻页不自己算页码）', () async {
      const url = 'https://cn.baozimhcn.com/api/list?type=all&page=1';
      const next =
          'https://cn.baozimhcn.com/api/list?type=all&state=all&filter=*&page=2';
      final body = jsonEncode({
        'next': next,
        'items': [
          {'comic_id': 'a', 'name': '甲'},
        ],
      });
      final fake = FakeComicTarget(responses: {url: body});
      final service = ComicOnlineService(
        target: fake,
        source: source,
        listTimeout: const Duration(milliseconds: 20),
      );
      final page = await service.explore(url);
      expect(page.nextUrl, next, reason: '下一页要用接口给的（自己拼会漏 state/filter 参数）');
      // `items` 里没有 next 字段时也不能被当成列表项字段
      expect(page.hits.single.name, '甲');
    });

    test('分类取书：接口没给 JSON（被拦/出错页）时把开头片段带回来', () async {
      const url = 'https://cn.baozimhcn.com/api/list?type=all&page=1';
      final fake = FakeComicTarget(
        responses: {url: '<html><body>403 Forbidden</body></html>'},
      );
      final service = ComicOnlineService(
        target: fake,
        source: source,
        listTimeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        service.explore(url),
        throwsA(
          isA<ComicProbeException>().having(
            (e) => e.message,
            'message',
            allOf(contains('没返回 JSON'), contains('403 Forbidden')),
          ),
        ),
      );
    });

    test('目录取不到：章节为空表（界面按"没取到目录"显示，不编造）', () async {
      final fake = FakeComicTarget(
        values: {source.bookInfoRules['name']!: ['某书']},
      );
      final service = ComicOnlineService(target: fake, source: source, listTimeout: const Duration(milliseconds: 20));
      final book = await service.bookInfo('https://cn.baozimhcn.com/comic/x');
      expect(book.chapters, isEmpty);
      expect(book.firstChapter, isNull);
    });
  });

  group('章节取图', () {
    test('书源 JS 段给图：走 JS 段那条路', () async {
      final fake = FakeComicTarget(
        jsSegment:
            '<img src="https://s1.bzcdn.net/a/1.jpg"><img src="https://s1.bzcdn.net/a/2.jpg">',
      );
      final service = ComicOnlineService(
        target: fake,
        source: source,
        waitTimeout: const Duration(milliseconds: 50),
        listTimeout: const Duration(milliseconds: 20),
      );
      final urls = await service.chapterImages('https://cn.dzmanga.com/ch/1.html');
      expect(urls, [
        'https://s1.bzcdn.net/a/1.jpg',
        'https://s1.bzcdn.net/a/2.jpg',
      ]);
    });

    test('JS 段没给图：退回属性直读（data-src）', () async {
      final css = cssFromComicRule('class.comic-contain@amp-img')!;
      final fake = FakeComicTarget(
        jsSegment: '',
        attrs: {
          '$css|data-src': ['https://s1.bzcdn.net/b/1.jpg'],
        },
      );
      final service = ComicOnlineService(
        target: fake,
        source: source,
        waitTimeout: const Duration(milliseconds: 50),
      );
      final urls = await service.chapterImages('https://cn.dzmanga.com/ch/1.html');
      expect(urls, ['https://s1.bzcdn.net/b/1.jpg']);
    });

    test('都取不到：如实报"一个图地址都没有"', () async {
      final fake = FakeComicTarget(jsSegment: '');
      final service = ComicOnlineService(
        target: fake,
        source: source,
        waitTimeout: const Duration(milliseconds: 30),
        listTimeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        service.chapterImages('https://cn.dzmanga.com/ch/1.html'),
        throwsA(
          isA<ComicProbeException>().having(
            (e) => e.message,
            'message',
            contains('一个图地址都没有'),
          ),
        ),
      );
    });
  });

  group('快路：取 HTML 文本直接解析（不开页面、不等渲染）', () {
    // 注意：规则是 `class.a b`，HTML 的 class 属性只写类名（真页面形状）
    const card =
        'class.comics-card pure-u-1-2 pure-u-sm-1-2 pure-u-md-1-4 pure-u-lg-1-6';
    const cardClasses =
        'comics-card pure-u-1-2 pure-u-sm-1-2 pure-u-md-1-4 pure-u-lg-1-6';
    const html = '''
<html><body>
<div class="$cardClasses"><a href="/comic/haizeiwang" title="海贼王"><amp-img src="https://c/a.jpg"></amp-img></a>
  <div class="comics-card__title text-truncate">海贼王</div>
  <div class="tags text-truncate">尾田荣一郎</div></div>
<div class="$cardClasses"><a href="/comic/yellow" title="海贼王yellow"><amp-img src="https://c/b.jpg"></amp-img></a>
  <div class="comics-card__title text-truncate">海贼王yellow</div></div>
</body></html>''';

    test('搜索：HTML 文本里就能解析出卡片 → 不打开搜索页', () async {
      final fake = FakeComicTarget();
      final url = source.searchUrlFor('海贼')!;
      fake.responses[url] = html;
      final service = ComicOnlineService(
        target: fake,
        source: source,
        listTimeout: const Duration(milliseconds: 20),
      );

      final hits = await service.search('海贼');
      expect(hits.length, 2);
      expect(hits[0].name, '海贼王');
      expect(hits[0].cover, 'https://c/a.jpg');
      expect(hits[1].name, '海贼王yellow');
      expect(service.lastPath, contains('快路'));
      // 关键：**没有打开搜索页**（只把 WebView 停在站点上）
      expect(fake.opened, isNot(anyElement(contains('/search?q='))));
      expect(fake.fetched.single, url);
    });

    test('快路拿到的 HTML 里没有卡片 → 退回老路（并记下原因）', () async {
      final fake = FakeComicTarget(
        perElement: {
          '$card|${source.searchRules['name']}': ['海贼王'],
          '$card|${source.searchRules['bookUrl']}': ['/comic/haizeiwang'],
        },
      );
      fake.responses[source.searchUrlFor('海贼')!] = '<html><body>没有卡片</body></html>';
      final service = ComicOnlineService(
        target: fake,
        source: source,
        listTimeout: const Duration(milliseconds: 20),
      );

      final hits = await service.search('海贼');
      expect(hits.single.name, '海贼王');
      expect(service.lastPath, contains('老路'));
      expect(service.lastPathNote, contains('没解析出卡片'));
    });

    test('详情：HTML 文本里就能解析出书名/作者/目录', () async {
      const toc =
          'pure-u-1-1 pure-u-sm-1-2 pure-u-md-1-3 pure-u-lg-1-4 comics-chapters';
      const detailHtml = '''
<html><body>
<div class="comics-detail__title">航海王</div>
<div class="comics-detail__author">尾田荣一郎</div>
<amp-img src="https://c/cover.jpg"></amp-img>
<div class="$toc"><a href="/user/page_direct?chapter_slot=1186"><div><span>第1186话 再一次</span></div></a></div>
<div class="$toc"><a href="/user/page_direct?chapter_slot=1185"><div><span>第1185话 伙伴</span></div></a></div>
</body></html>''';
      final fake = FakeComicTarget();
      fake.responses['https://cn.baozimhcn.com/comic/x'] = detailHtml;
      final service = ComicOnlineService(
        target: fake,
        source: source,
        listTimeout: const Duration(milliseconds: 20),
      );

      final book = await service.bookInfo('https://cn.baozimhcn.com/comic/x');
      expect(book.name, '航海王');
      expect(book.author, '尾田荣一郎');
      expect(book.chapters.length, 2);
      expect(book.chapters.first.title, '第1186话 再一次');
      expect(book.chapters.first.url, contains('chapter_slot=1186'));
      expect(service.lastPath, contains('快路'));
      expect(fake.opened, isNot(anyElement(contains('/comic/x'))));
    });

    test('快路拿到的不是网页（被拦的挑战页）→ 记原因并退回老路', () async {
      final fake = FakeComicTarget();
      fake.responses[source.searchUrlFor('海贼')!] = '{"challenge_url":"https://x"}';
      final service = ComicOnlineService(
        target: fake,
        source: source,
        listTimeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        service.search('海贼'),
        throwsA(
          isA<ComicProbeException>().having(
            (e) => e.message,
            'message',
            contains('书链一条都没取到'),
          ),
        ),
      );
      expect(service.lastPathNote, contains('不是网页'));
    });
  });
}
