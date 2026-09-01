import 'package:box/features/admin/domain/quiz_review_answer_match.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const options = <String>[
    '立即停车检查',
    '继续行驶',
    '减速慢行通过',
    '鸣喇叭示意',
  ];

  group('QuizReviewAnswerMatch.correctIndexes', () {
    test('答案是选项原文时命中该项', () {
      expect(
        QuizReviewAnswerMatch.correctIndexes(options: options, answer: '减速慢行通过'),
        <int>[2],
      );
    });

    test('答案是字母时命中对应序号（旧实现只比原文，字母答案一个都高亮不了）', () {
      expect(
        QuizReviewAnswerMatch.correctIndexes(options: options, answer: 'C'),
        <int>[2],
      );
      expect(
        QuizReviewAnswerMatch.correctIndexes(options: options, answer: 'a'),
        <int>[0],
      );
    });

    test('多选字母答案命中多项', () {
      expect(
        QuizReviewAnswerMatch.correctIndexes(options: options, answer: 'AC'),
        <int>[0, 2],
      );
      expect(
        QuizReviewAnswerMatch.correctIndexes(options: options, answer: 'A、C'),
        <int>[0, 2],
      );
      expect(
        QuizReviewAnswerMatch.correctIndexes(options: options, answer: 'B,D'),
        <int>[1, 3],
      );
    });

    test('答案原文含多余空白仍能命中', () {
      expect(
        QuizReviewAnswerMatch.correctIndexes(
          options: options,
          answer: '  减速慢行通过 ',
        ),
        <int>[2],
      );
    });

    test('选项带字母前缀而答案是纯字母时命中', () {
      expect(
        QuizReviewAnswerMatch.correctIndexes(
          options: const <String>['A. 甲', 'B. 乙'],
          answer: 'B',
        ),
        <int>[1],
      );
    });

    test('超出选项范围的字母不误命中', () {
      expect(
        QuizReviewAnswerMatch.correctIndexes(options: options, answer: 'Z'),
        isEmpty,
      );
    });

    test('答案为空时无命中', () {
      expect(
        QuizReviewAnswerMatch.correctIndexes(options: options, answer: '  '),
        isEmpty,
      );
    });

    test('答案与任何选项都不匹配时无命中（审核端据此发现坏数据）', () {
      expect(
        QuizReviewAnswerMatch.correctIndexes(
          options: options,
          answer: '这个答案不在选项里',
        ),
        isEmpty,
      );
    });

    test('判断题 正确/错误 能命中对应选项', () {
      expect(
        QuizReviewAnswerMatch.correctIndexes(
          options: const <String>['正确', '错误'],
          answer: '对',
        ),
        <int>[0],
      );
      expect(
        QuizReviewAnswerMatch.correctIndexes(
          options: const <String>['正确', '错误'],
          answer: '错',
        ),
        <int>[1],
      );
    });
  });

  group('QuizReviewAnswerMatch.isAnswerResolvable', () {
    test('无法定位答案的投稿应被标记，提醒审核员这是坏数据', () {
      expect(
        QuizReviewAnswerMatch.isAnswerResolvable(
          options: options,
          answer: '不存在的答案',
        ),
        isFalse,
      );
      expect(
        QuizReviewAnswerMatch.isAnswerResolvable(
          options: options,
          answer: 'C',
        ),
        isTrue,
      );
    });

    test('没有选项的题（如纯判断/填空）不因此被判坏数据', () {
      expect(
        QuizReviewAnswerMatch.isAnswerResolvable(
          options: const <String>[],
          answer: '任意',
        ),
        isTrue,
      );
    });
  });
}
