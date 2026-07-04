import 'package:box/novel/core/rules/rule_engine_v2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RuleEngineV2', () {
    final engine = RuleEngineV2.defaults();

    test('resolveStringRule: base path', () {
      final ctx = {'title': '  Hello World  '};
      expect(engine.resolveStringRule(r'{{$.title}}', context: ctx, root: ctx), 'Hello World');
    });

    test('resolveStringRule: regex replacement', () {
      final ctx = {'title': 'Chapter 1: The Beginning'};
      expect(
        engine.resolveStringRule(r'{{$.title}}##Chapter\s+\d+:\s*##',
            context: ctx, root: ctx),
        'The Beginning',
      );
    });

    test('resolveStringRule: empty input', () {
      expect(engine.resolveStringRule('', context: {}, root: {}), '');
    });

    test('resolveStringRule: js eval placeholder strips suffix', () {
      final ctx = {'text': 'abc'};
      // @js: 后缀会被剥离，base 部分正常解析
      expect(
        engine.resolveStringRule(r'{{$.text}}@js:{{$.text}}',
            context: ctx, root: ctx),
        'abc',
      );
    });

    test('resolveDynamic: map lookup', () {
      final root = {'data': {'id': 123}};
      expect(engine.resolveDynamic('data.id', context: root, root: root), 123);
    });

    test('resolveDynamic: vars fallback', () {
      expect(
        engine.resolveDynamic('keyword', context: {}, root: {}, vars: {'keyword': 'abc'}),
        'abc',
      );
    });

    test('resolveDynamic: rule expr returns empty', () {
      final root = {'a': 1};
      expect(engine.resolveDynamic('@js:', context: root, root: root), '');
    });

    test('findMaps: filter nested', () {
      final root = {
        'list': [
          {'name': 'A', 'v': 1},
          {'name': 'B', 'v': 2},
          {'x': 1},
        ]
      };
      final result = engine.findMaps(root, (m) => m.containsKey('name'));
      expect(result.length, 2);
      expect(result[0]['name'], 'A');
      expect(result[1]['name'], 'B');
    });
  });
}
