import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/quiz_plugin/domain/quiz_match_scoring.dart';

/// 判断题选项优先加权。
///
/// 原版本在测试文件里把 `quiz_engine.dart` 的公式抄了一份（`int weighted(...)`）
/// 再断言自己的副本，引擎改坏了照样绿。现在调真实的 QuizMatchScoring。
void main() {
  int weighted(int qScore, int oScore, {required bool optionFirst}) =>
      QuizMatchScoring.baseScore(
        useOptions: true,
        questionScore: qScore,
        optionScore: oScore,
        shapeBonus: 0,
        optionFirst: optionFirst,
      );

  group('判断题选项优先加权', () {
    test('修复前后对比：oScore 满分、qScore=40 的真实场景', () {
      const qScore = 40;
      const oScore = 100;
      final before = weighted(qScore, oScore, optionFirst: false);
      final after = weighted(qScore, oScore, optionFirst: true);
      expect(before, 67, reason: '旧权重下跌破 70 阈值 => 误报人工确认');
      expect(QuizMatchScoring.isLowConfidence(before), isTrue,
          reason: '这就是用户遇到的现象');
      expect(after, 85);
      expect(QuizMatchScoring.isLowConfidence(after), isFalse,
          reason: '修复后不再要求人工确认');
    });

    test('题干被噪声压得很低时也能免确认', () {
      const oScore = 100;
      // 屏幕噪声 x + 错别字 + 长题干稀释，qScore 掉到 20 都还能救
      for (final qScore in [20, 30, 40, 50]) {
        final score = weighted(qScore, oScore, optionFirst: true);
        expect(
          QuizMatchScoring.isLowConfidence(score),
          isFalse,
          reason: 'qScore=$qScore oScore=100 => score=$score 应免人工确认',
        );
      }
    });

    test('选择题权重未被改动', () {
      // 四选一：选项数不为 2，不该触发选项优先
      expect(
        QuizMatchScoring.judgmentOptionFirst(
          useOptions: true,
          probeOptionCount: 4,
          bankOptionCount: 4,
          optionScore: 100,
        ),
        isFalse,
      );
      expect(weighted(40, 100, optionFirst: false), 67);
    });

    test('选项相似度不够高时判断题也不走选项优先', () {
      // oScore 未达 90 门槛：选项本身没对上，不该让它主导
      expect(
        QuizMatchScoring.judgmentOptionFirst(
          useOptions: true,
          probeOptionCount: 2,
          bankOptionCount: 2,
          optionScore: 89,
        ),
        isFalse,
      );
      expect(
        QuizMatchScoring.judgmentOptionFirst(
          useOptions: true,
          probeOptionCount: 2,
          bankOptionCount: 2,
          optionScore: 90,
        ),
        isTrue,
      );
    });

    test('只有一侧是两个选项时不算判断题形状', () {
      expect(
        QuizMatchScoring.isJudgmentShape(
          useOptions: true,
          probeOptionCount: 2,
          bankOptionCount: 4,
        ),
        isFalse,
      );
      expect(
        QuizMatchScoring.isJudgmentShape(
          useOptions: true,
          probeOptionCount: 4,
          bankOptionCount: 2,
        ),
        isFalse,
      );
    });

    test('不使用选项时退回题干分加形状加成', () {
      expect(
        QuizMatchScoring.baseScore(
          useOptions: false,
          questionScore: 60,
          optionScore: 100,
          shapeBonus: 5,
          optionFirst: false,
        ),
        65,
        reason: 'useOptions=false 时 oScore 不该参与',
      );
    });
  });
}
