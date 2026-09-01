import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/quiz_plugin/domain/quiz_match_scoring.dart';

/// 判断题唯一命中的置信度。
///
/// 记录的问题：判断题只有 2 个选项，引擎里多处「选项已足够消歧」的快捷
/// 路径都要求选项数 >= 3，判断题一律走不到，只能吃 55/45 加权。于是
/// oScore 满分也救不回被 OCR 噪声压低的 qScore，表现为「唯一命中却提示
/// 请人工确认」。
///
/// 原版本在测试文件里抄了一份 baseScore 公式再断言自己的副本，引擎改坏
/// 了照样绿。现在调真实的 QuizMatchScoring。
void main() {
  /// 旧口径：不走选项优先的 55/45 加权。
  int legacyBase(int qScore, int oScore) => QuizMatchScoring.baseScore(
        useOptions: true,
        questionScore: qScore,
        optionScore: oScore,
        shapeBonus: 0,
        optionFirst: false,
      );

  group('判断题唯一命中的置信度（旧 55/45 口径的边界）', () {
    test('选项满分但题干被噪声压低时会误判 lowConfidence', () {
      const oScore = 100;
      const qScore = 60;
      final score = legacyBase(qScore, oScore);
      expect(score, 78, reason: 'qScore=60 时尚可');
      expect(QuizMatchScoring.isLowConfidence(score), isFalse);
    });

    test('题干相似度跌到 45 以下时，选项满分也救不回来', () {
      const oScore = 100;
      for (final qScore in [30, 40, 44]) {
        final score = legacyBase(qScore, oScore);
        expect(
          QuizMatchScoring.isLowConfidence(score),
          isTrue,
          reason: 'qScore=$qScore oScore=100 => score=$score，'
              '判断题选项已完全一致却仍要求人工确认',
        );
      }
    });

    test('临界点：旧口径下 qScore 需要 >=45 才不触发人工确认', () {
      const oScore = 100;
      var threshold = -1;
      for (var q = 0; q <= 100; q++) {
        if (!QuizMatchScoring.isLowConfidence(legacyBase(q, oScore))) {
          threshold = q;
          break;
        }
      }
      expect(
        threshold,
        45,
        reason: '选项满分时题干相似度仍需 >=45 才免确认；'
            '这解释了为何长题干 + OCR 噪声容易掉进人工确认',
      );
    });
  });

  group('选项完整时的 20/80 抬分路径', () {
    test('选项完整且题干过线时用 20/80 抬分', () {
      // base 走旧 55/45：qScore=40 => 67（低置信）
      final base = legacyBase(40, 100);
      expect(base, 67);
      final lifted = QuizMatchScoring.finalScore(
        base: base,
        hasCompleteProbeOptions: true,
        questionScore: 40,
        optionScore: 100,
      );
      expect(lifted, 88, reason: '20/80 => 0.2*40 + 0.8*100 = 88');
      expect(QuizMatchScoring.isLowConfidence(lifted), isFalse);
    });

    test('题干低于 35 时不给抬分', () {
      final base = legacyBase(30, 100);
      final result = QuizMatchScoring.finalScore(
        base: base,
        hasCompleteProbeOptions: true,
        questionScore: 30,
        optionScore: 100,
      );
      expect(result, base, reason: 'qScore < 35 不满足抬分前提');
    });

    test('选项不完整时不给抬分', () {
      final base = legacyBase(40, 100);
      final result = QuizMatchScoring.finalScore(
        base: base,
        hasCompleteProbeOptions: false,
        questionScore: 40,
        optionScore: 100,
      );
      expect(result, base);
    });

    test('抬分只会取较大值，不会把已经更高的 base 拉低', () {
      // 判断题选项优先：0.25*60 + 0.75*100 = 90
      // 20/80 抬分只有 0.2*60 + 0.8*100 = 92 —— 这里反过来验更高的一侧胜出
      final base = QuizMatchScoring.baseScore(
        useOptions: true,
        questionScore: 60,
        optionScore: 100,
        shapeBonus: 0,
        optionFirst: true,
      );
      expect(base, 90);
      final result = QuizMatchScoring.finalScore(
        base: base,
        hasCompleteProbeOptions: true,
        questionScore: 60,
        optionScore: 100,
      );
      expect(result, 92, reason: 'max() 取两者较大：20/80 更高时用它');
      expect(result >= base, isTrue, reason: 'max() 语义：不得低于 base');
    });

    test('base 已高于 20-80 结果时保留 base', () {
      // qScore=20 走选项优先：0.25*20 + 0.75*100 = 80
      // 20/80 只有 0.2*20 + 0.8*100 = 84 —— 仍更高
      // 取一个 base 确实更高的组合：oScore 刚过门槛 90
      final base = QuizMatchScoring.baseScore(
        useOptions: true,
        questionScore: 100,
        optionScore: 90,
        shapeBonus: 0,
        optionFirst: true,
      );
      expect(base, 93, reason: '0.25*100 + 0.75*90 = 92.5 → 93');
      final result = QuizMatchScoring.finalScore(
        base: base,
        hasCompleteProbeOptions: true,
        questionScore: 100,
        optionScore: 90,
      );
      expect(result, 93, reason: '20/80 只有 92，应保留更高的 base');
    });

    test('分数始终收敛在 0..100', () {
      final result = QuizMatchScoring.finalScore(
        base: 100,
        hasCompleteProbeOptions: true,
        questionScore: 100,
        optionScore: 100,
      );
      expect(result, 100);
    });
  });
}
