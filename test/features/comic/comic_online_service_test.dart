// 在线服务的用例：搜索 / 详情目录 / 章节取图。
//
// 不联网、不起 WebView：假目标按**引擎真实返回的形状**回答（Android 会再编码一层，
// 这里走 androidEncode，与真机见到的形状一致）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:box/features/comic/domain/comic_online_service.dart';
import 'package:box/features/comic/domain/comic_relay.dart';
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

    test('分类列表：纯文本清单（名称::地址）——不用跑 JS、不用开页面', () async {
      // 2026-10-01：野蛮漫画没配 exploreUrl，界面上一直显示「分类浏览不可用」。
      // 补上清单后这里钉住两条：填好 {{page}}、且**不碰站点页面**（纯文本不需要）。
      final yeman = ComicSource.tryParse(kSeedComicSourceYemanJson)!;
      final fake = FakeComicTarget();
      final service = ComicOnlineService(
        target: fake,
        source: yeman,
        listTimeout: const Duration(milliseconds: 20),
      );

      final list = await service.categories();

      expect(list.length, greaterThanOrEqualTo(10), reason: '这份源给了十来个分类');
      expect(list.first.title, '全部');
      expect(
        list.first.url,
        'https://yemancomic.com/comiclists/9/全部/3/1.html',
        reason: '`{{page}}` 填成第 1 页',
      );
      expect(fake.opened, isEmpty, reason: '纯文本清单不用打开站点页面');
    });

    test('分类取书：分类页是网页（class. 规则）→ 走页面解析，下一页按清单里的 {{page}} 推', () async {
      final yeman = ComicSource.tryParse(kSeedComicSourceYemanJson)!;
      const url = 'https://yemancomic.com/comiclists/9/全部/3/1.html';
      final fake = FakeComicTarget(responses: {url: _yemanListHtml});
      final service = ComicOnlineService(
        target: fake,
        source: yeman,
        listTimeout: const Duration(milliseconds: 20),
      );

      final page = await service.explore(url);

      expect(page.hits.length, 2);
      expect(page.hits.first.name, '海贼王~');
      expect(
        page.hits.first.bookUrl,
        'https://yemancomic.com/book/7530/',
        reason: '相对地址要补成绝对地址',
      );
      expect(page.hits.first.cover, contains('justpic'));
      expect(
        page.nextUrl,
        'https://yemancomic.com/comiclists/9/全部/3/2.html',
        reason: '清单里写着 {{page}}，翻页就按它加一（不假装到底了）',
      );
      expect(
        service.lastPath,
        contains('快路'),
        reason: 'HTML 已经在手里就直接解析，不走"打开页面渲染"那条慢路',
      );
    });

    test('分类取书：网页式分类页解析不出卡片时，如实报出来（不当成成功）', () async {
      final yeman = ComicSource.tryParse(kSeedComicSourceYemanJson)!;
      const url = 'https://yemancomic.com/comiclists/9/全部/3/1.html';
      final fake = FakeComicTarget(
        responses: {url: '<html><body>什么都没有</body></html>'},
      );
      final service = ComicOnlineService(
        target: fake,
        source: yeman,
        listTimeout: const Duration(milliseconds: 20),
      );

      await expectLater(
        service.explore(url),
        throwsA(isA<ComicProbeException>()),
      );
    });

    test('分类列表：没配 exploreUrl 时说的是"没配"，不是"格式看不懂"', () async {
      // 两种坏法要分开：没配是**源的问题**（改源），格式看不懂才是**解析的问题**。
      const bare = ComicSource(
        name: '没分类的源',
        baseUrl: 'https://x.example',
        searchUrl: 'https://x.example/s?q={{key}}',
        searchRules: {'bookList': 'class.a'},
      );
      final service = ComicOnlineService(
        target: FakeComicTarget(),
        source: bare,
        listTimeout: const Duration(milliseconds: 20),
      );

      await expectLater(
        service.categories(),
        throwsA(
          isA<ComicProbeException>().having(
            (e) => e.message,
            'message',
            allOf(contains('没配分类浏览'), isNot(contains('格式'))),
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

  // ─────────────────────────────────────────────────────────────
  // 中转：手机那条网连不上站点，取数全经自己的服务器
  // ─────────────────────────────────────────────────────────────
  group('中转（章 HTML 与取图接口都经服务器）', () {
    final yeman = ComicSource.tryParse(kSeedComicSourceYemanJson)!;

    test('搜索：HTML 从中转取回后解析（不碰 WebView）', () async {
      final host = FakeComicRelay(searchHtml: _yemanSearchHtml);
      final target = FakeComicTarget();
      final service = ComicOnlineService(
        target: target,
        source: yeman,
        relay: host.client(),
      );

      final hits = await service.search('海贼');
      expect(hits.length, 2);
      expect(hits[0].name, '海贼王~');
      expect(hits[0].bookUrl, 'https://yemancomic.com/book/7530/');
      expect(hits[0].cover, contains('tuer.justpic01pt.com:666'));
      // 这份源没写作者规则：给"没有"，不能因此报错/错位
      expect(hits[0].author, isNull);
      expect(service.lastPath, contains('中转'));
      // 走中转就不该再去动 WebView（手机那条网本来就进不去站点）
      expect(target.opened, isEmpty);
      expect(target.fetched, isEmpty);
      expect(host.getTexts.single, contains('/search?searchkey='));
    });

    test('详情：书名/作者/简介/封面/目录都从中转的 HTML 解析', () async {
      final service = ComicOnlineService(
        target: FakeComicTarget(),
        source: yeman,
        relay: FakeComicRelay(bookHtml: _yemanBookHtml).client(),
      );

      final book = await service.bookInfo('https://yemancomic.com/book/7530/');
      expect(book.name, '海贼王~', reason: '要取 h1#js_comic-title，不是那个嵌了作者的 h1.name');
      expect(book.author, '尾田栄一郎');
      expect(book.intro, contains('ONE PIECE'));
      expect(book.cover, contains('cover.jpg'));
      expect(book.chapters.length, 2);
      expect(book.chapters.first.title, '1卷');
      expect(
        book.chapters.first.url,
        'https://yemancomic.com/chapter/7530/772668.html',
      );
      expect(service.lastPath, contains('中转'));
    });

    test('章节取图：一批 10 张（站点上限就是 10）；地址包成中转地址；offset 递增正确', () async {
      final host = FakeComicRelay(
        chapterHtml: _yemanChapterHtml(total: 10),
        total: 10,
      );
      final service = ComicOnlineService(
        target: FakeComicTarget(),
        source: yeman,
        relay: host.client(),
      );

      final urls = await service.chapterImages(
        'https://yemancomic.com/chapter/7530/772668.html',
      );

      expect(urls.length, 10);
      expect(host.postForms.map((f) => f['offset']).toList(), ['0']);
      expect(
        host.postForms.first['limit'],
        '10',
        reason: '要 10 张：站点封顶 10（实测 limit>10 也只回 10），一整话少跑一半往返',
      );
      expect(host.postForms.first['id'], '772668');
      expect(host.postForms.first['aid'], '7530');
      // 地址必须是**中转地址**（手机直连图片 CDN 也连不上），但令牌不在地址里
      for (final u in urls) {
        expect(u, startsWith(_relayEndpoint));
        expect(
          Uri.parse(u).queryParameters['u'],
          startsWith('https://tuer.justpic01pt.com:666/'),
        );
      }
      expect(urls.first, isNot(contains(_relayToken)));
      expect(service.lastPath, contains('中转'));
    });

    test('章节取图：接口 502 时报清楚"第几批、从哪张开始"', () async {
      final host = FakeComicRelay(
        chapterHtml: _yemanChapterHtml(total: 10),
        total: 10,
        failFirstPost: true,
      );
      final service = ComicOnlineService(
        target: FakeComicTarget(),
        source: yeman,
        relay: host.client(),
      );

      await expectLater(
        service.chapterImages('https://yemancomic.com/chapter/7530/772668.html'),
        throwsA(
          isA<ComicProbeException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('第 1 批'),
              contains('offset=0'),
              contains('中转取不到'),
            ),
          ),
        ),
      );
    });

    test('章节页里没有取图参数：如实报"站点可能改版"，不静默给空', () async {
      final service = ComicOnlineService(
        target: FakeComicTarget(),
        source: yeman,
        relay: FakeComicRelay(
          chapterHtml: '<html><body>没有脚本</body></html>',
        ).client(),
      );

      await expectLater(
        service.chapterImages('https://yemancomic.com/chapter/7530/772668.html'),
        throwsA(
          isA<ComicProbeException>().having(
            (e) => e.message,
            'message',
            contains('找不到取图参数'),
          ),
        ),
      );
    });

    test('中转取不到：如实抛错，**不**悄悄退回"打开页面"那条路', () async {
      final target = FakeComicTarget();
      final service = ComicOnlineService(
        target: target,
        source: yeman,
        relay: (FakeComicRelay()..failGet = true).client(),
      );

      await expectLater(
        service.search('海贼'),
        throwsA(isA<ComicProbeException>()),
      );
      expect(target.opened, isEmpty, reason: '不该偷偷去开站点页面');
      expect(target.fetched, isEmpty);
    });

    test('源带 relay 但没有令牌 → 直连站点取数（不再要求先填令牌）', () async {
      final searchUrl = yeman.searchUrlFor('海贼')!;
      final target = FakeComicTarget(responses: {searchUrl: _yemanSearchHtml});
      final service = ComicOnlineService(target: target, source: yeman);

      final hits = await service.search('海贼');

      expect(hits, isNotEmpty);
      expect(hits.first.name, contains('海贼'));
      expect(
        target.fetched,
        contains(searchUrl),
        reason: '直连：页内直接取站点 HTML，不经任何服务器',
      );
    });

    test('章节取图：没有令牌 → 直连取图接口（图地址不包中转，且带手机 UA）', () async {
      final host = FakeComicRelay(chapterHtml: _yemanChapterHtml(total: 10));
      final service = ComicOnlineService(
        target: FakeComicTarget(),
        source: yeman,
        directClient: host.directClient(),
      );

      final urls = await service.chapterImages(
        'https://yemancomic.com/chapter/7530/772668.html',
      );

      expect(urls.length, 10);
      expect(
        urls.every((u) => u.startsWith('https://tuer.justpic01pt.com:666/')),
        isTrue,
        reason: '直连不把图片地址包成中转地址',
      );
      expect(
        host.postForms.length,
        1,
        reason: '10 张按一批 10 张取（站点上限 10），一次往返取完',
      );
      expect(
        host.directUserAgents,
        everyElement(contains('Android')),
        reason: '直连必须带手机 UA，否则站点 307 空响应',
      );
      expect(service.lastPath, contains('直连'));
    });

    test('章节取图：逐批回调（onPartial）—— 阅读页靠它先显示前几张，不必等整话取完', () async {
      // 209 张 = 21 批：用户报的"取第一页一直转圈"就是等整话取完才显示。
      final host = FakeComicRelay(
        chapterHtml: _yemanChapterHtml(total: 209),
        total: 209,
      );
      final service = ComicOnlineService(
        target: FakeComicTarget(),
        source: yeman,
        directClient: host.directClient(),
      );

      final progress = <int>[];
      final urls = await service.chapterImages(
        'https://yemancomic.com/chapter/7530/772668.html',
        onPartial: (partial) => progress.add(partial.length),
      );

      expect(urls.length, 209);
      expect(
        progress.take(3).toList(),
        [10, 20, 30],
        reason: '每批都回调一次、长度递增（第一批就能显示）',
      );
      expect(progress.last, 209, reason: '最后一批回调到整话的张数');
    });

    test('headersFor：中转地址才带令牌，图床地址只给手机 UA（令牌不许发给第三方）', () {
      const endpoint = 'https://box.hpa888.top/comicrelay/fetch';
      final relay = ComicRelay(endpoint: endpoint, token: _relayToken);
      final withRelay = ComicOnlineService(
        target: FakeComicTarget(),
        source: yeman,
        relay: relay,
      );
      // 我们自己的中转地址：带令牌（不带就是每张图 401）
      expect(
        withRelay.headersFor('$endpoint?u=https%3A%2F%2Ftuer.justpic01pt.com%2Fx.jpg')[
            'X-Box-Token'],
        _relayToken,
      );
      // 图床 / 站点地址：**不许**带令牌（发给第三方就是泄露），只给手机 UA
      final cdn = withRelay.headersFor(
        'https://tuer.justpic01pt.com:666/picbed/CPMH/haizeiwang/a.jpg',
      );
      expect(cdn.containsKey('X-Box-Token'), isFalse, reason: '令牌只发给自己的中转');
      expect(cdn['User-Agent'], contains('Android'));

      // 直连（没配中转）：任何地址都给手机 UA
      final direct = ComicOnlineService(
        target: FakeComicTarget(),
        source: yeman,
      );
      expect(
        direct.headersFor('https://tuer.justpic01pt.com:666/a.jpg')['User-Agent'],
        contains('Android'),
      );

      // 不配 relay 的源（包子）：空表（那条老路用不上请求头）
      final plain = ComicOnlineService(
        target: FakeComicTarget(),
        source: ComicSource.tryParse(kSeedComicSourceJson)!,
      );
      expect(plain.headersFor('https://tuer.justpic01pt.com:666/a.jpg'), isEmpty);
    });
  });
}

// ── 假中转（不联网） ────────────────────────────────────────────────

const String _relayEndpoint = 'https://box.hpa888.top/comicrelay/fetch';
const String _relayToken = 'tok-test-relay';

const Map<String, String> _jsonUtf8 = {
  'content-type': 'application/json; charset=utf-8',
};
const Map<String, String> _htmlUtf8 = {
  'content-type': 'text/html; charset=utf-8',
};

/// 假中转：GET 按 `u` 里的路径回答，POST 取图接口按 offset 分批。
/// 记录每次请求，便于断言"offset 递增"和"一共取了几批"。
class FakeComicRelay {
  FakeComicRelay({
    this.searchHtml = '',
    this.bookHtml = '',
    this.chapterHtml = '',
    this.total = 10,
    this.failFirstPost = false,
  });

  final String searchHtml;
  final String bookHtml;
  final String chapterHtml;

  /// 站点自报的总张数（取图接口的 `total`）。
  final int total;

  /// 第一批取图就 502（验"第几批失败"能不能报出来）。
  final bool failFirstPost;

  /// GET 全失败（验"不会悄悄退回老路"）。
  bool failGet = false;

  /// 每次 GET 的原始地址（`u` 参数）。
  final List<String> getTexts = [];

  /// 每批取图表单（`id`/`aid`/`offset`）。
  final List<Map<String, String>> postForms = [];

  /// 站点**一次最多给几张**（真实站点是 10：`limit: 10` 是能要到的上限）。
  static const int batch = 10;

  ComicRelay client() => ComicRelay(
    endpoint: _relayEndpoint,
    token: _relayToken,
    client: MockClient(_handle),
  );

  Future<http.Response> _handle(http.Request req) async {
    final u = req.url.queryParameters['u'] ?? '';
    if (req.method == 'POST') {
      postForms.add(req.bodyFields);
      return _picsJson(req.bodyFields);
    }
    getTexts.add(u);
    if (failGet) {
      return http.Response(
        jsonEncode({'error': '取不到（URLError）'}),
        502,
        headers: _jsonUtf8,
      );
    }
    if (u.contains('/search')) {
      return http.Response(searchHtml, 200, headers: _htmlUtf8);
    }
    if (u.contains('/book/')) {
      return http.Response(bookHtml, 200, headers: _htmlUtf8);
    }
    if (u.contains('/chapter/')) {
      return http.Response(chapterHtml, 200, headers: _htmlUtf8);
    }
    return http.Response(
      jsonEncode({'error': '不认识的地址'}),
      404,
      headers: _jsonUtf8,
    );
  }

  /// 取图接口的响应（直连与中转共用一份，免得两处各自演化）。
  http.Response _picsJson(Map<String, String> form) {
    if (failFirstPost && postForms.length == 1) {
      return http.Response(
        jsonEncode({'error': '取不到（URLError）'}),
        502,
        headers: _jsonUtf8,
      );
    }
    final offset = int.tryParse(form['offset'] ?? '') ?? 0;
    // 站点认 `limit`（上限 10）：我们要 10 张就给 10 张，别写死 5 —— 一整话 209 张
    // 因此从 42 次往返降到 21 次。
    final want = int.tryParse(form['limit'] ?? '') ?? batch;
    final cap = want < batch ? want : batch;
    final n = (total - offset).clamp(0, cap).toInt();
    return http.Response(
      jsonEncode({
        'data': {
          'pic': [
            for (var i = 0; i < n; i++)
              {
                'pic': 'https://tuer.justpic01pt.com:666/p/${offset + i}.jpg',
                'id': '${offset + i}',
              },
          ],
          'offset': offset,
          'limit': cap,
          'total': total,
        },
      }),
      200,
      headers: _jsonUtf8,
    );
  }

  /// 直连的假客户端：请求**直接打在站点地址上**（没有 `u` 参数），按路径回答。
  ///
  /// 顺手记下每次请求的 UA —— 直连不带手机 UA 就会被站点 307 掉，这条得能测出来。
  final List<String> directUserAgents = [];

  http.Client directClient() => MockClient(_handleDirect);

  Future<http.Response> _handleDirect(http.Request req) async {
    directUserAgents.add(req.headers['User-Agent'] ?? '');
    if (req.method == 'POST') {
      postForms.add(req.bodyFields);
      return _picsJson(req.bodyFields);
    }
    final path = req.url.path;
    if (path.contains('/search')) {
      return http.Response(searchHtml, 200, headers: _htmlUtf8);
    }
    if (path.contains('/book/')) {
      return http.Response(bookHtml, 200, headers: _htmlUtf8);
    }
    if (path.contains('/chapter/')) {
      return http.Response(chapterHtml, 200, headers: _htmlUtf8);
    }
    return http.Response(
      jsonEncode({'error': '不认识的地址'}),
      404,
      headers: _jsonUtf8,
    );
  }
}

// ── 站点页面的真实形状（照 2026-09-28 实测的 HTML 写，规则改了这里就会红） ──

/// 分类页和搜索页是**同一套卡片**（同一天实测的 HTML），起个名字用在分类用例里。
const String _yemanListHtml = _yemanSearchHtml;

const String _yemanSearchHtml = '''
<html><body>
<ul class="comic-sort col3" id="js_comicSortList">
  <li class="item comic-item">
    <a href="/book/7530/" title="海贼王~,海贼王~漫画">
      <div class="thumbnail"><img class="img" src="https://tuer.justpic01pt.com:666/picbed/CPMH/haizeiwang/a.jpg" alt="海贼王~"><span class="chapter">第1193话</span></div>
      <p class="title">海贼王~</p>
    </a>
  </li>
  <li class="item comic-item">
    <a href="/book/70174/" title="海贼王剧场版">
      <div class="thumbnail"><img class="img" src="https://tuer.justpic01pt.com:666/picbed/CPMH/red/b.jpg" alt="海贼王剧场版"></div>
      <p class="title">海贼王剧场版</p>
    </a>
  </li>
</ul>
</body></html>''';

const String _yemanBookHtml = '''
<html><body>
<div class="header-center top-title js_top_title"><h1 id="js_comic-title" class="header-title">海贼王~</h1></div>
<div id="detail" class="comic-header js_comic_header">
  <div class="comic-info">
    <div class="book-name"><h1 class="name">海贼王~<span class="author">尾田栄一郎</span></h1></div>
    <div class="book-cover comic-item">
      <div class="thumbnail"><img src="https://tuer.justpic01pt.com:666/picbed/CPMH/haizeiwang/cover.jpg" alt="海贼王~漫画"></div>
    </div>
  </div>
  <div class="intro-text"><p id="js_desc_content" class="intro-text-wrapper">拥有财富…大秘宝“ONE PIECE”，无数海贼扬起旗帜。</p></div>
  <div class="chapter-list" id="js_chapter_list">
    <ul id="js_chapters">
      <li class="comic-chapter-item" data-index="1"><a class="comic-chapter-link" href="/chapter/7530/772668.html" title="1卷">1卷</a></li>
      <li class="comic-chapter-item" data-index="2"><a class="comic-chapter-link" href="/chapter/7530/772669.html" title="2卷">2卷</a></li>
    </ul>
  </div>
</div>
</body></html>''';

String _yemanChapterHtml({required int total}) =>
    '''<html><body><script>
let read={aid:'7530',cid:'772668',apiCid:'772668',picCount:$total,articlename:'海贼王~',chaptername:'1卷',url:'/book/7530/'}
</script></body></html>''';

