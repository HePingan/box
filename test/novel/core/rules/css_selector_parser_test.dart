import 'package:flutter_test/flutter_test.dart';
import 'package:box/novel/core/rules/css_selector_parser.dart';

void main() {
  group('CssSelectorParser — 索引语法', () {
    const html = '''
<div class="book-list">
  <ul>
    <li class="item">第一本：斗罗大陆</li>
    <li class="item">第二本：斗破苍穹</li>
    <li class="item">第三本：凡人修仙传</li>
  </ul>
</div>
<div class="info">
  <span class="author">唐家三少</span>
  <span class="author">天蚕土豆</span>
  <span class="year">2024</span>
</div>
''';

    test('tag.span.0 选中第一个 span', () {
      final result = CssSelectorParser.parse('class.info@tag.span.0@text', html);
      expect(result, '唐家三少');
    });

    test('tag.span.1 选中第二个 span', () {
      final result = CssSelectorParser.parse('class.info@tag.span.1@text', html);
      expect(result, '天蚕土豆');
    });

    test('tag.li.0 选中第一个 li', () {
      final result = CssSelectorParser.parse('class.book-list@tag.li.0@text', html);
      expect(result, '第一本：斗罗大陆');
    });

    test('tag.li.2 选中第三个 li', () {
      final result = CssSelectorParser.parse('class.book-list@tag.li.2@text', html);
      expect(result, '第三本：凡人修仙传');
    });

    test('索引越界返回 null', () {
      final result = CssSelectorParser.parse('class.book-list@tag.li.99@text', html);
      expect(result, isNull);
    });

    test('纯索引 .0 选择第一个候选', () {
      final result = CssSelectorParser.parse('class.book-list@tag.li@.0@text', html);
      expect(result, '第一本：斗罗大陆');
    });

    test('class.item.0 语法也支持', () {
      final result = CssSelectorParser.parse('class.item.0@text', html);
      expect(result, '第一本：斗罗大陆');
    });

    test('复合规则含 src + 索引', () {
      const imgHtml = '''
<div class="cover">
  <img src="http://example.com/1.jpg" />
  <img src="http://example.com/2.jpg" />
</div>
''';
      final result = CssSelectorParser.parse('class.cover@tag.img.1@src', imgHtml);
      expect(result, 'http://example.com/2.jpg');
    });
  });

  group('CssSelectorParser — 基础功能', () {
    test('text 提取', () {
      const html = '<div class="title">斗罗大陆</div>';
      final result = CssSelectorParser.parse('class.title@text', html);
      expect(result, '斗罗大陆');
    });

    test('href 提取', () {
      const html = '<a class="book-link" href="/book/1/">斗罗大陆</a>';
      final result = CssSelectorParser.parse('class.book-link@href', html);
      expect(result, '/book/1/');
    });

    test('空规则返回 null', () {
      expect(CssSelectorParser.parse('', '<div></div>'), isNull);
    });
  });
}
