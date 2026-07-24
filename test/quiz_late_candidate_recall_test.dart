import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';

void main() {
  test('索引未命中时，后排的近似题仍会被轻量预筛选召回', () {
    final items = List.generate(
      300,
      (i) => QuizBankItem(
        id: 'item-$i',
        question: i == 299 ? '机动车在雨天路面湿滑时应当降低车速保持安全距离' : '第$i道其他驾驶规则题目内容',
        type: QuizQuestionType.singleChoice,
        options: const ['A', 'B'],
        correctAnswer: 'A',
      ),
    );
    final cache = QuizBankCache.forTesting(items);
    final candidates = cache.candidatesFor('雨天路滑应减速保持距离');
    expect(candidates.map((e) => e.id), contains('item-299'));
    expect(candidates.length, lessThanOrEqualTo(80));
  });
}
