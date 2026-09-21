import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 回归：**标题栏按可用宽度自适应**（用户 2026-09-13 拍板「B 方案」）。
///
/// 真因回顾：`defaultOverlaySize()` 用 `(widthPixels*0.52).coerceIn(280,480)`，
/// 把 480 当成 **px** 上限 —— iQOO 1440px/密度3.5 上窗只有 137dp，而标题栏
/// 需要 193~224dp → 横向溢出，右侧按钮被裁（用户截图里 AI + 更多 正好消失）。
///
/// 用户选择：**不改窗宽**，让标题栏自适应 —— 按优先级「让位」：
///   AI搜题（核心，必须保位）> 关闭 > 眼睛 > 更多 > 状态胶囊
/// 空间不足时从最低优先级开始收起；胶囊可缩到只剩圆点。
void main() {
  final kt = File(
    'android/app/src/main/kotlin/top/hpa888/box/QuizAccessibilityService.kt',
  ).readAsStringSync();

  /// 按花括号配平提取某个函数的完整函数体（非贪婪正则会在第一个内层 `}` 断掉）。
  String? fnBody(String signature) {
    final i = kt.indexOf(signature);
    if (i < 0) return null;
    final j = kt.indexOf('{', i);
    if (j < 0) return null;
    var depth = 0;
    for (var k = j; k < kt.length; k++) {
      final c = kt[k];
      if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) return kt.substring(j, k + 1);
      }
    }
    return null;
  }

  /// 取某个 findViewById 绑定到的局部变量名，例如
  /// `val ai = view.findViewById<View>(R.id.btn_ai_vision)` → `ai`。
  String? varFor(String body, String id) {
    final m = RegExp(
      r'val\s+(\w+)\s*=\s*view\.findViewById<[^>]*>\(R\.id\.' + id + r'\)',
    ).firstMatch(body);
    return m?[1];
  }

  group('标题栏自适应契约', () {
    test('存在自适应函数（按可用宽度收缩）', () {
      expect(kt, contains('applyTitleBarAdaptive'),
          reason: '需要专门的标题栏自适应函数处理窄窗');
    });

    test('AI 按钮在自适应里必须保活为 VISIBLE，绝不被藏', () {
      final body = fnBody('private fun applyTitleBarAdaptive');
      expect(body, isNotNull, reason: '应能找到 applyTitleBarAdaptive');

      // 通过局部变量名定位真正的可见性赋值行（Kotlin 惯用 val ai = ...; ai?.visibility = ...）
      final aiVar = varFor(body!, 'btn_ai_vision') ?? 'ai';
      final assign = RegExp(
        r'\b' + RegExp.escape(aiVar) + r'\??\.visibility\s*=\s*([^\n]+)',
      ).allMatches(body).map((m) => m[1]!.trim()).toList();
      expect(assign, isNotEmpty, reason: '应有设置 AI 按钮可见性的语句');
      expect(assign.any((v) => v.contains('GONE')), isFalse,
          reason: 'AI 按钮绝不能被藏掉 —— 它就是用户找不到的那个');
      expect(assign.any((v) => v.contains('VISIBLE')), isTrue,
          reason: 'AI 按钮在自适应里必须显式保活为 VISIBLE');
    });

    test('方案 A 后「更多」不再让位：按钮恒可见，溢出交给横向滑动', () {
      // 方案 A（用户 2026-09-15 拍板）取代了「窄窗下把 ⋯ 让位隐藏」的旧设计。
      // 旧设计让用户以为功能丢失（第 5 次反馈「框选按钮找不到」同源）。
      // 新设计：所有按钮恒 VISIBLE，放不下就横向滑动。
      final body = fnBody('private fun applyTitleBarAdaptive');
      expect(body, isNotNull, reason: '应存在 applyTitleBarAdaptive');
      // ⋯ 必须被显式保活为 VISIBLE
      expect(body!, contains('more?.visibility = View.VISIBLE'),
          reason: '方案 A 下「更多」必须常驻可见，不得再按宽度 GONE');
      // 旧行为不得复活：不再直接出现 more GONE
      expect(body.contains('more?.visibility = View.GONE'), isFalse,
          reason: '「更多」不得再被按宽度隐藏（方案 A 已推翻该行为）');
      // 旧预算逻辑应被隔离进回退函数，主路径默认不执行
      expect(body.contains('TITLE_ACTIONS_SCROLL_ENABLED'), isTrue,
          reason: '方案 A 须有显式开关，便于回退；主路径默认走滑动方案');
    });

    test('方案 A 后胶囊不再收缩让位（恒可见，属拖动热区）', () {
      final body = fnBody('private fun applyTitleBarAdaptive');
      expect(body, isNotNull);
      // 胶囊在方案 A 下是拖动热区的一部分，必须恒 VISIBLE
      expect(body!.contains('tv_similarity_badge'), isTrue,
          reason: '自适应仍须确保胶囊可见');
      // 窄窗 GONE 的老行为应移出主路径
      expect(body.contains('badge.visibility = View.GONE'), isFalse,
          reason: '方案 A 下胶囊不得再被隐藏：它是拖动热区，隐藏后窄窗抓不住窗口');
    });

    test('自适应在进入考试模式/应用 chrome 后会被调用', () {
      final chrome = fnBody('private fun applyExamChrome');
      expect(chrome, isNotNull);
      expect(chrome, contains('applyTitleBarAdaptive(view)'),
          reason: '模式切换后必须重排标题栏');
    });
  });
}
