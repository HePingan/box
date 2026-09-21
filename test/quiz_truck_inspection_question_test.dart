import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:box/features/quiz_plugin/domain/quiz_config.dart';
import 'package:box/features/quiz_plugin/data/quiz_engine.dart';
import 'package:box/features/quiz_plugin/presentation/quiz_plugin_entry.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归：载货汽车「多长时间以内每年检验1次」（问年数）必须有题可命中。
///
/// 真机现象（2026-09-13 09:18 截图）：该题在悬浮窗显示
/// 「请人工确认 / 候选1：1次」。根因是**题库覆盖缺口** —— 库里只有两条
/// 同前缀但问「几次」的题：
///   - 载货汽车从注册登记之日起，10年以内每年检验几次？ → 1次
///   - 载货汽车从注册登记之日起，超过10年的，每年检验多少次？ → 3
/// 引擎按前缀召回前者，置信度仅 0.35（问点不同），正确地判了「请人工确认」。
/// 已补题 q_Qu0WFOu5KkZY（答案 10年）。本测试钉住：补题后必须直达答案。
void main() {
  test('问年数原题 → 命中新题、hit、答案 10年', () async {
    QuizBankCache.instance.assign([
      const QuizBankItem(
        id: 'q_qUCu0onynQMz',
        question: '载货汽车从注册登记之日起，10年以内每年检验几次？',
        type: QuizQuestionType.singleChoice,
        options: ['1次', '2次', '3次', '4次'],
        correctAnswer: '1次',
      ),
      const QuizBankItem(
        id: 'q_SXsXOaNpiVQD',
        question: '载货汽车从注册登记之日起，超过10年的，每年检验多少次？',
        type: QuizQuestionType.singleChoice,
        options: ['2', '3', 'D4'],
        correctAnswer: '3',
      ),
      const QuizBankItem(
        id: 'q_Qu0WFOu5KkZY',
        question: '载货汽车从注册登记之日起，多长时间以内每年检验1次？',
        type: QuizQuestionType.singleChoice,
        options: ['6年', '10年', '5年', '8年'],
        correctAnswer: '10年',
      ),
    ]);

    final engine = QuizEngine(config: const QuizConfig(bankEnabled: true));
    final r = await engine.search(
      '载货汽车从注册登记之日起，多长时间以内每年检验1次？',
      probeOptions: ['6年', '10年', '5年', '8年'],
    );

    expect(r.answers, isNotEmpty, reason: '补题后应有命中');
    final top = r.answers.first;
    expect(top.correctAnswer, '10年', reason: '问年数必须给年数答案');
    expect(top.confidence, greaterThan(0.70), reason: '精确命中，置信度应过阈值');

    final decision = QuizPluginEntry.overlayDecisionForResult(
      r,
      r.answers.map((a) => a.correctAnswer).toList(),
    );
    expect(decision.status, 'hit', reason: '精确命中应直接出答案，不再要人工确认');
  });
}
