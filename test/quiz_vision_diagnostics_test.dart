// 读屏链路「答案侧」必须有日志 + 手动截图要真的补试（2026-11-19 自检页教训）。
//
// 真机自检（12:26:01）暴露两件事：
//   ① 后端那三次读屏（12:23:56 / 12:24:45 / 12:24:55）**全部 200 且返回了带 answer
//      的 JSON**（我用同一批真实截图复跑证实），但自检页里连一行答案侧的日志都没有
//      —— 因为那些日志只进了 AppLogger，而「复制结论」只带 QuizDiag 环形缓冲。
//      定位成本从「看一行日志」变成「靠猜」。
//   ② `12:25:36 截图快速回空，补一次` → `读屏跳过：未拿到截图 manual=true`：
//      手动点了 AI 按钮，只补 1 次 / 250ms 就放弃，用户视角是「点了没反应」。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final engineSrc = File('lib/features/quiz_plugin/data/quiz_engine.dart');
  final entrySrc =
      File('lib/features/quiz_plugin/presentation/quiz_plugin_entry.dart');

  group('读屏链路日志必须进 QuizDiag（自检页才看得到）', () {
    test('_visionLog 双写 AppLogger + QuizDiag', () {
      final s = engineSrc.readAsStringSync();
      final i = s.indexOf('void _visionLog(');
      expect(i, greaterThan(0));
      final body = s.substring(i, i + 900);
      expect(body.contains('AppLogger.instance.logTo'), isTrue);
      expect(body.contains('QuizDiag.log('), isTrue,
          reason: '只进 AppLogger 的话，用户复制的自检结论里看不到任何答案侧证据');
    });
  });

  group('手动截图补试', () {
    test('captureRegionScreenshot 支持多次补试且间隔递增', () {
      final s = entrySrc.readAsStringSync();
      expect(s.contains('int extraAttempts = 1'), isTrue);
      expect(s.contains('const delays = [250, 600, 1200];'), isTrue,
          reason: '一次 250ms 撞不过翻题竞争');
    });

    test('手动读屏传 3 次补试，自动档仍只补 1 次（不拖慢自动流程）', () {
      final s = entrySrc.readAsStringSync();
      expect(s.contains('extraAttempts: manual ? 3 : 1'), isTrue);
    });

    test('截图失败要如实告知并记录补试次数', () {
      final s = entrySrc.readAsStringSync();
      expect(s.contains("'retried': manual ? 3 : 1"), isTrue);
      expect(s.contains('visionCaptureFailureHint()'), isTrue,
          reason: '手动失败要给「没截到屏」的专属文案，不能退化成「未搜到」');
    });
  });
}
