import 'package:flutter_test/flutter_test.dart';
import 'package:box/novel/core/rule_engine.dart';

void main() {
  group('RuleEngine compat facade', () {
    // 验证旧 static API 仍然可用且正确委托到 RuleEngineV2

    group('URL 工具方法', () {
      test('normalizeBaseUrlInput adds https scheme', () {
        // 注意：normalizeBaseUrlInput 不删除末尾斜杠
        expect(
            RuleEngine.normalizeBaseUrlInput('example.com'), 'https://example.com');
      });

      test('normalizeBaseUrlInput keeps http/https prefix', () {
        expect(RuleEngine.normalizeBaseUrlInput('https://example.com/'),
            'https://example.com/');
        expect(RuleEngine.normalizeBaseUrlInput('http://test.com'),
            'http://test.com');
      });

      test('normalizeBaseUrlInput handles empty input', () {
        expect(RuleEngine.normalizeBaseUrlInput(''), '');
      });

      test('isAbsoluteUrl returns true for http/https URLs', () {
        expect(RuleEngine.isAbsoluteUrl('https://example.com/page'), true);
        expect(RuleEngine.isAbsoluteUrl('http://test.com'), true);
      });

      test('isAbsoluteUrl returns false for relative paths', () {
        expect(RuleEngine.isAbsoluteUrl('/path/to/page'), false);
        expect(RuleEngine.isAbsoluteUrl('relative/path'), false);
      });

      test('looksLikeRuleExpr detects JSONPath expressions', () {
        expect(RuleEngine.looksLikeRuleExpr(r'$.data'), true);
        expect(RuleEngine.looksLikeRuleExpr(r'$..title'), true);
        expect(RuleEngine.looksLikeRuleExpr(r'$.list[*].name'), true);
        expect(RuleEngine.looksLikeRuleExpr('@result'), true);
      });

      test('looksLikeRuleExpr returns false for plain text', () {
        expect(RuleEngine.looksLikeRuleExpr('hello world'), false);
        expect(RuleEngine.looksLikeRuleExpr('https://example.com'), false);
      });

      test('absUrl converts relative to absolute with base', () {
        final result = RuleEngine.absUrl(
          '/path/to/page',
          defaultBaseUrl: 'https://example.com',
        );
        expect(result, 'https://example.com/path/to/page');
      });

      test('absUrl keeps absolute URLs unchanged', () {
        final result = RuleEngine.absUrl(
          'https://other.com/page',
          defaultBaseUrl: 'https://example.com',
        );
        expect(result, 'https://other.com/page');
      });

      test('toAbsoluteUrl with base overrides defaultBaseUrl', () {
        final result = RuleEngine.toAbsoluteUrl(
          '/page',
          base: 'https://base.com',
          defaultBaseUrl: 'https://default.com',
        );
        expect(result, 'https://base.com/page');
      });
    });

    group('JSON 工具方法', () {
      test('tryDecodeJson parses valid JSON string', () {
        final result = RuleEngine.tryDecodeJson('{"key": "value", "num": 42}');
        expect(result, isA<Map>());
        expect(result['key'], 'value');
        expect(result['num'], 42);
      });

      test('tryDecodeJson returns null for invalid JSON', () {
        final result = RuleEngine.tryDecodeJson('not json');
        expect(result, isNull);
      });

      test('asMap returns map for valid Map input', () {
        final result = RuleEngine.asMap({'a': 1});
        expect(result, {'a': 1});
      });

      test('asMap returns empty map for non-map input', () {
        // asMap 对非 Map 输入返回空 Map（非抛出异常）
        expect(RuleEngine.asMap('string'), <String, dynamic>{});
        expect(RuleEngine.asMap(42), <String, dynamic>{});
        expect(RuleEngine.asMap(null), <String, dynamic>{});
      });

      test('parseHeader handles map input', () {
        final result = RuleEngine.parseHeader({
          'User-Agent': 'test/1.0',
          'Referer': 'https://example.com',
        });
        expect(result, {
          'User-Agent': 'test/1.0',
          'Referer': 'https://example.com',
        });
      });

      test('parseHeader handles string input (JSON)', () {
        final result = RuleEngine.parseHeader(
          '{"User-Agent": "test/1.0"}',
        );
        expect(result, {'User-Agent': 'test/1.0'});
      });

      test('parseHeader handles empty/null input', () {
        expect(RuleEngine.parseHeader(null), isEmpty);
        expect(RuleEngine.parseHeader(''), isEmpty);
      });
    });

    group('resolveStringRule', () {
      test('returns plain text unchanged as literal string', () {
        final result = RuleEngine.resolveStringRule(
          'hello',
          context: {},
          root: {},
        );
        expect(result, 'hello');
      });

      test('resolves {{ path }} expression from context', () {
        final result = RuleEngine.resolveStringRule(
          'Title: {{ title }}',
          context: {'title': '测试小说'},
          root: {},
        );
        expect(result, 'Title: 测试小说');
      });

      test('resolves nested path with dollar prefix', () {
        final data = {
          'book': {'title': '嵌套测试'},
        };
        final result = RuleEngine.resolveStringRule(
          'Book: {{ \$.book.title }}',
          context: data,
          root: data,
        );
        expect(result, 'Book: 嵌套测试');
      });

      test('returns empty for unresolvable expression', () {
        final result = RuleEngine.resolveStringRule(
          '{{ nonexistent }}',
          context: {},
          root: {},
        );
        expect(result, '');
      });
    });

    group('cleanText / cleanChapterTitle', () {
      test('cleanText collapses whitespace', () {
        // cleanText 不专门去除 HTML 标签，只折叠空白
        expect(
          RuleEngine.cleanText('  Hello   World  '),
          'Hello World',
        );
      });

      test('cleanText preserves inline HTML tags', () {
        // HTML 标签不被去除，只是空白被折叠
        final result = RuleEngine.cleanText('<p>Hello</p>');
        expect(result, '<p>Hello</p>');
      });

      test('cleanText returns empty for null/empty', () {
        expect(RuleEngine.cleanText(null), '');
        expect(RuleEngine.cleanText(''), '');
      });

      test('cleanChapterTitle removes volume prefixes', () {
        expect(
          RuleEngine.cleanChapterTitle('正文卷.第一章 开始'),
          '第一章 开始',
        );
      });

      test('cleanChapterTitle removes vote/update markers', () {
        final cleaned = RuleEngine.cleanChapterTitle('第一章 测试（求票）');
        expect(cleaned.contains('求票'), false);
        expect(cleaned.contains('（求票）'), false);
      });

      test('cleanChapterTitle returns empty for null/empty', () {
        expect(RuleEngine.cleanChapterTitle(null), '');
        expect(RuleEngine.cleanChapterTitle(''), '');
      });
    });

    group('extractPath / findMaps', () {
      test('extractPath with dollar prefix returns nested field', () {
        final data = {
          'data': {'title': '测试标题'},
        };
        final result = RuleEngine.extractPath(data, r'$.data.title');
        expect(result, '测试标题');
      });

      test('extractPath with [*] returns the array', () {
        // [*] 通配符返回数组本身（不继续投影）
        final data = {
          'data': [
            {'id': 1, 'name': 'item1'},
            {'id': 2, 'name': 'item2'},
          ],
        };
        final result = RuleEngine.extractPath(data, r'$.data[*]');
        expect(result, isA<List>());
        expect((result as List).length, 2);
      });

      test('extractPath with @ prefix works', () {
        final data = {
          'result': [1, 2, 3],
        };
        final result = RuleEngine.extractPath(data, r'@.result');
        expect(result, [1, 2, 3]);
      });

      test('findMaps searches recursively', () {
        final data = [
          {'type': 'a', 'val': 1},
          {'type': 'b', 'val': 2},
          {'type': 'a', 'val': 3},
        ];
        final found = RuleEngine.findMaps(
          data,
          (m) => m['type'] == 'a',
        );
        expect(found.length, 2);
        expect(found[0]['val'], 1);
        expect(found[1]['val'], 3);
      });
    });

    group('正则替换', () {
      test('applyRegexReplacement replaces pattern', () {
        final result = RuleEngine.applyRegexReplacement(
          'hello world foo bar',
          r'world',
          'there',
        );
        expect(result, 'hello there foo bar');
      });

      test('applyRegexReplacement supports regex patterns', () {
        final result = RuleEngine.applyRegexReplacement(
          'hello 123 world 456',
          r'\d+',
          'NUM',
        );
        expect(result, 'hello NUM world NUM');
      });

      test('applyRegexReplacement returns original for empty pattern', () {
        final result = RuleEngine.applyRegexReplacement(
          'hello world',
          '',
          'replacement',
        );
        expect(result, 'hello world');
      });
    });

    group('常量检查', () {
      test('timeout is 15 seconds', () {
        expect(RuleEngine.timeout, const Duration(seconds: 15));
      });

      test('htmlTag regex can be used externally', () {
        expect(RuleEngine.htmlTag.hasMatch('<div>'), true);
        expect(RuleEngine.htmlTag.hasMatch('plain text'), false);
      });
    });
  });
}
