import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 用户 2026-09-13 第五次反馈（原话）：
///   「悬浮窗大小没有变化，进行修改，把ai搜题过程写入调试日志，我分析一下，
///     顺便给他限定提示词不要调用任何工具，直接识别图片给出答案」
///
/// 三条诉求，逐条上锁：
///   ① 悬浮窗尺寸：每次启动都施加无条件的 dp 下限（旧的一次性迁移已废弃，
///      因为它只在升级后首次启动生效、跑过即作废 → 真机连报三次「没变化」）
///   ② AI 搜题过程必须写入调试日志（用户要自己分析）
///   ③ 提示词必须**显式禁止调用工具**，并要求直接识图给答案
///
/// 说明：这些断言只读源码文本，不做运行时行为验证（真机观感无法单测）。
void main() {
  final engine = File('lib/features/quiz_plugin/data/quiz_engine.dart')
      .readAsStringSync();
  final kt = File(
    'android/app/src/main/kotlin/top/hpa888/box/QuizAccessibilityService.kt',
  ).readAsStringSync();
  final entry =
      File('lib/features/quiz_plugin/presentation/quiz_plugin_entry.dart')
          .readAsStringSync();

  // ────────────────────────────────────────────────────────────────
  // ① 组已修订（2026-09-14 第六次反馈「悬浮窗还是没有变化」）：
  //
  // 原断言要求「OVERLAY_SCALE_V6 = 1.5 + schema<6 一次性迁移 + 写回 schema=6」。
  // 真机连续三次「没有变化」后查明该方案有本质缺陷：
  //   · 一次性迁移在升级后的**首次启动**即被执行并写回 schema，此后永不重跑；
  //     而尺寸只在 service 启动时应用一次 → 之后升级不再放大。
  //   · 「已保存值 ×1.5」对小保存值无意义（296dp×1.5 仍可能被屏宽夹回）。
  // 现改为**每次启动都施加的无条件 dp 下限**（coerceAtLeast(floorW/floorH)），
  // 已保存值无论多小都会被抬到下限之上，且不依赖任何一次性的 schema 门闸。
  // 断言见 quiz_region_button_and_ai_process_v7_test.dart group ①。
  // ────────────────────────────────────────────────────────────────
  group('① 悬浮窗尺寸（已改为每次启动的无条件下限）', () {
    test('必须有每次启动都生效的尺寸下限，且不再依赖一次性迁移', () {
      expect(
        RegExp(r'coerceAtLeast\(floorW\)').hasMatch(kt),
        isTrue,
        reason: '宽必须有无条件下限，旧保存值也要被抬升',
      );
      expect(
        RegExp(r'coerceAtLeast\(floorH\)').hasMatch(kt),
        isTrue,
        reason: '高必须有无条件下限',
      );
      expect(
        RegExp(r'KEY_OVERLAY_SIZE_SCHEMA, 0\) < \d').hasMatch(kt),
        isFalse,
        reason: '不得再依赖「schema < N 才放大一次」的门闸（会被消费掉）',
      );
      expect(
        RegExp(r'OVERLAY_SCALE_V6').hasMatch(kt),
        isFalse,
        reason: 'OVERLAY_SCALE_V6 已随一次性迁移一并删除',
      );
    });

    test('默认尺寸必须按 dp 计算（不再 px/dp 混用）', () {
      // 2026-09-15 修订（同 quiz_overlay_width_and_vision_timeout_test）：尺寸公式
      // 已抽到 OverlayGeometryPolicy，故按**语义**断言，不再断言 Service 某函数体
      // 里出现某字符串（位置断言会因合理重构假红、因公式写错假绿）。
      final body = _funBody(kt, 'defaultOverlaySize');
      final code = body
          .split('\n')
          .map((l) => l.replaceAll(RegExp(r'//.*$'), ''))
          .join('\n');
      expect(
        code.contains('coerceIn(280, 480)'),
        isFalse,
        reason: '旧的 px 字面量夹取必须消失（iQOO 上曾把窗口卡成 137dp）',
      );
      // 公式本体在 policy：确认它按 density 换算 dp，且宽度锚定 dp 常量。
      final policy = File(
        'android/app/src/main/kotlin/top/hpa888/box/OverlayGeometryPolicy.kt',
      ).readAsStringSync();
      expect(
        RegExp(r'density').hasMatch(policy),
        isTrue,
        reason: 'policy 必须用真实 density 换算 dp',
      );
      expect(
        RegExp(r'MIN_WIDTH_DP').hasMatch(policy),
        isTrue,
        reason: '宽度下限必须锚定 dp 常量（语义断言）',
      );
    });
  });

  group('② AI 搜题过程写入调试日志（用户要自己分析）', () {
    test('必须逐次记录请求：剩余预算 + 第几次', () {
      expect(
        RegExp(r'第\$\{attempt \+ 1\}次请求').hasMatch(engine),
        isTrue,
        reason: '日志要能看出重试了几次、每次剩余预算多少',
      );
    });

    test('必须记录每次响应耗时与 finish_reason', () {
      expect(
        RegExp(r'finish=\$\{_visionFinishReason\(decoded\)\}').hasMatch(engine),
        isTrue,
        reason: 'finish_reason 是判断「退化响应」的关键证据',
      );
      expect(
        RegExp(r'attemptMs').hasMatch(engine),
        isTrue,
        reason: '每次请求的单次耗时必须记录',
      );
    });

    test('必须记录图片/提示词体量，便于判断是否 payload 过大', () {
      expect(
        RegExp(r'原图=\$\{imageBytes\.length\}B').hasMatch(engine),
        isTrue,
      );
      expect(
        RegExp(r'b64=\$\{b64\.length\}B').hasMatch(engine),
        isTrue,
      );
    });

    test('日志必须带请求序号 tag，多题并发时能对上', () {
      expect(RegExp(r"final tag = 'VISION#").hasMatch(engine), isTrue);
    });

    test('日志必须走 LogChannel.quiz（用户在「题库」筛选里看）', () {
      expect(
        RegExp(r'_visionLog[\s\S]{0,200}LogChannel\.quiz').hasMatch(engine),
        isTrue,
        reason: '落错频道用户就筛不到，等于没写',
      );
    });

    test('日志不得泄露 API Key', () {
      expect(
        RegExp(r'_visionLog\([^)]*apiKey', caseSensitive: false).hasMatch(engine),
        isFalse,
        reason: '调试日志会被用户复制外发，绝不能带密钥',
      );
    });

    test('原生侧尺寸诊断必须经 nativeDebugLog 汇入同一日志库', () {
      expect(
        RegExp(r'"nativeDebugLog"').hasMatch(kt),
        isTrue,
        reason: '原生 density/尺寸是判断「大小没变化」的唯一事实来源',
      );
      expect(
        RegExp(r"call\.method == 'nativeDebugLog'").hasMatch(entry),
        isTrue,
        reason: 'Flutter 侧必须有对应分支接住',
      );
    });
  });

  group('③ 提示词：禁止调用工具 + 直接识图作答', () {
    test('必须显式禁止调用任何工具/函数/代码解释器', () {
      // 提示词是 Dart 字符串常量，注释删除对字符串字面量无效，
      // 因此这里直接匹配字符串内文本即可。
      expect(
        RegExp(r'禁止调用任何工具').hasMatch(engine),
        isTrue,
        reason: '实测模型会钻进代码解释器循环，必须明文禁止',
      );
      expect(
        RegExp(r'禁止.*代码解释器').hasMatch(engine),
        isTrue,
      );
    });

    test('必须声明「没有工具可用」并直接给答案', () {
      expect(
        RegExp(r'你没有任何工具可用').hasMatch(engine),
        isTrue,
        reason: '弱模型对「你没有工具」比「禁止用工具」更敏感',
      );
      expect(
        RegExp(r'直接看这张图').hasMatch(engine),
        isTrue,
      );
    });

    test('必须禁止输出思考过程/计划（实测思维链吃掉全部延迟）', () {
      expect(
        RegExp(r'禁止输出思考过程').hasMatch(engine),
        isTrue,
      );
    });

    test('API 层必须加 tool_choice=none（比提示词更硬的约束）', () {
      // 去掉注释再断言：否则「被注释掉的 tool_choice」也能骗过正则，
      // 变成假绿 —— 已用反向验证确认过这个坑。
      final code = engine
          .split('\n')
          .map((l) => l.replaceAll(RegExp(r'^\s*//.*$'), ''))
          .join('\n');
      expect(
        RegExp(r"'tool_choice':\s*'none'").hasMatch(code),
        isTrue,
        reason: '实测该字段让 29.9s/content=null 变成 15.4s/正常答案',
      );
    });
  });
}

/// 取某个顶层 fun 的完整函数体（按大括号配平），避免定长窗口正则
/// 在函数变长后静默匹配不到（这个坑已经踩过一次）。
String _funBody(String src, String funName) {
  final start = src.indexOf('fun $funName');
  if (start < 0) return '';
  final open = src.indexOf('{', start);
  if (open < 0) return '';
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) return src.substring(open, i + 1);
    }
  }
  return '';
}
