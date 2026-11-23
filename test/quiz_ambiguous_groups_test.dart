import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:box/features/quiz_plugin/presentation/quiz_ambiguous_groups_page.dart';

QuizBankItem _item(String id, String question, String answer,
        {bool isNewRule = false}) =>
    QuizBankItem(
      id: id,
      question: question,
      type: QuizQuestionType.singleChoice,
      options: const ['甲', '乙'],
      correctAnswer: answer,
      isNewRule: isNewRule,
    );

void main() {
  test('只保留同题干且答案不止一种的组', () {
    final groups = groupAmbiguousQuestions([
      _item('1', '这个标志是何含义？', '停车点'),
      _item('2', '这个标志是何含义？', '观景台'),
      _item('3', '普通题', '甲'),
      _item('4', '普通题', '甲'),
      _item('5', '', '甲'),
    ]);
    expect(groups.length, 1);
    expect(groups.single.items.length, 2);
    expect(groups.single.answerCount, 2);
  });

  test('歧义组按题目数量降序，最大组排最前', () {
    final groups = groupAmbiguousQuestions([
      _item('a1', '小歧义', '甲'),
      _item('a2', '小歧义', '乙'),
      _item('b1', '大歧义', '甲'),
      _item('b2', '大歧义', '乙'),
      _item('b3', '大歧义', '丙'),
    ]);
    expect(groups.first.stem, contains('大歧义'));
    expect(groups.first.items.length, 3);
  });

  test('新规标记不参与分组，补标不会让组消失', () {
    final groups = groupAmbiguousQuestions([
      _item('1', '货车超限记几分？', '1分', isNewRule: true),
      _item('2', '货车超限记几分？', '6分'),
    ]);
    expect(groups.length, 1);
    expect(groups.single.items.where((e) => e.isNewRule).length, 1);
  });
}
