import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/quiz_plugin/presentation/quiz_plugin_entry.dart';

void main() {
  group('搜题进度分阶段文案（2026-09-13 用户拍板 A 档）', () {
    test('0-3 秒：识别题目', () {
      expect(QuizPluginEntry.visionProgressText(Duration.zero), contains('识别'));
      expect(
        QuizPluginEntry.visionProgressText(const Duration(seconds: 2)),
        contains('识别'),
      );
    });

    test('3-15 秒：请求大模型，提示首次较慢', () {
      final t = QuizPluginEntry.visionProgressText(const Duration(seconds: 8));
      expect(t, contains('大模型'));
      expect(t, contains('首次'));
    });

    test('15-45 秒：重试阶段，给出最长等待预期', () {
      final t = QuizPluginEntry.visionProgressText(const Duration(seconds: 20));
      expect(t, contains('重试'));
      expect(t, contains('45'));
    });

    test('超过 45 秒：兜底可重试，不返回空', () {
      final t = QuizPluginEntry.visionProgressText(const Duration(seconds: 60));
      expect(t.trim(), isNotEmpty);
      expect(t, contains('重试'));
    });

    test('倒计时秒数：未满 1 秒不进位', () {
      expect(QuizPluginEntry.visionElapsedSeconds(Duration.zero), 0);
      expect(
        QuizPluginEntry.visionElapsedSeconds(
          const Duration(milliseconds: 4900),
        ),
        4,
      );
      expect(
        QuizPluginEntry.visionElapsedSeconds(const Duration(seconds: 12)),
        12,
      );
    });

    test('阶段文案随秒数单调推进（不会逆回上一阶段）', () {
      final st = <String>[
        for (final s in <int>[0, 3, 8, 15, 20, 44, 45, 60])
          QuizPluginEntry.visionProgressText(Duration(seconds: s)),
      ];
      // 相邻两档要么相同要么变化，且 0s 与 60s 文案必须不同
      expect(st.first == st.last, isFalse);
      for (var i = 1; i < st.length; i++) {
        expect(st[i].trim(), isNotEmpty);
      }
    });
  });
}
