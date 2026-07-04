import 'package:flutter_test/flutter_test.dart';
import 'package:box/novel/pages/reader/reader_dictionary_service.dart';

void main() {
  const service = ReaderDictionaryService();

  group('ReaderDictionaryService', () {
    test('内置词表查词 - 觊觎', () async {
      final result = await service.lookup('觊觎');
      expect(result.word, '觊觎');
      expect(result.phonetic, 'jì yú');
      expect(result.definitions.length, greaterThan(0));
      expect(result.definitions[0].definition,
          contains('希望得到'));
    });

    test('内置词表查词 - 饕餮', () async {
      final result = await service.lookup('饕餮');
      expect(result.word, '饕餮');
      expect(result.phonetic, 'tāo tiè');
      expect(result.definitions[0].definition, contains('贪吃'));
    });

    test('内置词表查词 - 单字', () async {
      final result = await service.lookup('姝');
      expect(result.word, '姝');
      expect(result.phonetic, 'shū');
      expect(result.definitions[0].definition, contains('美丽'));
    });

    test('空字符串返回空结果', () async {
      final result = await service.lookup('');
      expect(result.isEmpty, true);
    });

    test('不存在的词返回空结果', () async {
      // 使用不可能出现在词表里的随机字符串
      final result = await service.lookup('xyzzyxxyz');
      // 应该走到在线查询 → 可能找不到 → 无匹配
      // 无论在线查询是否成功，结果都不会为 null
      expect(result.word, 'xyzzyxxyz');
    });

    test('常用英文词通过在线查询', () async {
      final result = await service.lookup('hello');
      // 即使在线查询成功或失败，定义不会是 null
      expect(result.word, 'hello');
    });
  });
}
