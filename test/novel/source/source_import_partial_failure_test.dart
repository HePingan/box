import 'package:box/novel/pages/source_manager/book_source_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归：批量导入书源时，单个畸形条目不得让整批静默失败。
///
/// 缺陷（book_source_manager.dart:_parseSources）：`.map(fromJson)` 是懒惰求值，
/// 某一条 fromJson 抛异常会被外层 `catch (_)` 吞掉，整个 JSON 数组随即掉进
/// 「按段解析」兜底路径并解析出 0 条 —— 用户导入 50 个源，因为第 3 个字段畸形
/// 导致一个都没进，界面上还没有任何提示。
void main() {
  group('书源批量导入的部分失败容错', () {
    test('数组中夹一个畸形条目，其余仍应成功导入（核心回归）', () {
      const text = '''
[
  {"bookSourceUrl":"http://a.com","bookSourceName":"源A"},
  {"bookSourceUrl":12345,"bookSourceName":{"bad":"type"}},
  {"bookSourceUrl":"http://c.com","bookSourceName":"源C"}
]
''';
      final sources = BookSourceManager.parseSources(text);
      final urls = sources.map((e) => e.bookSourceUrl).toList();

      expect(urls, containsAll(<String>['http://a.com', 'http://c.com']),
          reason: '好的条目必须入库，实际: $urls');
      expect(sources.length, greaterThanOrEqualTo(2));
    });

    test('全部合法时全部导入', () {
      const text = '''
[
  {"bookSourceUrl":"http://a.com","bookSourceName":"源A"},
  {"bookSourceUrl":"http://b.com","bookSourceName":"源B"}
]
''';
      expect(BookSourceManager.parseSources(text).length, 2);
    });

    test('单对象 JSON 正常导入', () {
      const text = '{"bookSourceUrl":"http://a.com","bookSourceName":"源A"}';
      expect(BookSourceManager.parseSources(text).length, 1);
    });

    test('完全非 JSON 文本不抛异常', () {
      expect(() => BookSourceManager.parseSources('这不是 JSON'), returnsNormally);
    });

    test('空输入返回空列表', () {
      expect(BookSourceManager.parseSources(''), isEmpty);
      expect(BookSourceManager.parseSources('   '), isEmpty);
    });
  });
}
