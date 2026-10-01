// 读屏时限阶梯：这些值之间有**必须成立的大小关系**，散着改一个就会漂移
// （症状不是报错，而是"永远转圈"或"误杀正在正常推进的慢请求"）。
//
// 2026-10-01 事故背景：截图等待没有终点 → await 永不返回 → 界面永远"读屏中"、
// 服务端零请求。补完终点之后，第二件事就是把这些终点**锁成一套口径**。
import 'dart:io';

import 'package:box/features/quiz_plugin/domain/quiz_vision_timeouts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('读屏时限阶梯', () {
    test('原生看门狗 < Dart 截图等待 < 流程兜底', () {
      expect(
        QuizVisionTimeouts.kotlinCaptureWatchdog,
        lessThan(QuizVisionTimeouts.capture),
        reason: '原生要先自己收尾（回 null），Dart 侧超时只该做兜底',
      );
      expect(
        QuizVisionTimeouts.capture,
        lessThan(QuizVisionTimeouts.flow),
        reason: '单阶段超时不该晚于流程兜底',
      );
      expect(
        QuizVisionTimeouts.channel,
        lessThan(QuizVisionTimeouts.capture),
        reason: '普通通道（悬浮窗/权限）比截图更快，超时也不该更长',
      );
    });

    test('各阶段之和 ≤ 兜底：否则兜底会掐死还在正常推进的流程', () {
      final worst =
          QuizVisionTimeouts.capture +
          QuizVisionTimeouts.resolve +
          QuizVisionTimeouts.engineHard +
          QuizVisionTimeouts.channel;
      expect(
        worst,
        lessThanOrEqualTo(QuizVisionTimeouts.flow),
        reason: '最坏路径 $worst 必须装得进 ${QuizVisionTimeouts.flow}',
      );
    });

    test('兜底比引擎硬顶宽出一截（不能贴着引擎走）', () {
      expect(
        QuizVisionTimeouts.flow - QuizVisionTimeouts.engineHard,
        greaterThanOrEqualTo(const Duration(seconds: 20)),
        reason: '兜底贴着引擎硬顶会变成"误杀"而不是"兜底"',
      );
    });

    test('框选等用户交互不能短超时', () {
      expect(
        QuizVisionTimeouts.userInteraction,
        greaterThan(QuizVisionTimeouts.channel),
      );
      expect(
        QuizVisionTimeouts.userInteraction.inSeconds,
        greaterThanOrEqualTo(60),
        reason: '框选要等用户拖拽，短超时会让框选一进去就"失败"',
      );
    });

    test('Kotlin 常量与 Dart 声明一致（跨语言核对源码）', () {
      final file = File(
        'android/app/src/main/kotlin/top/hpa888/box/QuizAccessibilityService.kt',
      );
      expect(file.existsSync(), isTrue, reason: '原生服务源码是这一层的另一半');
      final match = RegExp(
        r'CAPTURE_WATCHDOG_MS\s*=\s*(\d+)L',
      ).firstMatch(file.readAsStringSync());
      expect(
        match,
        isNotNull,
        reason: '原生看门狗常量必须在：截图回包被顶掉时靠它收尾',
      );
      expect(
        int.parse(match!.group(1)!),
        QuizVisionTimeouts.kotlinCaptureWatchdog.inMilliseconds,
        reason: '改了 Dart 忘改 Kotlin（或反过来）：两侧收尾次序会漂移',
      );
    });
  });
}
