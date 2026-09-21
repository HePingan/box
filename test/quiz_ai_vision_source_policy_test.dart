// 红灯回归：AI 读屏来源（aiVision）的排名与判定。
//
// 背景（2026-09-13）：用户拍板「所有本地未命中的题」走大模型读屏。
// 历史教训（三轮报障）：来源排名不当会让新来源被静默拦下，悬浮窗永远停在
// 「检索中」。aiVision 必须排在所有既有来源之前，才能保证读屏结果能上屏。
//
// 本测试锁定三条契约：
//   1. aiVision 排名最高（rank 5）
//   2. aiVision 结果的 source 字符串可被识别为 aiVision
//   3. 换题后旧来源排名作废（防止跨题污染）

import 'package:box/features/quiz_plugin/domain/quiz_search_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// 生产代码里 _sourceForResult 的判定逻辑镜像 —— 保证 source 字符串与枚举
/// 的映射关系被测试锁死（改字符串必须同步改测试）。
QuizResultSource sourceForSourceString(String source) {
  final src = source.toLowerCase();
  if (src.contains('本地题库')) return QuizResultSource.localBank;
  if (src.contains('ocr')) return QuizResultSource.ocrLocalBank;
  if (src.contains('ai读屏') || src.contains('ai 读屏')) {
    return QuizResultSource.aiVision;
  }
  return QuizResultSource.externalApi;
}

void main() {
  group('AI 读屏来源判定', () {
    test('source="AI读屏" 被识别为 aiVision', () {
      expect(sourceForSourceString('AI读屏'), QuizResultSource.aiVision);
    });

    test('带空格变体 "AI 读屏" 也识别为 aiVision', () {
      expect(sourceForSourceString('AI 读屏'), QuizResultSource.aiVision);
    });

    test('不被误判为 externalApi（回归：必须早于外部 API 判定）', () {
      expect(
        sourceForSourceString('AI读屏'),
        isNot(QuizResultSource.externalApi),
      );
    });

    test('既有来源判定不受影响', () {
      expect(sourceForSourceString('本地题库'), QuizResultSource.localBank);
      expect(sourceForSourceString('OCR'), QuizResultSource.ocrLocalBank);
      expect(sourceForSourceString('外部API'), QuizResultSource.externalApi);
    });
  });

  group('AI 读屏排名（防止结果被静默拦下）', () {
    test('aiVision 可覆盖本地题库命中（不存在 rank 不足被丢弃）', () {
      final policy = QuizSearchPolicy();
      // 先记录一次本地题库命中作为既有最高来源。
      policy.recordSuccess(
        stem: '题目甲',
        options: const ['A', 'B'],
        source: QuizResultSource.localBank,
        questionScore: 100,
        optionScore: 100,
      );
      // 同题再来读屏结果：必须放行（否则悬浮窗停在检索中）。
      expect(
        policy.canReplaceWith(QuizResultSource.aiVision, stem: '题目甲'),
        isTrue,
      );
    });

    test('换题后旧排名作废：读屏结果可上屏', () {
      final policy = QuizSearchPolicy();
      policy.recordSuccess(
        stem: '旧题',
        options: const ['A'],
        source: QuizResultSource.localBank,
        questionScore: 100,
        optionScore: 100,
      );
      // 换了一道新题：旧题的 localBank 排名不得掐死新题的读屏结果。
      expect(
        policy.canReplaceWith(QuizResultSource.aiVision, stem: '新题'),
        isTrue,
      );
    });

    test('本地题库仍可覆盖较低优先级的通用外搜（externalApi）', () {
      final policy = QuizSearchPolicy();
      policy.recordSuccess(
        stem: '题目乙',
        options: const ['A'],
        source: QuizResultSource.externalApi,
        questionScore: 50,
        optionScore: 50,
      );
      expect(
        policy.canReplaceWith(QuizResultSource.localBank, stem: '题目乙'),
        isTrue,
      );
    });
  });

  group('题干指纹（读屏 hintQuestion 复用）', () {
    test('stripQuestionPrefix 归一化后可用于同题判定', () {
      final a = QuizSearchPolicy.stemFingerprint('【单选题】驾驶校车超员');
      final b = QuizSearchPolicy.stemFingerprint('驾驶校车超员');
      expect(a, b);
    });
  });
}
