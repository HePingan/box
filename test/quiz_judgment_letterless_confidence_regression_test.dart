import 'package:box/features/quiz_plugin/domain/quiz_answer_aligner.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用户真实反馈复现：判断题唯一命中却提示「请人工确认」。
///
/// 屏幕原文：
/// ```
/// x 如图所示，驾驶机动车遇到前方车辆行驶较慢时，可以在交叉路口内超车。x
/// 正确
/// 错误
/// 答案 B
/// 速记口诀
/// 请人工确认
/// 候选 1：错误
/// ```
///
/// 题库里这道题的选项被存成「正确. 正确 / 错误. 错误」——
/// 即选项前缀不是 A/B/C/D 字母，而是选项自身文字。
///
/// 「候选 1：错误」说明答案投影正确、候选唯一（answers.length == 1），
/// 所以走的不是 ambiguous 分支，而是 lowConfidence（confidence < 0.70）。
void main() {
  group('判断题「正确/错误」应能对齐到卷面选项', () {
    test('题库答案「错误」对齐卷面「错误」必须 aligned 且高置信', () {
      final a = QuizAnswerAligner.align(
        bankAnswer: '错误',
        bankOptions: const ['正确', '错误'],
        probeOptions: const ['正确', '错误'],
      );
      expect(a.aligned, isTrue, reason: '判断题文字完全一致，必须对齐');
      expect(a.method, 'exact');
      expect(
        a.confidenceFactor,
        1.0,
        reason: 'exact 对齐不该有置信度折扣',
      );
    });

    test('题库选项带「正确.」「错误.」自身文字前缀时也要对齐', () {
      // 这是用户题库里的真实存储形态（不是 A./B.）
      final a = QuizAnswerAligner.align(
        bankAnswer: '错误',
        bankOptions: const ['正确. 正确', '错误. 错误'],
        probeOptions: const ['正确', '错误'],
      );
      expect(
        a.aligned,
        isTrue,
        reason: '「错误. 错误」应被规范化后对齐到卷面「错误」',
      );
      expect(
        a.confidenceFactor,
        greaterThanOrEqualTo(0.92),
        reason: 'confidenceFactor 0.70 会把 95 分打到 66.5，'
            '低于 0.70 阈值从而误报「请人工确认」',
      );
    });

    test('答案存成「B」而卷面是判断题时，字母应投影到第二项', () {
      final a = QuizAnswerAligner.align(
        bankAnswer: 'B',
        bankOptions: const ['正确', '错误'],
        probeOptions: const ['正确', '错误'],
      );
      expect(a.aligned, isTrue);
      expect(a.probeOption, '错误');
      expect(a.confidenceFactor, 1.0);
    });

    test('高分命中经 confidenceFactor 折扣后不得跌破人工确认阈值', () {
      final a = QuizAnswerAligner.align(
        bankAnswer: '错误',
        bankOptions: const ['正确. 正确', '错误. 错误'],
        probeOptions: const ['正确', '错误'],
      );
      // 引擎：adjustedScore = score * confidenceFactor，confidence = adjustedScore/100
      // overlayDecisionForResult 里 lowConfidence = confidence < 0.70
      const rawScore = 95;
      final confidence = (rawScore * a.confidenceFactor).round() / 100;
      expect(
        confidence,
        greaterThanOrEqualTo(0.70),
        reason: '判断题精确命中不该被判 lowConfidence',
      );
    });
  });
}
