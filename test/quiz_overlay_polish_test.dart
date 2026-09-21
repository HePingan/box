import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/quiz_plugin/presentation/quiz_plugin_entry.dart';

/// 悬浮窗第二轮视觉优化（2026-09-13 用户反馈「有点丑」）
///
/// 用户原话：
///   「有点丑哇，继续优化一下，并且AI大模型按钮没显示，
///     还有搜不出这道题时，加入提示请点击大模型按钮进行联网搜题」
///
/// 本轮要锁定三件纯逻辑契约：
///   ① 未命中时的引导文案必须指向「AI 联网搜题」并说清怎么点；
///   ② 相似度胶囊文案（标题栏内联胶囊，替代独立状态行）；
///   ③ 状态驱动的胶囊配色（检索中/命中/未命中）。
void main() {
  group('未命中引导文案（搜不出这道题时提示点 AI 联网搜题）', () {
    test('未命中且未开启读屏 → 提示点 AI 按钮联网搜题', () {
      final text = QuizPluginEntry.visionMissHint(isVisionRunning: false);
      expect(text, contains('未搜到'));
      expect(text, contains('AI'));
      expect(text, contains('联网'));
      expect(text, contains('点'));
    });

    test('未命中但正在读屏 → 提示等待，不再让用户重复点', () {
      final text = QuizPluginEntry.visionMissHint(isVisionRunning: true);
      expect(text, contains('读屏'));
      expect(text, isNot(contains('点击')));
    });

    test('引导文案必须点明按钮位置与外观（右上角紫色 AI）', () {
      final text = QuizPluginEntry.visionMissHint(isVisionRunning: false);
      // 用户 2026-09-13 报障「没看到 ai 按钮」的根因之一：按钮长得不像文案说的样子。
      // 旧文案写「✨ 星星按钮」，但按钮实际是带「AI」字的紫色胶囊，用户按文案去找
      // 照星星，自然找不到。文案必须与真机外观一致。
      expect(text, anyOf(contains('右上'), contains('右上角')));
      expect(text, anyOf(contains('紫色'), contains('AI')));
      expect(text, isNot(contains('星星')),
          reason: '按钮已不是星星，文案不得再指路「星星」');
    });
  });

  group('相似度胶囊文案（标题栏内联，替代独立状态行）', () {
    test('命中态：显示百分比', () {
      expect(QuizPluginEntry.similarityPillText(90, hit: true), '90%');
    });

    test('检索中：显示读屏中，不显示百分比', () {
      expect(QuizPluginEntry.similarityPillText(null, hit: false, searching: true),
          '读屏中');
    });

    test('未命中无相似度：显示未命中', () {
      expect(QuizPluginEntry.similarityPillText(null, hit: false), '未命中');
    });

    test('胶囊文字必须短（≤6 字符），否则标题栏又会被挤爆', () {
      for (final t in [
        QuizPluginEntry.similarityPillText(90, hit: true),
        QuizPluginEntry.similarityPillText(null, hit: false, searching: true),
        QuizPluginEntry.similarityPillText(null, hit: false),
      ]) {
        expect(t.runes.length, lessThanOrEqualTo(6), reason: '「$t」太长');
      }
    });
  });

  group('胶囊配色随状态变化（视觉可辨识）', () {
    test('命中 → 绿色系', () {
      final c = QuizPluginEntry.similarityPillColor(90, hit: true);
      expect(c, '#12B76A');
    });

    test('检索中 → 琥珀色系（与进度条一致）', () {
      final c = QuizPluginEntry.similarityPillColor(null, hit: false, searching: true);
      expect(c, '#F59E0B');
    });

    test('未命中 → 中性灰', () {
      final c = QuizPluginEntry.similarityPillColor(null, hit: false);
      expect(c, '#98A2B3');
    });
  });
}
