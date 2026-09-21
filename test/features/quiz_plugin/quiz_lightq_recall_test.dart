import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:flutter_test/flutter_test.dart';

const bankStem = '驾驶机动车不按规定使用灯光的，一次记3分。';

QuizBankItem _item(String question) => QuizBankItem(
  id: 'q_7gZgweMXMRQd',
  question: question,
  type: QuizQuestionType.trueFalse,
  options: const ['正确', '错误'],
  correctAnswer: '错误',
  category: '驾驶理论题库-20260719',
);

void main() {
  test('真实题干：cleanForMatch 后精确索引应能命中', () {
    final bankKey = QuizBankTextNormalizer.cleanForMatch(bankStem);
    final ocrKey = QuizBankTextNormalizer.cleanForMatch(bankStem);
    // ignore: avoid_print
    print('bankKey="$bankKey" ocrKey="$ocrKey" equal=${bankKey == ocrKey}');
    final cache = QuizBankCache.forTesting([_item(bankStem)]);
    final hits = cache.candidatesFor(ocrKey);
    // ignore: avoid_print
    print('hits=${hits.length}');
    expect(hits, isNotEmpty, reason: '库中同题必须召回');
  });

  test('OCR 丢失句号时也应命中（token 兜底）', () {
    const ocrNoDot = '驾驶机动车不按规定使用灯光的，一次记3分';
    final ocrKey = QuizBankTextNormalizer.cleanForMatch(ocrNoDot);
    final cache = QuizBankCache.forTesting([_item(bankStem)]);
    final hits = cache.candidatesFor(ocrKey);
    // ignore: avoid_print
    print('noDot ocrKey="$ocrKey" hits=${hits.length}');
    expect(hits, isNotEmpty);
  });

  test('带读屏 chrome 前缀时也应命中', () {
    const ocrWithChrome = '倒计时41:12\n驾驶机动车不按规定使用灯光的，一次记3分。\nA 正确\nB 错误';
    final ocrKey = QuizBankTextNormalizer.cleanForMatch(ocrWithChrome);
    final cache = QuizBankCache.forTesting([_item(bankStem)]);
    final hits = cache.candidatesFor(ocrKey);
    // ignore: avoid_print
    print('chrome ocrKey="$ocrKey" hits=${hits.length}');
    expect(hits, isNotEmpty);
  });
}
