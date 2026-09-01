import 'dart:math';

/// 题干/选项相似度如何合成最终匹配分。
///
/// 抽出来的原因：公式原先内联在 `quiz_engine.dart` 的匹配循环里，外部调
/// 不到。此前 `quiz_judgment_option_first_weight_test.dart` 和
/// `quiz_judgment_single_hit_confidence_test.dart` 在测试文件里把公式抄了
/// 一份再断言自己的副本 —— 引擎改坏了那两个测试照样绿。
class QuizMatchScoring {
  const QuizMatchScoring._();

  /// 低于此置信度就提示「请人工确认」。
  static const double lowConfidenceThreshold = 0.70;

  /// 判断题选项优先加权的触发门槛：选项相似度至少这么高。
  static const int judgmentOptionFirstMinOptionScore = 90;

  /// 「选项已完整且高度匹配」快捷路径的题干下限。
  static const int completeOptionsMinQuestionScore = 35;

  /// 是否为判断题形状：两侧选项数都恰好为 2。
  ///
  /// 引擎里多处「选项已足够消歧」的快捷路径门槛都是选项数 >= 3，判断题
  /// 整类被排除，只能吃 55/45 加权。但对判断题而言选项匹配才是最强信号
  /// （只有正确/错误两种可能，对上就是对上了），题干相似度反而最容易被
  /// OCR 噪声污染（屏幕噪声字符、错别字、长题干稀释）。
  static bool isJudgmentShape({
    required bool useOptions,
    required int probeOptionCount,
    required int bankOptionCount,
  }) =>
      useOptions && probeOptionCount == 2 && bankOptionCount == 2;

  /// 判断题是否走「选项优先」权重。只在选项高度匹配时生效，选择题不受影响。
  static bool judgmentOptionFirst({
    required bool useOptions,
    required int probeOptionCount,
    required int bankOptionCount,
    required int optionScore,
  }) =>
      isJudgmentShape(
        useOptions: useOptions,
        probeOptionCount: probeOptionCount,
        bankOptionCount: bankOptionCount,
      ) &&
      optionScore >= judgmentOptionFirstMinOptionScore;

  /// 合成基础分。
  ///
  /// 判断题选项优先时用 25/75，否则 55/45。不使用选项时退回题干分 + 形状加成。
  static int baseScore({
    required bool useOptions,
    required int questionScore,
    required int optionScore,
    required int shapeBonus,
    required bool optionFirst,
  }) {
    if (!useOptions) {
      return (questionScore + shapeBonus).clamp(0, 100);
    }
    final weighted = optionFirst
        ? (questionScore * 0.25 + optionScore * 0.75)
        : (questionScore * 0.55 + optionScore * 0.45);
    return weighted.round().clamp(0, 100);
  }

  /// 选项完整且高度匹配时，允许用 20/80 再抬一次分（取两者较大值）。
  ///
  /// 55/45 下 oScore 满分时仍要求 qScore >= 45，会导致「唯一命中却提示
  /// 请人工确认」。
  static int finalScore({
    required int base,
    required bool hasCompleteProbeOptions,
    required int questionScore,
    required int optionScore,
  }) {
    final eligible = hasCompleteProbeOptions &&
        questionScore >= completeOptionsMinQuestionScore &&
        optionScore >= judgmentOptionFirstMinOptionScore;
    final result = eligible
        ? max(base, (questionScore * 0.20 + optionScore * 0.80).round())
        : base;
    return result.clamp(0, 100);
  }

  /// 该分数是否需要人工确认。
  static bool isLowConfidence(int score) =>
      score / 100 < lowConfidenceThreshold;
}
