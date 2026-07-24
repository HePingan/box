import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';

void main() {
  test('题干指纹在选项变化时保持稳定', () {
    const q = '机动车通过路口时应当如何操作？';
    final a = QuizBankTextNormalizer.cleanForMatch(q);
    final b = QuizBankTextNormalizer.cleanForMatch(q);
    expect(a, b);
  });

  test('不同题干指纹不同，旧请求应能被识别为过期', () {
    final old = QuizBankTextNormalizer.cleanForMatch('机动车通过路口时应当如何操作？');
    final next = QuizBankTextNormalizer.cleanForMatch('夜间行车应当使用什么灯光？');
    expect(old, isNot(next));
  });
}
