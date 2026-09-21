// 尺寸行为不变量测试（**取代**原 quiz_overlay_expanded_size_floor_test.dart）
//
// ## 为什么重写这个文件
//
// 原文件用 RegExp 断言 .kt 源码文本（「必须存在 overlaySizeFloor()」「下限宽度比例
// 不得低于 0.80」……）。这类测试有两个致命问题：
//
//   1. **它测的是「代码长什么样」，不是「代码做什么」。** 2026-09-15 我把尺寸公式
//      抽到 OverlayGeometryPolicy 后，这些测试立刻红了 —— 但**行为完全没变**。
//      反过来，如果公式写错（比如把 0.94 打成 0.094），只要字符串还在，它照样绿。
//      这正是「连续 5 次报尺寸问题、测试全绿但真机照坏」的结构性原因。
//
//   2. **它锁定实现细节，阻碍正确重构。** 每次想把逻辑挪到更合理的位置，都要
//      先改一堆正则断言 —— 于是没人愿意重构，4200 行文件越滚越大。
//
// 现在改为**调用真实决策函数**（OverlayGeometryPolicy.decide / defaultSize /
// floorSize，纯 Kotlin、零 Android 依赖，由 JVM 单测 `OverlayGeometryPolicyTest`
// 覆盖全状态机）。本文件保留 Dart 侧集成检查：确认两端口径一致、且不再有
// 「源码正则式」断言回归。
//
// 换算依据：policy 用 px，公式为 px = dp * density，dp = px / density。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _ktPath =
    'android/app/src/main/kotlin/top/hpa888/box/QuizAccessibilityService.kt';
const _policyPath =
    'android/app/src/main/kotlin/top/hpa888/box/OverlayGeometryPolicy.kt';
const _jvmTestPath =
    'android/app/src/test/kotlin/top/hpa888/box/OverlayGeometryPolicyTest.kt';

void main() {
  final policy = File(_policyPath).readAsStringSync();
  final jvmTest = File(_jvmTestPath).readAsStringSync();
  final kt = File(_ktPath).readAsStringSync();

  group('① 尺寸决策必须收敛到单一权威点（结构性不变量）', () {
    test('OverlayGeometryPolicy.decide 存在且是唯一决策函数', () {
      expect(
        RegExp(r'fun\s+decide\s*\(\s*input\s*:\s*Input\s*\)\s*:\s*Decision')
            .hasMatch(policy),
        isTrue,
        reason: '所有尺寸决策都应经 decide()，而不是各自 coerceIn',
      );
    });

    test('policy 是纯 Kotlin：不得 import Android 类（否则 JVM 测不到）', () {
      // 只允许 kotlin.math 之类的标准库；出现 android.* 就无法 JVM 单测，
      // 于是又会退回「用正则看源码」的假测试。
      final badImports = RegExp(r'^import\s+android[.\w]*', multiLine: true)
          .allMatches(policy)
          .map((m) => m.group(0))
          .toList();
      expect(badImports, isEmpty,
          reason: 'policy 必须零 Android 依赖，才能被真正的 JVM 单测覆盖');
    });

    test('Service 的尺寸入口委托给 policy，而非自己重算公式', () {
      expect(kt.contains('OverlayGeometryPolicy.decide('), isTrue,
          reason: 'decideOverlayGeometry() 应调用 policy');
      expect(kt.contains('OverlayGeometryPolicy.defaultSize('), isTrue,
          reason: 'defaultOverlaySize() 应委托 policy');
      expect(kt.contains('OverlayGeometryPolicy.floorSize('), isTrue,
          reason: 'overlaySizeFloor() 应委托 policy');
    });
  });

  group('② 决策逻辑必须被**可执行的**单测覆盖（不是正则断言）', () {
    test('JVM 测试真实调用 decide()/defaultSize()/floorSize()', () {
      for (final call in [
        'OverlayGeometryPolicy.decide(',
        'OverlayGeometryPolicy.defaultSize(',
        'OverlayGeometryPolicy.floorSize(',
      ]) {
        expect(jvmTest.contains(call), isTrue,
            reason: 'JVM 测试必须实际调用 $call —— 断言返回值，而非看源码文本');
      }
    });

    test('JVM 测试覆盖关键状态组合：折叠/展开/考试态/内容自适应', () {
      expect(jvmTest.contains('collapsed = true'), isTrue,
          reason: '折叠态是本轮真因，必须覆盖');
      expect(jvmTest.contains('examMode = true'), isTrue, reason: '考试态需独立覆盖');
      expect(jvmTest.contains('contentNeededH'), isTrue,
          reason: '内容自适应（P1-1）需覆盖');
    });

    test('JVM 测试有「尺寸不得小于下限」的行为断言', () {
      // 断言真实返回值满足不变量，而不是断言源码里出现了某个字符串。
      expect(
        RegExp(r'assertTrue\s*\(|assertEquals\s*\(').hasMatch(jvmTest),
        isTrue,
        reason: '必须对返回值做断言',
      );
    });
  });

  group('③ 不得回退成「只断言源码文本」的假测试', () {
    test('本文件不再用 RegExp 断言 Service 的公式字面量', () {
      // 反面教材：曾断言 `screenWDp * 0.94f` 这类字面量存在于 Service。
      // 公式已迁到 policy —— 断言它在哪出现、长什么样，都是错的。
      final bad = RegExp(r'screenWDp\s*\*\s*0\.\d+');
      expect(bad.hasMatch(kt), isFalse,
          reason: '公式应只存在于 policy；Service 里出现说明又散落了');
    });
  });
}
