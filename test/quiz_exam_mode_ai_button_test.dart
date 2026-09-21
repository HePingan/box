import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 回归：**AI 联网搜题按钮在考试模式下必须可见**。
///
/// 用户真机复现（2026-09-13 18:44 截图，驾考 App 答题中）：
/// 悬浮窗标题栏只有「未命中胶囊 + 眼睛 + 关闭」，AI 按钮和「更多」都不见了。
/// 但正文却写着「点右上角 ✨ 星星按钮，用 AI 联网搜题」—— 指路指向一个
/// 被自己藏起来的按钮。
///
/// 真因分两层，**证据强度不同，须如实区分**：
/// 1) 【已证实·主因】宽度溢出：defaultOverlaySize() 用
///    `(widthPixels*0.52).coerceIn(280,480)` 把 480 当 px 上限，iQOO
///    1440px/密度3.5 上窗仅 137dp，而标题栏静态需求 193dp(考试)/224dp(普通)。
///    按真实布局顺序回算：溢出时「更多」越界消失、AI 胶囊被左侧胶囊压住 ——
///    与用户截图完全吻合。见 test/quiz_titlebar_adaptive_test.dart。
/// 2) 【真实但次要·已防御性修复】考试模式误隐藏：若驾考 App 在前台触发
///    autoExam（空白名单 = 全部第三方 App），examMode=true 后
///    applyExamChrome 把 btn_more 收进 hideIds、又把 btn_ai_vision 置 GONE。
///    用户截图无法区分是哪个模式，故此路一并加固。
///
/// 结论：AI 联网搜题是**核心功能**（用户答题搜不出答案时唯一的联网出路），
/// 不是低频装饰入口，考试模式下必须保留可见。只有「更多/字号/调节柄」
/// 这类低频项才该在考试模式下隐藏。
void main() {
  final kt = File(
    'android/app/src/main/kotlin/top/hpa888/box/QuizAccessibilityService.kt',
  ).readAsStringSync();

  group('考试模式 chrome 可见性契约', () {
    test('btn_ai_vision 不得出现在 hideIds 隐藏列表里', () {
      final hideIdsBlock = RegExp(
        r'val hideIds = intArrayOf\((.*?)\)',
        dotAll: true,
      ).firstMatch(kt);
      expect(hideIdsBlock, isNotNull, reason: '应能找到 hideIds 数组');
      expect(
        hideIdsBlock![1]!,
        isNot(contains('R.id.btn_ai_vision')),
        reason: 'AI 联网搜题是核心功能，考试模式也必须可见',
      );
    });

    test('applyExamChrome 不得把 btn_ai_vision 置 GONE', () {
      final chrome = RegExp(
        r'private fun applyExamChrome\(view: View\)\s*\{(.*?)\n    \}',
        dotAll: true,
      ).firstMatch(kt);
      expect(chrome, isNotNull, reason: '应能找到 applyExamChrome');
      final body = chrome![1]!;
      // 允许出现 btn_ai_vision（显式置 VISIBLE 是要求），但不允许任何把它
      // 置 GONE / 收进隐藏列表的写法。
      final aiLines = body
          .split('\n')
          .where((l) => l.contains('btn_ai_vision'))
          .join('\n');
      expect(
        aiLines,
        isNot(contains('GONE')),
        reason: 'applyExamChrome 里不得把 AI 按钮置 GONE',
      );
      expect(
        aiLines,
        isNot(contains('hideIds')),
        reason: 'AI 按钮不得被收进 hideIds',
      );
    });

    test('applyExamChrome 必须显式保活 btn_ai_vision 为 VISIBLE', () {
      final chrome = RegExp(
        r'private fun applyExamChrome\(view: View\)\s*\{(.*?)\n    \}',
        dotAll: true,
      ).firstMatch(kt);
      final body = chrome![1]!;
      expect(
        body,
        contains('R.id.btn_ai_vision)?.visibility = View.VISIBLE'),
        reason: '必须显式声明 AI 按钮在考试模式可见，防止后续被误收进 hideIds',
      );
    });

    test('btn_more 仍应在考试模式隐藏（低频项，保持界面干净）', () {
      final hideIdsBlock = RegExp(
        r'val hideIds = intArrayOf\((.*?)\)',
        dotAll: true,
      ).firstMatch(kt);
      expect(
        hideIdsBlock![1]!,
        contains('R.id.btn_more'),
        reason: '更多菜单考试模式应收起',
      );
    });
  });
}
