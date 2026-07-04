import 'package:flutter_test/flutter_test.dart';
import 'package:box/novel/core/rules/css_selector_parser.dart';

void main() {
  test('debug parse', () {
    const html = '<div class="novel-list"><li><a href="/book/123" class="name">斗破苍穹</a></li></div>';
    final result = CssSelectorParser.parse('class.novel-list@class.name@text', html);
    print('result: $result');
    expect(result, isNotNull);
  });
}
