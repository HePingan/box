import 'package:box/features/dictionary/dictionary_manager.dart';
import 'package:box/features/dictionary/models/dictionary_definition.dart';
import 'package:box/features/dictionary/models/dictionary_source.dart';
import 'package:box/features/dictionary/sources/built_in_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// 可计数的假词典源：用于验证缓存是否真的挡住了重复查询。
class _CountingSource extends DictionarySource {
  _CountingSource({
    required this.id,
    required this.name,
    Map<String, String>? words,
  }) : _words = words ?? const {};

  @override
  final String id;
  @override
  final String name;

  final Map<String, String> _words;
  int lookupCount = 0;

  @override
  Future<DictionaryDefinition> lookup(String word) async {
    lookupCount++;
    final hit = _words[word.trim()];
    if (hit == null) {
      return DictionaryDefinition(word: word.trim(), source: name);
    }
    return DictionaryDefinition(
      word: word.trim(),
      phonetic: 'ph-$hit',
      senses: [DictionarySense(definition: hit)],
      source: name,
    );
  }
}

void main() {
  group('DictionaryManager 缓存', () {
    test('同一个词第二次查询命中缓存，不再打源', () async {
      final source = _CountingSource(
        id: 's1',
        name: '源一',
        words: const {'觊觎': '希望得到'},
      );
      final manager = DictionaryManager(sources: [source]);

      final first = await manager.lookup('觊觎');
      final second = await manager.lookup('觊觎');

      expect(first.senses.single.definition, '希望得到');
      expect(second.senses.single.definition, '希望得到');
      expect(source.lookupCount, 1, reason: '第二次应命中缓存');
    });

    test('查不到的词不进缓存，下次仍会重试源', () async {
      final source = _CountingSource(id: 's1', name: '源一');
      final manager = DictionaryManager(sources: [source]);

      await manager.lookup('不存在的词');
      await manager.lookup('不存在的词');

      expect(source.lookupCount, 2, reason: '空结果不应被缓存，否则源补充词条后仍查不到');
    });

    test('空字符串直接返回空结果，不打源', () async {
      final source = _CountingSource(id: 's1', name: '源一');
      final manager = DictionaryManager(sources: [source]);

      final result = await manager.lookup('   ');

      expect(result.word, '');
      expect(result.isEmpty, isTrue);
      expect(source.lookupCount, 0);
    });

    test('clearCache 后重新打源', () async {
      final source = _CountingSource(
        id: 's1',
        name: '源一',
        words: const {'觊觎': '希望得到'},
      );
      final manager = DictionaryManager(sources: [source]);

      await manager.lookup('觊觎');
      manager.clearCache();
      await manager.lookup('觊觎');

      expect(source.lookupCount, 2);
    });

    test('setActiveSource 切换源时清缓存，避免返回旧源释义', () async {
      final a = _CountingSource(
        id: 'a',
        name: '源A',
        words: const {'词': 'A 的释义'},
      );
      final b = _CountingSource(
        id: 'b',
        name: '源B',
        words: const {'词': 'B 的释义'},
      );
      final manager = DictionaryManager(sources: [a, b], activeSource: a);

      final fromA = await manager.lookup('词');
      expect(fromA.senses.single.definition, 'A 的释义');

      manager.setActiveSource('b');
      final fromB = await manager.lookup('词');

      expect(
        fromB.senses.single.definition,
        'B 的释义',
        reason: '切源后必须走新源，不能命中旧源缓存',
      );
    });

    test('setActiveSource 传入不存在的 id 时保持原活跃源', () async {
      final a = _CountingSource(
        id: 'a',
        name: '源A',
        words: const {'词': 'A 的释义'},
      );
      final manager = DictionaryManager(sources: [a], activeSource: a);

      manager.setActiveSource('不存在');

      expect(manager.activeSource.id, 'a');
    });
  });

  group('DictionaryManager 源注册', () {
    test('register 同 id 覆盖旧源，不产生重复项', () {
      final manager = DictionaryManager(sources: [BuiltInDictionarySource()]);
      final custom1 = _CountingSource(id: 'custom', name: '自定义1');
      final custom2 = _CountingSource(id: 'custom', name: '自定义2');

      manager.register(custom1);
      manager.register(custom2);

      final customs = manager.sources.where((s) => s.id == 'custom').toList();
      expect(customs.length, 1);
      expect(customs.single.name, '自定义2');
    });

    test('register 不得把活跃源悄悄换成新注册的源', () {
      // 默认构造不显式传 activeSource，此时 activeSource 回落到 sources.first。
      final builtIn = BuiltInDictionarySource();
      final manager = DictionaryManager(sources: [builtIn]);
      expect(manager.activeSource.id, 'built_in');

      manager.register(_CountingSource(id: 'custom', name: '自定义'));

      expect(
        manager.activeSource.id,
        'built_in',
        reason: '注册新源只是添加可选项，不应改变用户当前在用的源',
      );
    });

    test('unregister 拒绝移除内置源', () {
      final manager = DictionaryManager(sources: [BuiltInDictionarySource()]);

      manager.unregister('built_in');

      expect(manager.sources.map((s) => s.id), contains('built_in'));
    });

    test('unregister 后活跃源回落到剩余源', () {
      final builtIn = BuiltInDictionarySource();
      final custom = _CountingSource(id: 'custom', name: '自定义');
      final manager = DictionaryManager(
        sources: [builtIn, custom],
        activeSource: custom,
      );

      manager.unregister('custom');

      expect(manager.sources.map((s) => s.id), isNot(contains('custom')));
      expect(manager.activeSource.id, 'built_in');
    });

    test('unregister 必须清掉该源留下的缓存', () async {
      final custom = _CountingSource(
        id: 'custom',
        name: '自定义源名',
        words: const {'词': '自定义释义'},
      );
      final replacement = _CountingSource(
        id: 'custom',
        name: '自定义源名',
        words: const {'词': '新源释义'},
      );
      final manager = DictionaryManager(
        sources: [BuiltInDictionarySource(), custom],
        activeSource: custom,
      );

      final before = await manager.lookup('词');
      expect(before.senses.single.definition, '自定义释义');

      // 注意：不能借道 setActiveSource 来验证——它内部会 _cache.clear()，
      // 会把 unregister 自身漏清缓存的问题掩盖掉。这里让 unregister 后
      // 活跃源自然回落到 built_in，直接观察缓存是否残留。
      manager.unregister('custom');
      expect(manager.activeSource.id, 'built_in');

      final after = await manager.lookup('词');
      expect(after.source, '内置词表', reason: '被移除源留下的缓存必须清掉，否则会拿已卸载源的释义回答');
      expect(after.isEmpty, isTrue, reason: '内置词表未收录「词」，应返回空结果而不是旧源的缓存');

      // 补充：重新注册同 id 的源后也不该读到陈旧释义。
      manager.register(replacement);
      manager.setActiveSource('custom');
      final rebound = await manager.lookup('词');
      expect(rebound.senses.single.definition, '新源释义');
    });

    test('sources 返回不可变视图，外部不能直接改内部列表', () {
      final manager = DictionaryManager(sources: [BuiltInDictionarySource()]);

      expect(
        () => manager.sources.add(_CountingSource(id: 'x', name: 'X')),
        throwsUnsupportedError,
      );
    });
  });

  group('BuiltInDictionarySource', () {
    test('精确匹配返回拼音与释义', () async {
      final source = BuiltInDictionarySource();

      final result = await source.lookup('觊觎');

      expect(result.word, '觊觎');
      expect(result.phonetic, 'jì yú');
      expect(result.senses.single.definition, '希望得到（不该得到的东西）');
      expect(result.source, '内置词表');
      expect(result.isEmpty, isFalse);
    });

    test('单字精确命中时返回该单字自身的读音，而非双字词的首字', () async {
      final source = BuiltInDictionarySource();

      final result = await source.lookup('曦');

      expect(result.phonetic, 'xī');
      expect(result.senses.single.definition, contains('晨光'));
    });

    test('未收录的词返回空结果但带上源名', () async {
      final source = BuiltInDictionarySource();

      final result = await source.lookup('这个词没收录');

      expect(result.word, '这个词没收录');
      expect(result.source, '内置词表');
      expect(result.isEmpty, isTrue);
    });

    test('前后空白被裁剪后仍能命中', () async {
      final source = BuiltInDictionarySource();

      final result = await source.lookup('  饕餮  ');

      expect(result.word, '饕餮');
      expect(result.phonetic, 'tāo tiè');
    });

    test('空输入返回空结果，word 为空串', () async {
      final source = BuiltInDictionarySource();

      final result = await source.lookup('');

      expect(result.word, '');
      expect(result.isEmpty, isTrue);
    });

    test('词表内每一条都是「拼音 | 释义」两段结构', () async {
      final source = BuiltInDictionarySource();
      // 抽样覆盖双字与单字两类
      for (final word in ['龃龉', '囹圄', '耄耋', '姝', '懿']) {
        final r = await source.lookup(word);
        expect(r.phonetic, isNotEmpty, reason: '$word 应有拼音');
        expect(r.senses, hasLength(1), reason: '$word 应有一条释义');
        expect(r.senses.single.definition, isNotEmpty, reason: '$word 释义非空');
        expect(
          r.senses.single.definition,
          isNot(contains(' | ')),
          reason: '$word 释义不应残留分隔符，说明拆分失败',
        );
      }
    });
  });

  group('DictionaryDefinition 序列化', () {
    test('toJson / fromJson 往返保留全部字段', () {
      const original = DictionaryDefinition(
        word: '觊觎',
        phonetic: 'jì yú',
        senses: [
          DictionarySense(
            partOfSpeech: '动',
            definition: '希望得到',
            example: '觊觎已久',
          ),
          DictionarySense(definition: '第二条释义'),
        ],
        source: '内置词表',
      );

      final restored = DictionaryDefinition.fromJson(original.toJson());

      expect(restored.word, original.word);
      expect(restored.phonetic, original.phonetic);
      expect(restored.source, original.source);
      expect(restored.senses, hasLength(2));
      expect(restored.senses.first.partOfSpeech, '动');
      expect(restored.senses.first.example, '觊觎已久');
      expect(restored.senses.last.example, isNull);
    });

    test('fromJson 容忍缺字段与 null', () {
      final restored = DictionaryDefinition.fromJson(const {});

      expect(restored.word, '');
      expect(restored.phonetic, '');
      expect(restored.senses, isEmpty);
      expect(restored.source, '');
      expect(restored.isEmpty, isTrue);
    });

    test('isEmpty 只在既无释义也无拼音时为真', () {
      const onlyPhonetic = DictionaryDefinition(word: 'x', phonetic: 'p');
      const onlySense = DictionaryDefinition(
        word: 'x',
        senses: [DictionarySense(definition: 'd')],
      );

      expect(onlyPhonetic.isEmpty, isFalse);
      expect(onlySense.isEmpty, isFalse);
      expect(const DictionaryDefinition(word: 'x').isEmpty, isTrue);
    });
  });
}
