import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';

void main() {
  group('UniqueQuizKeyGenerator', () {
    test('同题干不同选项 → 不同 id', () {
      const q = '驾驶这种机动车上路行驶属于什么行为?';
      final id1 = UniqueQuizKeyGenerator.key(
        q,
        options: ['违规行为', '违章行为', '违法行为', '犯罪行为'],
      );
      final id2 = UniqueQuizKeyGenerator.key(
        q,
        options: ['正确', '错误'],
      );
      expect(id1, isNot(equals(id2)));
    });

    test('同题干同选项（顺序不同）→ 同一 id', () {
      const q = '以下说法正确的是？';
      final id1 = UniqueQuizKeyGenerator.key(
        q,
        options: ['A', 'B', 'C'],
      );
      final id2 = UniqueQuizKeyGenerator.key(
        q,
        options: ['C', 'A', 'B'],
      );
      expect(id1, equals(id2));
    });

    test('同题干同选项 → 覆盖同一 id', () {
      const q = '测试题';
      final opts = ['甲', '乙'];
      final a = UniqueQuizKeyGenerator.key(q, options: opts);
      final b = UniqueQuizKeyGenerator.key(q, options: opts);
      expect(a, equals(b));
    });
  });
}
