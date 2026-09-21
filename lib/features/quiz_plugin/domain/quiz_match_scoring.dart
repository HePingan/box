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

  /// 由「选项优先」平滑过渡到「通用加权」的下界。
  ///
  /// 原因（真机 17:02 截图）：选项分 89→90 之间原本是个**硬开关**，
  /// 相邻 1 分导致最终分跳 14~22 分，跨过 0.70 阈值。
  /// 「正确」「错误」这类判断词只有两个字，OCR 多一个标点或噪声字就
  /// 掉到 89 以下，整类题在阈值边缘反复误报「请人工确认」。
  ///
  /// 现在 89~90 之间按线性比例在 55/45 与 25/75 之间插值，消除断崖。
  /// **不放松阈值**，只消除落差。
  static const int judgmentOptionFirstFadeFrom = 80;

  /// 「选项已完整且高度匹配」快捷路径的题干下限。
  static const int completeOptionsMinQuestionScore = 35;

  /// 选项分高到可以完全接管判断的最低题干分。
  ///
  /// 判断题只有两个选项，随机猜中率就有 50%，单靠选项对上不足以判定
  /// 「这道题就是它」—— 题干至少要有基本重合（>= completeOptionsMinQuestionScore）
  /// 才允许走 20/80 兜底。否则 qScore=0 + oScore=100 也会出炉高分（错答）。
  static const int optionOverrideMinQuestionScore = completeOptionsMinQuestionScore;

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

  /// 判断题「选项优先」权重占比，0（全用 55/45）~ 1（全用 25/75）。
  ///
  /// 返回连续值而非 bool，是为了消除 89→90 的硬开关断崖：
  ///   optionScore <= 80  → 0.0（完全通用加权）
  ///   optionScore >= 90  → 1.0（完全选项优先）
  ///   中间线性插值。
  /// 选择题（非判断题形状）恒为 0.0，行为不变。
  ///
  /// ⚠ 题干分低于 [optionOverrideMinQuestionScore] 时权重直接归零：
  /// 判断题只有两个选项，随机猜中率 50%，若题干几乎对不上还让选项接管，
  /// 会把「完全不同的题」推过阈值给出错误答案。宁可报「请人工确认」。
  static double judgmentOptionFirstWeight({
    required bool useOptions,
    required int probeOptionCount,
    required int bankOptionCount,
    required int optionScore,
  }) {
    if (!isJudgmentShape(
      useOptions: useOptions,
      probeOptionCount: probeOptionCount,
      bankOptionCount: bankOptionCount,
    )) {
      return 0;
    }
    const from = judgmentOptionFirstFadeFrom;
    const to = judgmentOptionFirstMinOptionScore;
    if (optionScore >= to) return 1;
    if (optionScore <= from) return 0;
    return (optionScore - from) / (to - from);
  }

  /// [judgmentOptionFirstWeight] 的带题干闸门版本，供引擎使用。
  ///
  /// 题干分 < [optionOverrideMinQuestionScore] 时一律用通用 55/45 加权，
  /// 避免「选项相同但题干完全不同」的题被选项抬过阈值。
  static double judgmentOptionFirstWeightGated({
    required bool useOptions,
    required int probeOptionCount,
    required int bankOptionCount,
    required int optionScore,
    required int questionScore,
  }) {
    if (questionScore < optionOverrideMinQuestionScore) return 0;
    return judgmentOptionFirstWeight(
      useOptions: useOptions,
      probeOptionCount: probeOptionCount,
      bankOptionCount: bankOptionCount,
      optionScore: optionScore,
    );
  }

  /// 判断题是否走「选项优先」权重（仅在完全生效时为 true）。
  ///
  /// 保留此 API 供既有调用点与测试使用；平滑过渡请用
  /// [judgmentOptionFirstWeight]。
  static bool judgmentOptionFirst({
    required bool useOptions,
    required int probeOptionCount,
    required int bankOptionCount,
    required int optionScore,
  }) =>
      judgmentOptionFirstWeight(
        useOptions: useOptions,
        probeOptionCount: probeOptionCount,
        bankOptionCount: bankOptionCount,
        optionScore: optionScore,
      ) >=
      1;

  /// 合成基础分。
  ///
  /// 判断题按 [judgmentOptionFirstWeight] 在 55/45 与 25/75 之间连续插值；
  /// 选择题恒为 55/45（weight=0），行为不变。
  /// 不使用选项时退回题干分 + 形状加成。
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
    // optionFirst 为 true 时 weight=1（完全选项优先），否则 0（通用加权）。
    // 平滑过渡由 baseScoreWeighted 承担；此处保持既有语义兼容旧调用点。
    return baseScoreWeighted(
      useOptions: useOptions,
      questionScore: questionScore,
      optionScore: optionScore,
      shapeBonus: shapeBonus,
      optionFirstWeight: optionFirst ? 1.0 : 0.0,
    );
  }

  /// 按选项优先权重 [optionFirstWeight]（0~1）在两种加权之间连续插值。
  static int baseScoreWeighted({
    required bool useOptions,
    required int questionScore,
    required int optionScore,
    required int shapeBonus,
    required double optionFirstWeight,
  }) {
    if (!useOptions) {
      return (questionScore + shapeBonus).clamp(0, 100);
    }
    final w = optionFirstWeight.clamp(0.0, 1.0);
    final generic = questionScore * 0.55 + optionScore * 0.45;
    final optionLed = questionScore * 0.25 + optionScore * 0.75;
    return (generic + (optionLed - generic) * w).round().clamp(0, 100);
  }

  /// 选项完整且高度匹配时，允许用 20/80 再抬一次分（取两者较大值）。
  ///
  /// 两道闸门缺一不可：
  ///   ① 题干分 >= [optionOverrideMinQuestionScore]。判断题只有两个选项，
  ///      猜中率 50%，纯靠选项对上不能判定「就是这道题」——否则
  ///      qScore=0 + oScore=100 也会出炉高分，给出错误答案。
  ///   ② 选项分 >= [judgmentOptionFirstMinOptionScore]。
  static int finalScore({
    required int base,
    required bool hasCompleteProbeOptions,
    required int questionScore,
    required int optionScore,
  }) {
    final eligible = hasCompleteProbeOptions &&
        questionScore >= optionOverrideMinQuestionScore &&
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
