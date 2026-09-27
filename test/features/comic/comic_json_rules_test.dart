// JSON 规则子集的用例（书源的 ruleExplore 走的是 JSON 接口，不是网页）。
//
// 重点不是"能取到"，而是**取不到时能说清**：规则不认识 / 字段不存在 / 类型不对，
// 三种都要报错，绝不静默返回空串（静默返回空在真机上就是"没有结果"，会把人带偏）。
library;

import 'package:box/features/comic/domain/comic_json_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JSON 规则：取值', () {
    const data = {
      'items': [
        {'comic_id': 'abc', 'name': '航海王', 'author': '尾田荣一郎', 'topic_img': 'a.jpg'},
        {'comic_id': 'def', 'name': '海贼王yellow', 'type_names': ['少年', '热血']},
      ],
    };

    test(r'$.items[*] 取列表；$[0] 取第几个；$.a.b 取嵌套字段', () {
      expect(comicJsonList(data, r'$.items[*]').length, 2);
      expect(comicJsonPick(data, r'$.items[0].name'), '航海王');
      expect(comicJsonPick(data, r'$.items[1].comic_id'), 'def');
    });

    test('不是列表时如实报错（附实际类型）', () {
      expect(
        () => comicJsonList(data, r'$.items[0].name'),
        throwsA(isA<ComicJsonRuleException>()),
      );
    });

    test('字段不存在 / 不是 \$ 开头 / 括号没闭合，三种都报错', () {
      expect(
        () => comicJsonPick(data, r'$.items[0].nope'),
        throwsA(
          isA<ComicJsonRuleException>().having(
            (e) => e.message,
            'message',
            contains('没有字段'),
          ),
        ),
      );
      expect(
        () => comicJsonPick(data, 'items[0]'),
        throwsA(
          isA<ComicJsonRuleException>().having(
            (e) => e.message,
            'message',
            contains(r'$'),
          ),
        ),
      );
      expect(
        () => comicJsonPick(data, r'$.items[0'),
        throwsA(isA<ComicJsonRuleException>()),
      );
    });

    test(r'字段转文本：字符串去空格、数组用逗号连、缺失给空串', () {
      final first = comicJsonList(data, r'$.items[*]').first;
      final second = comicJsonList(data, r'$.items[*]')[1];
      expect(comicJsonFieldText(first, r'$.name'), '航海王');
      expect(comicJsonFieldText(second, r'$.type_names'), '少年,热血');
      expect(comicJsonFieldText(second, r'$.author'), '');
    });
  });

  group('JSON 模板（地址里填字段）', () {
    const item = {'comic_id': 'hanghaiwang', 'topic_img': 'x.jpg'};

    test(r'把 {{$.字段}} 填进地址', () {
      expect(
        comicTemplate(r'https://cn.baozimhcn.com/comic/{{$.comic_id}}', item),
        'https://cn.baozimhcn.com/comic/hanghaiwang',
      );
    });

    test('字段缺失就报错 —— 不拼出半个地址（半个地址点下去只会开 404）', () {
      expect(
        () => comicTemplate(r'https://x/comic/{{$.nope}}', item),
        throwsA(isA<ComicJsonRuleException>()),
      );
      expect(
        () => comicTemplate(r'https://x/comic/{{$.comic_id', item),
        throwsA(
          isA<ComicJsonRuleException>().having(
            (e) => e.message,
            'message',
            contains('没闭合'),
          ),
        ),
      );
    });

    test('没有模板的地址原样返回', () {
      expect(
        comicTemplate('https://x/comic/hanghaiwang', item),
        'https://x/comic/hanghaiwang',
      );
    });
  });

  test(r'isComicJsonRule：只有 \$ 开头才算 JSON 规则', () {
    expect(isComicJsonRule(r'$.items[*]'), isTrue);
    expect(isComicJsonRule(r'  $.name'), isTrue);
    expect(isComicJsonRule('class.comics-card@tag.a@href'), isFalse);
    expect(isComicJsonRule('<js>foo</js>'), isFalse);
  });
}
