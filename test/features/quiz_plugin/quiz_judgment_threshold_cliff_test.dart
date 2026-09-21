import 'package:box/features/quiz_plugin/domain/quiz_match_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真机 17:02 截图回归：判断题「驾驶机动车不按规定使用灯光的，一次记3分。」
/// 悬浮窗报「请人工确认 / 候选1: 错误 / 候选2: 正确」。
///
/// 根因：`judgmentOptionFirstMinOptionScore = 90` 是个**硬开关**。
///   oScore=89 → 掉回 55/45 → final=62（报警）
///   oScore=90 → 走 25/75 + 20/80 兜底 → final=80（不报警）
/// 选项分只差 1 分，最终分跳 18 分，跨过 0.70 阈值。
/// 「正确」「错误」词太短，OCR 多一个标点/噪声字就掉到 89 以下，
/// 整类判断题在阈值边缘反复误报。
///
/// 本测试锁住「没有断崖」这一不变量：**不放松阈值**，只消除落差。
void main() {
  int scoreOf({required int o, required int q}) {
    final weight = QuizMatchScoring.judgmentOptionFirstWeightGated(
      useOptions: true,
      probeOptionCount: 2,
      bankOptionCount: 2,
      optionScore: o,
      questionScore: q,
    );
    final base = QuizMatchScoring.baseScoreWeighted(
      useOptions: true,
      questionScore: q,
      optionScore: o,
      shapeBonus: 0,
      optionFirstWeight: weight,
    );
    return QuizMatchScoring.finalScore(
      base: base,
      hasCompleteProbeOptions: true,
      questionScore: q,
      optionScore: o,
    );
  }

  /// 全 qScore 扫描下，选项分相邻 1 分导致的最大最终分落差。
  /// 实测原实现为 22（qScore=20, oScore=89→90）。
  int worstAdjacentDrop() {
    var worst = 0;
    for (var q = 20; q <= 80; q += 5) {
      for (var o = 70; o < 100; o++) {
        final d = (scoreOf(o: o, q: q) - scoreOf(o: o + 1, q: q)).abs();
        if (d > worst) worst = d;
      }
    }
    return worst;
  }

  test('RED: 选项分跨 90 不该出现断崖（相邻落差 <= 10）', () {
    final worst = worstAdjacentDrop();
    expect(worst, lessThanOrEqualTo(10),
        reason: '选项分相邻 1 分导致最终分暴跌 $worst 分，说明仍有断崖');
  });

  test('RED: 中等题干 + oScore=89 不该跌破 0.70', () {
    // 89 是「OCR 掉一个噪声字」的典型值，此时不该报警
    final s = scoreOf(o: 89, q: 50);
    expect(QuizMatchScoring.isLowConfidence(s), isFalse,
        reason: 'oScore=89/qScore=50 得 $s，仍误报请人工确认');
  });

  test('GREEN 保护：弱匹配仍必须报警（不能放松过头）', () {
    for (final o in [40, 55, 60]) {
      final s = scoreOf(o: o, q: 40);
      expect(QuizMatchScoring.isLowConfidence(s), isTrue,
          reason: 'oScore=$o 本就是弱匹配，必须继续报警');
    }
  });

  test('GREEN 保护：低题干分也仍应报警（题干对不上不能靠选项硬抬）', () {
    for (final q in [0, 10, 20]) {
      final s = scoreOf(o: 100, q: q);
      expect(QuizMatchScoring.isLowConfidence(s), isTrue,
          reason: 'qScore=$q 题干几乎对不上，不该被选项抬过阈值');
    }
  });
}
