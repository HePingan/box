import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/quiz_plugin/presentation/quiz_plugin_entry.dart';

/// 悬浮窗标题栏排版 + 大模型搜题进度（2026-09-13 用户拍板 B/A/合并发）
///
/// 背景：AI 读屏按钮加进标题栏后，标题栏固定需求涨到 216dp，
/// 而悬浮窗在真机上只有 137~175dp 宽 → 最右侧「小眼睛/关闭」被裁掉。
/// 修法（用户拍板）：
///   1. 相似度徽章搬离标题栏（B 档：迁到状态色条行）
///   2. 标题栏只留 AI读屏/眼睛/关闭，「区域」「录入」收进溢出菜单
///   3. 眼睛点击行为不变（隐藏悬浮窗）
void main() {
  group('标题栏宽度预算', () {
    test('紧凑标题栏（3 键）在最小真机宽度下不溢出', () {
      // 3 × 26dp 按钮 + 3 × 2dp 间距 + 4dp 右内边距 = 88dp
      expect(QuizPluginEntry.overlayTitleBarWidthDp, 88);

      // 真机最小悬浮窗宽度 = 137dp（1440p / density 3.5）
      expect(
        QuizPluginEntry.overlayTitleBarFits(windowWidthDp: 137),
        isTrue,
        reason: '1440p 机型（窗宽 137dp）也必须放得下眼睛按钮',
      );
    });

    test('旧布局（徽章+5 键 = 216dp）会被判定溢出，证明本回归真实存在', () {
      expect(
        QuizPluginEntry.overlayLegacyTitleBarWidthDp,
        216,
      );
      expect(
        QuizPluginEntry.overlayTitleBarFits(
          windowWidthDp: 137,
          widthDp: QuizPluginEntry.overlayLegacyTitleBarWidthDp,
        ),
        isFalse,
        reason: '旧布局在 1440p 上溢出，正是眼睛看不见的原因',
      );
    });

    test('各档真机窗宽下紧凑标题栏均有富余', () {
      for (final w in <double>[137, 160, 175, 187]) {
        expect(
          QuizPluginEntry.overlayTitleBarFits(windowWidthDp: w),
          isTrue,
          reason: '窗宽 ${w}dp 时标题栏应放得下',
        );
        expect(
          QuizPluginEntry.overlayTitleBarSlackDp(windowWidthDp: w) > 0,
          isTrue,
        );
      }
    });
  });

  group('溢出菜单契约', () {
    test('区域与录入收进溢出菜单，标题栏不再直接持有', () {
      expect(
        QuizPluginEntry.overlayOverflowMenuKeys,
        containsAll(<String>['area', 'quizEntry']),
      );
      expect(
        QuizPluginEntry.overlayTitleBarKeys,
        <String>['aiVision', 'hideOverlay', 'close'],
        reason: '眼睛必须留在标题栏且顺序固定',
      );
      // 眼睛不能在溢出菜单里（用户拍板：点击眼睛隐藏悬浮窗）
      expect(
        QuizPluginEntry.overlayOverflowMenuKeys,
        isNot(contains('hideOverlay')),
      );
    });
  });

  group('大模型搜题进度分阶段文案', () {
    test('0-3 秒：截图识别阶段', () {
      expect(
        QuizPluginEntry.visionProgressText(Duration.zero),
        contains('识别'),
      );
      expect(
        QuizPluginEntry.visionProgressText(const Duration(seconds: 2)),
        contains('识别'),
      );
    });

    test('3-15 秒：请求大模型阶段，提示首次较慢', () {
      final t = QuizPluginEntry.visionProgressText(const Duration(seconds: 8));
      expect(t, contains('大模型'));
      expect(t, contains('首次'));
    });

    test('15 秒以上：重试阶段，必须给出最长等待预期', () {
      final t = QuizPluginEntry.visionProgressText(const Duration(seconds: 20));
      expect(t, contains('重试'));
      expect(t, contains('45'), reason: '要让用户知道最长等多久');
    });

    test('已等待秒数随进度递增，供徽章倒计时显示', () {
      expect(QuizPluginEntry.visionElapsedSeconds(Duration.zero), 0);
      expect(
        QuizPluginEntry.visionElapsedSeconds(const Duration(milliseconds: 4900)),
        4,
        reason: '未满 1 秒不进位，避免显示 0s 时跳 1s',
      );
      expect(QuizPluginEntry.visionElapsedSeconds(const Duration(seconds: 12)), 12);
    });

    test('超过总超时后仍给出兜底文案，不返回空', () {
      final t = QuizPluginEntry.visionProgressText(const Duration(seconds: 60));
      expect(t.trim(), isNotEmpty);
    });
  });
}
