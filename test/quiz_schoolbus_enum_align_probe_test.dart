import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/quiz_plugin/data/quiz_engine.dart';
import 'package:box/features/quiz_plugin/domain/ocr_quiz_parser.dart';
import 'package:box/features/quiz_plugin/domain/quiz_answer_aligner.dart';
import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:box/features/quiz_plugin/domain/quiz_config.dart';

/// 真实反馈（2026-09-06 19:05 试捕 + 悬浮窗截图）：
/// 题干「如图所示，校车在最右侧车道停靠上下学生时，以下哪辆车可以通过？」
/// 卷面 A.②③ B.② C.③ D.①，题库（服务端 q_vbDHldYwkqZ9）答案「①」。
/// 悬浮窗显示「答案：① (未对齐卷面选项)」+ 70%，应当显示 D。
void main() {
  const bankOptions = <String>['②③', '②', '③', '①'];

  // 用户提供的读屏原文（13 行）
  const rawScreen = '''
答题
背题
视频
NEW
设置
x 如图所示，校车在最右侧车道停靠上下学生时，以下哪辆车可以通过？x
②③
②
③
①
答案 D
速记口诀
本题技巧
''';

  const bankItem = QuizBankItem(
    id: 'q_vbDHldYwkqZ9',
    question: '如图所示，校车在最右侧车道停靠上下学生时，以下哪辆车可以通过？',
    type: QuizQuestionType.singleChoice,
    options: bankOptions,
    correctAnswer: '①',
    analysis: '速记口诀',
  );

  test('读屏原文应解析出 4 个圈码选项', () {
    final parsed = OcrQuizParser.parse(rawScreen);
    expect(parsed.options, bankOptions, reason: 'question=${parsed.question}');
  });

  test('圈码单选答案应对齐到卷面 D（选项齐全）', () {
    final a = QuizAnswerAligner.align(
      bankAnswer: '①',
      bankOptions: bankOptions,
      probeOptions: bankOptions,
    );
    expect(a.aligned, isTrue, reason: 'method=${a.method}');
    expect(a.displayAnswer, 'D. ①');
  });

  test('卷面漏捕被选中的那一项时，仍应能对齐（当前失败=复现用例）', () {
    // 真机上 D 行显示为 ✔ 勾选态，读屏很可能拿不到「①」这一行。
    final a = QuizAnswerAligner.align(
      bankAnswer: '①',
      bankOptions: bankOptions,
      probeOptions: const ['②③', '②', '③'],
    );
    expect(
      a.aligned,
      isTrue,
      reason: '缺项卷面也应按题库选项序落到 D；实际 method=${a.method} display=${a.displayAnswer}',
    );
    expect(a.optionLetter, 'D');
  });

  test('端到端：读屏原文 + 真实题库记录应给出 D. ①', () async {
    QuizBankCache.instance.assign([bankItem]);
    final engine = QuizEngine(config: const QuizConfig(bankEnabled: true));
    final parsed = OcrQuizParser.parse(rawScreen);
    final result = await engine.search(
      rawScreen,
      probeOptions: parsed.options,
    );
    expect(result.isSuccess, isTrue, reason: 'error=${result.error}');
    final first = result.answers.first;
    expect(
      first.alignedToProbe,
      isTrue,
      reason: 'method=${first.alignmentMethod} text=${first.text}',
    );
    expect(first.correctAnswer, '①');
    expect(first.confidence, greaterThanOrEqualTo(0.9));
  });

  group('bank_index 兜底的边界（不得越权硬贴序号）', () {
    test('卷面有题库里没有的选项时不得按序号贴（异文题库）', () {
      final a = QuizAnswerAligner.align(
        bankAnswer: '①',
        bankOptions: bankOptions,
        // 「④」在题库里不存在 → 两侧不是同一套选项
        probeOptions: const ['②③', '②', '④'],
      );
      expect(a.method, isNot('bank_index'));
      expect(a.aligned, isFalse);
    });

    test('卷面选项齐全时不走兜底（应由 exact 命中）', () {
      final a = QuizAnswerAligner.align(
        bankAnswer: '①',
        bankOptions: bankOptions,
        probeOptions: bankOptions,
      );
      expect(a.method, 'exact');
    });

    test('漏捕的项不是答案项时不得贴到答案上', () {
      // 卷面漏了 C「③」，但答案是 D「①」且卷面已有「①」→ 应走 exact，不是兜底
      final a = QuizAnswerAligner.align(
        bankAnswer: '①',
        bankOptions: bankOptions,
        probeOptions: const ['②③', '②', '①'],
      );
      expect(a.method, 'exact');
      expect(a.optionLetter, 'C', reason: '卷面第 3 项就是①，字母按卷面位置算');
    });

    test('文字选项题：卷面漏捕答案项也应补出字母', () {
      final a = QuizAnswerAligner.align(
        bankAnswer: '停车让行',
        bankOptions: const ['加速通过', '鸣喇叭通过', '停车让行', '绕行通过'],
        probeOptions: const ['加速通过', '鸣喇叭通过', '绕行通过'],
      );
      expect(a.aligned, isTrue, reason: 'method=${a.method}');
      expect(a.optionLetter, 'C');
    });
  });

  test('端到端：卷面漏捕勾选项（3 个选项）时不得退化为未对齐', () async {
    QuizBankCache.instance.assign([bankItem]);
    final engine = QuizEngine(config: const QuizConfig(bankEnabled: true));
    final result = await engine.search(
      rawScreen,
      probeOptions: const ['②③', '②', '③'],
    );
    expect(result.isSuccess, isTrue, reason: 'error=${result.error}');
    final first = result.answers.first;
    expect(
      first.alignedToProbe,
      isTrue,
      reason: 'method=${first.alignmentMethod} text=${first.text}',
    );
  });
}
