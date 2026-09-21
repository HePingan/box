import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 用户 2026-09-13 第四次反馈（真机截图 + 文字）：
///   「还是很拥挤，还得扩大长宽高，扩大1.5倍，
///     ai搜题还是有问题，以前10秒不到可以出，现在半天出不了，继续优化」
///
/// 两件事：
///   G. 悬浮窗长宽高整体 ×1.5（含对已保存尺寸的一次性放大迁移）
///   H. AI 搜题退化：上游对「像真题的复杂截图」返回
///      finish_reason=tool_calls + content=null（代码解释器循环），
///      30s+ 且必然无结果。客户端必须①识别该形态②别把重试预算耗光
///      ③给出能看懂的提示，而不是「读屏返回无法解析」。

/// 取出 Kotlin 函数体（按花括号配对，不受注释内括号影响）。
///
/// 必须是**顶层函数**：放在 main() 内会被 Dart 视为局部变量，
/// 在其声明处之前调用会报「can't be referenced before it is declared」。
String funBody(String src, String signature) {
  final start = src.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: '未找到 $signature');
  var i = src.indexOf('{', start);
  var depth = 0;
  final buf = StringBuffer();
  for (; i < src.length; i++) {
    final c = src[i];
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) {
        buf.write(c);
        break;
      }
    }
    buf.write(c);
  }
  return buf.toString();
}

void main() {
  // 注：G 组尺寸断言已改查 OverlayGeometryPolicy（见下），故不再读 Service 源码。
  final engine = File(
    '/root/box/lib/features/quiz_plugin/data/quiz_engine.dart',
  ).readAsStringSync();

  // ────────────────────────────────────────────────────────────────
  // G 组已修订（2026-09-14，用户第 5 次反馈「悬浮窗还是没有变化」）：
  //
  // 原断言要求「OVERLAY_SCALE_V6 = 1.5 + schema<6 一次性迁移」。真机连报
  // 三次「没有变化」后查明：**一次性迁移本身是错的**——
  //   · 升级到 250 的那一次启动就把迁移消费掉了，之后再升级永不放大；
  //   · 且「保存值 ×1.5」对本来就小的保存值毫无意义（296dp 还是偏小）。
  // 现改为**每次启动都施加的无条件下限**（见 v7 测试 group ①）。
  // 故此处只保留「不得超出屏幕」这条仍然成立的红线。
  // ────────────────────────────────────────────────────────────────
  group('G. 悬浮窗尺寸（已改为无条件下限，见 v7 测试）', () {
    // 2026-09-15 修订：尺寸决策已抽到 OverlayGeometryPolicy（P0-1 单一事实源）。
    // 原断言检查 Service 里 defaultOverlaySize() 的**内联函数体**是否含某个
    // 字符串/正则 —— 公式迁走后假红，而窗口行为未变。改为对 policy 断语义。
    test('默认尺寸仍不得超出屏幕宽度（夹取在屏内）', () {
      final policy = File(
        '/root/box/android/app/src/main/kotlin/top/hpa888/box/OverlayGeometryPolicy.kt',
      ).readAsStringSync();
      // 语义：宽度取屏宽的一定比例，且**必须被屏宽夹住**，不得溢出。
      expect(
        RegExp(r'coerceAtMost\(input\.screenW\)').hasMatch(policy),
        isTrue,
        reason: '宽度上限必须夹到屏幕宽，否则高密度机会溢出',
      );
      expect(
        RegExp(r'DEFAULT_WIDTH_RATIO').hasMatch(policy),
        isTrue,
        reason: '默认宽度应按屏宽比例（而非裸 px）',
      );
    });

    test('下限锚定 dp 常量、上限受屏幕夹取（无裸 px 字面量）', () {
      final policy = File(
        '/root/box/android/app/src/main/kotlin/top/hpa888/box/OverlayGeometryPolicy.kt',
      ).readAsStringSync();
      expect(
        RegExp(r'MIN_WIDTH_DP\s*=\s*240').hasMatch(policy),
        isTrue,
        reason: '下限必须锚定 dp 常量',
      );
      // 红线：policy 里不得复活 px/dp 混用的旧裸 px 上限。
      expect(
        RegExp(r'coerceIn\(\s*(280|480)\s*,').hasMatch(policy),
        isFalse,
        reason: '不得复活 px/dp 混用的旧上限',
      );
    });
  });

  group('H. AI 搜题退化响应', () {
    test('必须有 _isDegenerateVisionResponse 判定', () {
      expect(
        RegExp(r'bool _isDegenerateVisionResponse').hasMatch(engine),
        isTrue,
        reason: 'tool_calls + content=null 的形态必须被识别',
      );
      expect(
        RegExp(r'toolCalls is List && toolCalls\.isNotEmpty').hasMatch(engine),
        isTrue,
        reason: '判定依据是 message.tool_calls 非空',
      );
    });

    test('退化响应必须给出可操作提示，而非「无法解析」', () {
      expect(
        engine.contains('AI 读图失败（模型未给出答案），可重试或改用手动录入'),
        isTrue,
        reason: '用户看不懂「读屏返回无法解析」，且需要知道能改手动录入',
      );
    });

    test('诊断日志必须记录 finish_reason，便于真机定位', () {
      expect(
        RegExp(r'_visionFinishReason\(decoded\)').hasMatch(engine),
        isTrue,
      );
      expect(
        RegExp(r'String _visionFinishReason').hasMatch(engine),
        isTrue,
      );
    });

    test('content 为空时必须回落到 reasoning_content 取 JSON', () {
      expect(
        RegExp(r"message\['reasoning_content'\]").hasMatch(engine),
        isTrue,
        reason: '实测该渠道把结果塞在 reasoning_content，只读 content 会漏',
      );
    });

    test('超时必须按剩余预算签发，总时长封顶 hardTimeout', () {
      expect(
        RegExp(r'\.timeout\(remaining\)').hasMatch(engine),
        isTrue,
        reason: '每次重试重起 45s 会把总耗时拖成几分钟',
      );
      expect(
        RegExp(r'remaining\s*<=\s*Duration\.zero').hasMatch(engine),
        isTrue,
      );
    });
  });
}
