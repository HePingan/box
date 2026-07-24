import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';

void main() {
  test('同题的节点刷新保持相同题干指纹，应受命中锁保护', () {
    final first = QuizBankTextNormalizer.cleanForMatch('机动车通过路口时应当如何操作？');
    final refresh = QuizBankTextNormalizer.cleanForMatch('机动车通过路口时应当如何操作？');
    expect(refresh, first);
  });

  test('新题干产生不同指纹，应解除旧题命中锁', () {
    final old = QuizBankTextNormalizer.cleanForMatch('机动车通过路口时应当如何操作？');
    final next = QuizBankTextNormalizer.cleanForMatch('夜间行车应当使用什么灯光？');
    expect(next, isNot(old));
  });
}
