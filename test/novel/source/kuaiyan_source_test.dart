import 'package:flutter_test/flutter_test.dart';
import 'package:box/novel/core/kuaiyan_novel_source.dart';
import 'package:box/novel/core/models.dart';
import 'package:box/novel/core/rules/css_selector_parser.dart';

void main() {
  group('KuaiYanNovelSource', () {
    late KuaiYanNovelSource source;

    setUp(() {
      source = KuaiYanNovelSource(
        name: '快眼看书（优+）',
        baseUrl: 'http://www.xbotaodz.com',
        searchUrl: '/search.html?keyword={{key}}',
        exploreUrl: '/category.html',
        ruleSearch: {
          'bookList': 'class.novel-list@tag.li',
          'name': 'class.name@text',
          'author': 'class.author@text',
          'coverUrl': 'class.pic@tag.img@src',
          'bookUrl': 'class.name@tag.a@href',
          'lastChapter': 'class.update@text',
        },
        ruleBookInfo: {
          'name': 'class.novelinfo-l@text',
          'author': 'class.name@text',
          'intro': 'class.intro@text',
          'coverUrl': 'class.pic@tag.img@src',
        },
        ruleToc: {
          'chapterList': 'class.chapter-list@tag.a',
        },
        ruleContent: {
          'content': 'id.chaptercontent@textNodes',
        },
      );
    });

    test('supportsBookSourceJson 正确识别', () {
      expect(KuaiYanNovelSource.supportsBookSourceJson({
        'bookSourceUrl': 'http://www.xbotaodz.com/api',
        'bookSourceName': '快眼看书（优+）',
      }), isTrue);

      expect(KuaiYanNovelSource.supportsBookSourceJson({
        'bookSourceUrl': 'https://example.com',
        'bookSourceName': '普通书源',
      }), isFalse);
    });

    test('CssSelectorParser 基础选择', () {
      const html = '''
        <div class="novel-list">
          <li>
            <a href="/book/123" class="name">斗破苍穹</a>
            <span class="author">天蚕土豆</span>
            <img class="pic" src="//img.example.com/1.jpg" />
          </li>
          <li>
            <a href="/book/456" class="name">完美世界</a>
          </li>
        </div>
      ''';

      expect(
        CssSelectorParser.parse('class.novel-list@tag.li@class.name@text', html),
        '斗破苍穹\n完美世界',
      );
    });

    test('CssSelectorParser 多段选择（index 筛选）', () {
      const html = '''
        <ul>
          <li class="item"><a href="/a">A</a></li>
          <li class="item"><a href="/b">B</a></li>
          <li class="item"><a href="/c">C</a></li>
        </ul>
      ''';

      expect(
        CssSelectorParser.parse('class.item@.1@tag.a@href', html),
        '/b',
      );
    });

    test('CssSelectorParser textNodes 提取', () {
      const html = '''
        <div id="chaptercontent">
          <p>第一章</p>
          <p>这是正文内容。</p>
        </div>
      ''';

      expect(
        CssSelectorParser.parse('id.chaptercontent@textNodes', html),
        '第一章\n\n这是正文内容。',
      );
    });

    test('CssSelectorParser 降级处理空规则', () {
      expect(CssSelectorParser.parse('', '<html></html>'), isNull);
      expect(CssSelectorParser.parse('@text', '<p>hello</p>'), 'hello');
    });

    test('KuaiYanNovelSource 基础字段', () {
      expect(source.name, '快眼看书（优+）');
      expect(source.baseUrl, 'http://www.xbotaodz.com');
      expect(source.headers.containsKey('User-Agent'), isTrue);
    });

    test('KuaiYanNovelSource fromBookSourceJson', () {
      final src = KuaiYanNovelSource.fromBookSourceJson({
        'bookSourceName': '快眼看书(yk)',
        'bookSourceUrl': 'http://www.xbotaodz.com',
        'searchUrl': '/search.html?keyword={{key}}',
        'exploreUrl': '/category.html',
        'ruleSearch': {'name': 'class.title@text'},
        'header': {'Authorization': 'Bearer xyz'},
      });

      expect(src.name, '快眼看书(yk)');
      expect(src.headers['Authorization'], 'Bearer xyz');
    });

    test('KuaiYanNovelSource fetchByPath 空路径保护', () async {
      final books = await source.fetchByPath('');
      expect(books, isEmpty);
    });

    test('KuaiYanNovelSource fetchChapter 索引越界', () async {
      final detail = NovelDetail(
        book: NovelBook(id: '1', title: 'T', author: '', intro: '', coverUrl: '', detailUrl: ''),
        chapters: const [NovelChapter(title: '1', url: '/ch/1')],
      );

      final result = await source.fetchChapter(
        detail: detail,
        chapterIndex: 5,
      );

      expect(result.content, '章节索引越界');
      expect(result.chapterIndex, 5);
    });
  });
}
