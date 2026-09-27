// 在线服务的用例：搜索 / 详情目录 / 章节取图。
//
// 不联网、不起 WebView：假目标按**引擎真实返回的形状**回答（Android 会再编码一层，
// 这里走 androidEncode，与真机见到的形状一致）。
library;

import 'package:flutter_test/flutter_test.dart';

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
      expect(fake.opened.single, contains('/search?q='));
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
}
