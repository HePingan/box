import 'package:box/features/quiz_plugin/domain/quiz_answer_aligner.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真实云端题库（/api/quiz/sync 全量 1934 题）中残留 3 道脏数据：
///   q_Iby4sdZZoyc0 -> answer 'C'，但只有 2 个选项
///   q_JBPEq4mvadaK -> answer 'D'，但只有 3 个选项
///   q_dR7qVj8vIbzq -> answer 'D'，但只有 2 个选项
///
/// 这类题的字母下标越界于「题库选项」，等于题库自己都不知道答案是哪一项。
/// 但卷面（probeOptions）通常有 4 项，此时 bankOptions[index] 取不到 →
/// bankOpt 为空 → canLetterMap 的 `bankOpt.isEmpty` 分支被误命中，
/// 于是按位硬贴到卷面第 index 项，还给出 method:'letter' + score:100
/// + confidenceFactor 1.0，向用户「高置信」地展示一个凭空捏造的答案。
///
/// 正确行为：题库有选项、但答案字母越界时属于脏数据，必须拒绝按位映射。
void main() {
  group('题库答案字母越界时不得按位硬贴卷面', () {
    test('答案 C 但题库只有 2 项：不得贴到卷面第 3 项', () {
      final alignment = QuizAnswerAligner.align(
        bankAnswer: 'C',
        bankOptions: ['必须报警，等候警察处理', '开车离开现场'],
        probeOptions: ['必须报警，等候警察处理', '开车离开现场', '与对方私下协商解决', '先行拍照后撤离现场'],
      );

      expect(alignment.aligned, isFalse, reason: '题库只有 2 项却说答案是 C，无法确定答案，不能对齐');
      expect(alignment.method, isNot('letter'));
      expect(alignment.optionIndex, isNull);
      // 不得把卷面第 3 项当成答案展示
      expect(alignment.displayAnswer, isNot(contains('与对方私下协商解决')));
      expect(alignment.confidenceFactor, lessThan(0.85));
    });

    test('答案 D 但题库只有 3 项：不得贴到卷面第 4 项', () {
      final alignment = QuizAnswerAligner.align(
        bankAnswer: 'D',
        bankOptions: ['甲选项正文', '乙选项正文', '丙选项正文'],
        probeOptions: ['甲选项正文', '乙选项正文', '丙选项正文', '丁选项正文'],
      );

      expect(alignment.aligned, isFalse);
      expect(alignment.method, isNot('letter'));
      expect(alignment.displayAnswer, isNot(contains('丁选项正文')));
    });

    test('题库压根没有选项时，仍允许按字母映射（保留既有能力）', () {
      // bankOptions 为空是「只存了字母答案」的正常形态，不是脏数据，
      // 此时按位映射是唯一可用信息，必须继续支持。
      final alignment = QuizAnswerAligner.align(
        bankAnswer: 'B',
        bankOptions: const [],
        probeOptions: ['甲选项正文', '乙选项正文', '丙选项正文', '丁选项正文'],
      );

      expect(alignment.aligned, isTrue);
      expect(alignment.method, 'letter');
      expect(alignment.optionLetter, 'B');
      expect(alignment.displayAnswer, 'B. 乙选项正文');
    });

    test('字母在题库选项范围内且正文一致时照常对齐（不回归）', () {
      final alignment = QuizAnswerAligner.align(
        bankAnswer: 'B',
        bankOptions: ['甲选项正文', '乙选项正文', '丙选项正文'],
        probeOptions: ['甲选项正文', '乙选项正文', '丙选项正文'],
      );

      expect(alignment.aligned, isTrue);
      expect(alignment.optionLetter, 'B');
      expect(alignment.displayAnswer, 'B. 乙选项正文');
    });

    test('越界字母且无卷面试捕时也不得凭空对齐', () {
      final alignment = QuizAnswerAligner.align(
        bankAnswer: 'C',
        bankOptions: ['必须报警，等候警察处理', '开车离开现场'],
      );

      expect(alignment.aligned, isFalse);
      expect(alignment.method, isNot('letter'));
      expect(alignment.confidenceFactor, lessThan(0.85));
    });

    test('题库某项为空串但答案指向该项时不得硬贴卷面', () {
      // bankOptions[2] 是空串，等于题库该项缺正文，同样无法校验。
      final alignment = QuizAnswerAligner.align(
        bankAnswer: 'C',
        bankOptions: ['甲选项正文', '乙选项正文', '   '],
        probeOptions: ['甲选项正文', '乙选项正文', '丙选项正文', '丁选项正文'],
      );

      expect(alignment.aligned, isFalse);
      expect(alignment.displayAnswer, isNot(contains('丙选项正文')));
    });
  });
}
