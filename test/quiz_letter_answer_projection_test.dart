import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';

/// 云端 /api/quiz/sync 绝大多数题的 correctAnswer 是「选项原文」，
/// 但真实库里残留少量字母形答案（如 'C'），且字母下标可能越界于选项数。
///
/// 真机实测（1934 题全量扫描）：
///   q_Iby4sdZZoyc0 -> answer 'C'，仅 2 个选项（越界）
///   q_JBPEq4mvadaK -> answer 'D'，仅 3 个选项（越界）
///   q_dR7qVj8vIbzq -> answer 'D'，仅 2 个选项（越界）
///
/// 这类题在查看页用 `options[i] == correctAnswer` 纯文本比较时永远匹配不到，
/// 会静默显示成「没有正确答案」，用户无从判断对错。
void main() {
  group('字母形答案投影到选项原文', () {
    test('字母在选项范围内时投影为对应选项原文', () {
      const item = QuizBankItem(
        id: 'q1',
        question: '遇到这种情况应当如何处理？',
        type: QuizQuestionType.singleChoice,
        options: ['加速通过', '停车让行', '鸣喇叭示意'],
        correctAnswer: 'B',
      );

      final resolved = QuizAnswerProjection.resolve(item);

      expect(resolved.answer, '停车让行');
      expect(resolved.projected, isTrue);
      expect(resolved.outOfRange, isFalse);
    });

    test('小写字母同样投影', () {
      const item = QuizBankItem(
        id: 'q2',
        question: '判断题示例',
        type: QuizQuestionType.singleChoice,
        options: ['正确', '错误'],
        correctAnswer: 'b',
      );

      expect(QuizAnswerProjection.resolve(item).answer, '错误');
    });

    test('答案已是选项原文时保持不变，不误判为字母', () {
      const item = QuizBankItem(
        id: 'q3',
        question: '罚款额度是多少？',
        type: QuizQuestionType.singleChoice,
        options: ['20元以上200元以下', '200元以上500元以下'],
        correctAnswer: '200元以上500元以下',
      );

      final resolved = QuizAnswerProjection.resolve(item);

      expect(resolved.answer, '200元以上500元以下');
      expect(resolved.projected, isFalse);
      expect(resolved.outOfRange, isFalse);
    });

    test('单字母选项本身是正文时不被当成字母下标', () {
      // 选项就是 A/B/C 这种字面值，答案 'B' 应按原文命中而非按下标投影。
      const item = QuizBankItem(
        id: 'q4',
        question: '下列哪个选项代号正确？',
        type: QuizQuestionType.singleChoice,
        options: ['A', 'B', 'C'],
        correctAnswer: 'B',
      );

      final resolved = QuizAnswerProjection.resolve(item);

      expect(resolved.answer, 'B');
      expect(resolved.projected, isFalse);
    });

    test('字母越界于选项数时标记为待补，不静默失配', () {
      // 真实脏数据形态：答案 'C' 但只有两个选项。
      const item = QuizBankItem(
        id: 'q_Iby4sdZZoyc0',
        question: '发生事故后应当如何处置？',
        type: QuizQuestionType.singleChoice,
        options: ['必须报警，等候警察处理', '开车离开现场'],
        correctAnswer: 'C',
      );

      final resolved = QuizAnswerProjection.resolve(item);

      expect(resolved.outOfRange, isTrue);
      expect(resolved.projected, isFalse);
      // 越界时不编造答案，保留原始值供 UI 提示「答案待补」
      expect(resolved.answer, 'C');
      expect(resolved.needsRepair, isTrue);
    });

    test('答案为空时标记待补', () {
      const item = QuizBankItem(
        id: 'q5',
        question: '缺答案的题',
        type: QuizQuestionType.singleChoice,
        options: ['甲', '乙'],
        correctAnswer: '',
      );

      final resolved = QuizAnswerProjection.resolve(item);

      expect(resolved.needsRepair, isTrue);
      expect(resolved.projected, isFalse);
    });

    test('带「答案：B」前缀的形态也能投影', () {
      const item = QuizBankItem(
        id: 'q6',
        question: '前缀形态',
        type: QuizQuestionType.singleChoice,
        options: ['甲', '乙', '丙'],
        correctAnswer: '答案：C',
      );

      expect(QuizAnswerProjection.resolve(item).answer, '丙');
    });

    test('答案文本仅大小写/空白差异时按选项原文归一', () {
      const item = QuizBankItem(
        id: 'q7',
        question: '空白差异',
        type: QuizQuestionType.singleChoice,
        options: ['停车 让行', '加速通过'],
        correctAnswer: '停车让行',
      );

      final resolved = QuizAnswerProjection.resolve(item);

      expect(resolved.answer, '停车 让行');
      expect(resolved.matchedIndex, 0);
    });
  });

  group('markCorrectOption 供 UI 打对号', () {
    test('字母形答案也能正确打对号', () {
      const item = QuizBankItem(
        id: 'q8',
        question: '打对号',
        type: QuizQuestionType.singleChoice,
        options: ['甲', '乙', '丙'],
        correctAnswer: 'B',
      );

      expect(QuizAnswerProjection.isCorrectOption(item, 0), isFalse);
      expect(QuizAnswerProjection.isCorrectOption(item, 1), isTrue);
      expect(QuizAnswerProjection.isCorrectOption(item, 2), isFalse);
    });

    test('越界字母答案时所有选项都不打对号', () {
      const item = QuizBankItem(
        id: 'q9',
        question: '越界',
        type: QuizQuestionType.singleChoice,
        options: ['甲', '乙'],
        correctAnswer: 'C',
      );

      expect(QuizAnswerProjection.isCorrectOption(item, 0), isFalse);
      expect(QuizAnswerProjection.isCorrectOption(item, 1), isFalse);
    });
  });
}
