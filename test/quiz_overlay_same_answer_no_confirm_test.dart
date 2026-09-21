import 'package:box/features/quiz_plugin/data/quiz_engine.dart';
import 'package:box/features/quiz_plugin/presentation/quiz_plugin_entry.dart';
import 'package:flutter_test/flutter_test.dart';

/// 红灯回归：同题干重复条目（答案一致）不得触发「请人工确认」。
///
/// 真机现象（2026-09-13 08:46 截图）：单选四选项题，悬浮窗只显示
/// 「请人工确认 / 候选1：处五百元以下罚款…」，但库里两条同题干条目
/// **答案完全相同**。用户不需要「人工确认」——没有分歧可选。
///
/// 根因：QuizPluginEntry.overlayDecisionForResult 只看 answers.length > 1，
/// 不比对答案正文；引擎层 _competingAnswerSummary 早已有「答案一致则不
/// 打扰用户」的正确判据，两层口径不一致。
void main() {
  QuizAnswer ans(String text, {double conf = 1.0, String answer = '处五百元以下罚款，申请人在一年内不得再次申领机动车驾驶证'}) =>
      QuizAnswer(
        text: text,
        confidence: conf,
        source: '本地题库',
        correctAnswer: answer,
      );

  List<String> cands(List<QuizAnswer> list) =>
      list.map((a) => a.correctAnswer).toList();

  group('overlayDecisionForResult：同题干重复条目', () {
    test('两条候选答案完全相同 → 不应判 ambiguous', () {
      final answers = [
        ans('匹配题目：…', answer: '处五百元以下罚款，申请人在一年内不得再次申领机动车驾驶证'),
        ans('匹配题目：…', answer: '处五百元以下罚款，申请人在一年内不得再次申领机动车驾驶证'),
      ];
      final result = QuizResult(question: '…', answers: answers);
      final decision = QuizPluginEntry.overlayDecisionForResult(
        result,
        cands(answers),
      );
      expect(
        decision.status,
        'hit',
        reason: '两条候选答案一致，用户无需确认；应直接给出答案',
      );
    });

    test('两条候选题干也相同、仅库内重复 → 不应判 ambiguous', () {
      const same = '申请人隐瞒有关情况或者提供虚假材料申领机动车驾驶证的，会受到什么处罚？';
      final answers = [
        ans('匹配题目：$same', answer: '处五百元以下罚款'),
        ans('匹配题目：$same', answer: '处五百元以下罚款'),
      ];
      final result = QuizResult(question: same, answers: answers);
      final decision = QuizPluginEntry.overlayDecisionForResult(
        result,
        cands(answers),
      );
      expect(decision.status, 'hit');
    });

    test('两条候选答案确实不同 → 仍必须判 ambiguous（不得回归）', () {
      final answers = [
        ans('…', answer: '处五百元以下罚款，申请人在一年内不得再次申领机动车驾驶证'),
        ans('…', answer: '申请人终生不得再次申领机动车驾驶证'),
      ];
      final result = QuizResult(question: '…', answers: answers);
      final decision = QuizPluginEntry.overlayDecisionForResult(
        result,
        cands(answers),
      );
      expect(
        decision.status,
        'ambiguous',
        reason: '答案有分歧必须保留人工确认',
      );
    });

    test('单条低置信（<0.70）仍必须判 ambiguous（不得回归）', () {
      final answers = [ans('…', conf: 0.55, answer: '处五百元以下罚款')];
      final result = QuizResult(question: '…', answers: answers);
      final decision = QuizPluginEntry.overlayDecisionForResult(
        result,
        cands(answers),
      );
      expect(decision.status, 'ambiguous');
    });
  });
}
