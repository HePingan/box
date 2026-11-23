import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:box/features/quiz_plugin/domain/quiz_bank_quality.dart';
import 'package:box/features/quiz_plugin/presentation/quiz_plugin_self_check_page.dart';

QuizBankItem _item(
  String id,
  String question,
  String answer, {
  List<String> options = const ['甲', '乙'],
  String? image,
  String? regionHash,
  bool isNewRule = false,
}) {
  return QuizBankItem(
    id: id,
    question: question,
    type: QuizQuestionType.singleChoice,
    options: options,
    correctAnswer: answer,
    imageUrl: image,
    imageRegionHash: regionHash,
    isNewRule: isNewRule,
  );
}

void main() {
  test('题库质量摘要：同题干异答案/带图/新规/答案越界分别计数', () {
    final summary = QuizBankQualitySummary.summarize([
      _item('1', '标志题', '甲', image: 'http://x/1.jpg', regionHash: 'abc'),
      _item('2', '标志题', '乙', image: 'http://x/2.jpg'),
      _item('3', '普通题', '甲', isNewRule: true),
      _item('4', '坏数据', 'D'),
    ]);
    expect(summary.total, 4);
    expect(summary.ambiguousGroups, 1);
    expect(summary.ambiguousItems, 2);
    expect(summary.withImage, 2);
    expect(summary.withRegionHash, 1);
    expect(summary.newRule, 1);
    expect(summary.answerOutOfRange, 1);
    expect(summary.describe(), contains('同题干异答案 1 组/2 题'));
  });

  test('报告带上题库质量摘要，且不泄漏令牌', () {
    final report = QuizPluginSelfCheckPage.buildReport(
      status: const {'凭证模式': '匿名'},
      probe: '未自测',
      recent: const [],
      important: const [],
      bankQuality: '题库 9 题｜同题干异答案 0 组/0 题',
    );
    expect(report, contains('题库 9 题'));
    expect(report, contains('凭证模式'));
    expect(report, isNot(contains('Bearer ')));
  });

  test('空题库不抛异常', () {
    final summary = QuizBankQualitySummary.summarize(const []);
    expect(summary.total, 0);
    expect(summary.describe(), contains('题库 0 题'));
  });
}
