import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:box/features/quiz_plugin/data/quiz_engine.dart';
import 'package:box/features/quiz_plugin/domain/quiz_config.dart';

/// 真机 1.18.16 (239) 报告：题图为空的高速限速题落到「请人工确认」，
/// 且候选端出完全无关题的答案。
///
/// 卷面（用户截图 2026-09-13 12:22）：
///   在图中高速公路行驶，车速不得高于（ ）。
///   A.90公里/小时 B.100公里/小时 C.120公里/小时 D.110公里/小时
///   正确答案 D.110公里/小时
///   题图为高速公路实拍（有限速 110 标志）——题库该条却 **没有存图**。
///
/// 悬浮窗实际显示：
///   请人工确认
///   候选 1：提醒车辆驾驶人前方有向上的陡坡路段
///   （该文案来自 q_sWuC0pNfkvCe「这个标志是何含义？」，是完全不同的题）
///
/// 云端题库真实存在的三条同前缀题（选项集合互不相同）：
///   q_9wW6dY8CTdWx  在图中高速公路行驶，车速不得超过（ ）。  [120,100,90,60]  → 120公里/小时
///   q_Dmd_nVL1hN4g  在图中高速公路行驶，车速不得高于（ ）。  [100,110,120,90] → 110公里/小时
///   q_MVecncprIEw-  在图中高速公路行驶，车速不得低于（ ）。  [50,60,80,100]   → 60公里/小时
///
/// 判据：三道题的**选项集合互不相同**，选项本身即可唯一决胜，无需题图。
/// 图只在「题干一致且选项也一致」时才不可替代。此处不属该情形。
void main() {
  const highwayStem = '在图中高速公路行驶，车速不得高于（ ）。';
  const highwayOptions = ['100公里/小时', '110公里/小时', '120公里/小时', '90公里/小时'];

  List<QuizBankItem> realBank() => const [
        QuizBankItem(
          id: 'q_9wW6dY8CTdWx',
          question: '在图中高速公路行驶，车速不得超过（ ）。',
          type: QuizQuestionType.singleChoice,
          options: ['120公里/小时', '100公里/小时', '90公里/小时', '60公里/小时'],
          correctAnswer: '120公里/小时',
        ),
        QuizBankItem(
          id: 'q_Dmd_nVL1hN4g',
          question: highwayStem,
          type: QuizQuestionType.singleChoice,
          options: highwayOptions,
          correctAnswer: '110公里/小时',
        ),
        QuizBankItem(
          id: 'q_MVecncprIEw-',
          question: '在图中高速公路行驶，车速不得低于（ ）。',
          type: QuizQuestionType.singleChoice,
          options: ['50公里/小时', '60公里/小时', '80公里/小时', '100公里/小时'],
          correctAnswer: '60公里/小时',
        ),
        // 真实存在于库里的无关题，正是悬浮窗端出的「陡坡」答案来源。
        QuizBankItem(
          id: 'q_sWuC0pNfkvCe',
          question: '这个标志是何含义？',
          type: QuizQuestionType.singleChoice,
          options: [
            '提醒车辆驾驶人前方有向上的陡坡路段',
            '提醒车辆驾驶人前方有向下的陡坡路段',
            '提醒车辆驾驶人前方有两个及以上的连续上坡路段',
            '提醒车辆驾驶人前方有连续下坡路段',
          ],
          correctAnswer: '提醒车辆驾驶人前方有向上的陡坡路段',
        ),
      ];

  test('RED：限速题题干+选项唯一命中时，应直接给出 110，不得落到请人工确认', () async {
    QuizBankCache.instance.assign(realBank());
    final engine = QuizEngine(config: const QuizConfig(bankEnabled: true));

    final result = await engine.search(highwayStem, probeOptions: highwayOptions);

    expect(result.isSuccess, isTrue, reason: '题干逐字一致 + 选项逐字一致，应命中');
    expect(
      result.answers.first.correctAnswer,
      '110公里/小时',
      reason: 'q_Dmd_nVL1hN4g 是该题的唯一正确解',
    );
  });

  test('RED：唯一命中时置信应 >= 0.90，不得落入 lowConfidence 确认态', () async {
    QuizBankCache.instance.assign(realBank());
    final engine = QuizEngine(config: const QuizConfig(bankEnabled: true));

    final result = await engine.search(highwayStem, probeOptions: highwayOptions);

    expect(result.answers, isNotEmpty);
    expect(
      result.answers.first.confidence,
      greaterThanOrEqualTo(0.90),
      reason: '题干与选项双满分的题不该低置信',
    );
  });

  test('RED：候选不得包含完全无关的「陡坡」答案', () async {
    QuizBankCache.instance.assign(realBank());
    final engine = QuizEngine(config: const QuizConfig(bankEnabled: true));

    final result = await engine.search(highwayStem, probeOptions: highwayOptions);

    final answers = result.answers.map((a) => a.correctAnswer).toList();
    expect(
      answers,
      isNot(contains('提醒车辆驾驶人前方有向上的陡坡路段')),
      reason: '「陡坡」来自「这个标志是何含义？」，属完全不同题，不得作为候选',
    );
    expect(answers, isNot(contains('120公里/小时')), reason: '「不得超过」是另一道题');
    expect(answers, isNot(contains('60公里/小时')), reason: '「不得低于」是另一道题');
  });
}
