// 回归测试：用户 2026-09-14 反馈
// 「继续优化悬浮窗显示，加入自适应，还有ai搜题这个显示咋只有一半，我看不完全」
//
// 真机截图证据：AI 助手屏幕分析中，底部「AI 作答过程」面板只露出上半部分
// （① 读屏截图1547KB → 压缩至585KB 之后就被窗口底边截断）。
//
// 根因（读代码确认）：
//   ensureAnswerOverlayFitsContent() 求和窗口需求高度时**完全没算 ai_process_box**，
//   只算了 title + status + divider + question + answer.height。
//   于是过程框一出现就落在窗口底边之外 → 被裁掉 → 用户只看到一半。
//
// 本测试锁定修复：
//   ① 窗口需求高度必须把 ai_process_box / vision_progress_box 计入；
//   ② 答案区不得再用 layout_weight=1 独占剩余空间（否则把过程框顶出窗外）；
//   ③ 过程框有独立可滚动区（maxHeight），内容超出时用户仍能滚完全部。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

/// 去掉注释行与行尾注释，避免历史注释里的反面教材误命中断言。
String _code(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .map((l) => l.replaceAll(RegExp(r'//.*$'), ''))
    .join('\n');

void main() {
  final kt = _code(_read(
    'android/app/src/main/kotlin/top/hpa888/box/QuizAccessibilityService.kt',
  ));
  final xml = _code(_read('android/app/src/main/res/layout/quiz_overlay.xml'));

  group('① 窗口自适应必须把 AI 过程框计入需求高度', () {
    // 2026-09-15 修订：原断言检查 `ensureAnswerOverlayFitsContent` 函数体里是否
    // 出现 `R.id.ai_process_box` / `processH` / `0.92f` 等**字面量**。P0-1 把尺寸
    // 决策抽到 OverlayGeometryPolicy 后，这些断言全部假红 —— 而窗口行为没变。
    // 这正是「正则看源码」测试的通病：测位置不测行为。
    // 现改为断言**语义**：过程框确实进入内容高度求和，且上限由 policy 决定。
    test('内容需求高度必须把 AI 过程框算进去', () {
      final start = kt.indexOf('private fun currentContentNeededHeight');
      expect(start, greaterThan(0), reason: '应有内容高度求和函数');
      final end = kt.indexOf('\n    private fun ', start + 10);
      final body = kt.substring(start, end > 0 ? end : start + 2000);
      expect(body.contains('R.id.ai_process_box'), isTrue,
          reason: '需求高度必须把 AI 过程框算进去，否则过程框被窗口底边裁掉');
      expect(body.contains('hasPendingAiProcess'), isTrue,
          reason: '仅当过程框确实有待展示内容时才计入（与可见性同口径）');
    });

    test('求和必须用固有高度，而不是会被窗口夹缩的 height（P1-1 滞后）', () {
      final start = kt.indexOf('private fun currentContentNeededHeight');
      final end = kt.indexOf('\n    private fun ', start + 10);
      final body = kt.substring(start, end > 0 ? end : start + 2000);
      expect(body.contains('intrinsicHeight'), isTrue,
          reason: '必须用固有高度，否则「窗口小→测得小→不长大」死锁');
      expect(
        RegExp(r'current\.height\s*\)').hasMatch(body),
        isFalse,
        reason: '不得再用被夹后的 current.height 做决策',
      );
    });

    test('窗口高度上限由 policy 统一决定（不再是散落的 0.92f）', () {
      // 上限语义：展开高度不得超过屏高一定比例。policy 里应有该比例常量。
      final policy = File(
        'android/app/src/main/kotlin/top/hpa888/box/OverlayGeometryPolicy.kt',
      ).readAsStringSync();
      final m = RegExp(r'CONTENT_FIT_MAX_HEIGHT_RATIO\s*=\s*([\d.]+)').firstMatch(policy);
      expect(m, isNotNull, reason: 'policy 应有屏高占比上限常量');
      final ratio = double.parse(m!.group(1)!);
      expect(ratio, greaterThanOrEqualTo(0.9),
          reason: '上限应≥0.90（旧 0.82 太矮，长内容放不全）');
    });

    test('自适应允许收敛但有下限保护（决策 3：允许收敛）', () {
      // 2026-09-15 用户拍板「允许收敛」：原「只增高不缩小」会让窗口一旦被
      // 大内容撑开后永不回收，短答案也留一大片空白。
      // 现改为可缩小，但**绝不小于下限**（避免收回成小窗）。
      final policy = File(
        'android/app/src/main/kotlin/top/hpa888/box/OverlayGeometryPolicy.kt',
      ).readAsStringSync();
      expect(policy.contains('coerceAtLeast(floorH)') ||
              policy.contains('coerceIn(floorH'),
          isTrue,
          reason: '收敛必须带下限保护，否则会缩回小窗（用户连报五次的问题）');
    });
  });

  group('② 答案区不得独占剩余高度（否则把过程框顶出窗外）', () {
    test('scroll_answer 不再使用 layout_weight=1', () {
      final start = xml.indexOf('android:id="@+id/scroll_answer"');
      expect(start, greaterThan(0));
      // 取该 ScrollView 标签区间
      final tagStart = xml.lastIndexOf('<ScrollView', start);
      final tagEnd = xml.indexOf('>', start);
      final tag = xml.substring(tagStart, tagEnd);
      expect(tag.contains('layout_weight'), isFalse,
          reason: 'weight=1 会让答案区吃掉全部剩余空间，把下方过程框顶出窗外');
      expect(tag.contains('wrap_content'), isTrue,
          reason: '答案区应改为内容驱动高度');
      expect(tag.contains('maxHeight'), isTrue,
          reason: '答案区自身要有滚动上限，长答案不至于无限膨胀');
    });
  });

  group('③ AI 过程框可看全', () {
    test('过程框有可滚动区且给了足够高度', () {
      final start = xml.indexOf('android:id="@+id/scroll_ai_process"');
      expect(start, greaterThan(0));
      final tagStart = xml.lastIndexOf('<ScrollView', start);
      final tagEnd = xml.indexOf('>', start);
      final tag = xml.substring(tagStart, tagEnd);
      expect(tag.contains('ScrollView'), isTrue, reason: '内容超长时可滚动看全');
      final m = RegExp(r'android:maxHeight="(\d+)dp"').firstMatch(tag);
      expect(m, isNotNull, reason: '应有明确的 maxHeight');
      final maxH = int.parse(m!.group(1)!);
      expect(maxH, greaterThanOrEqualTo(150),
          reason: '过程框高度上限应≥150dp，否则一屏看不全几行（原 120dp 偏窄）');
    });

    test('过程框在结构上位于窗口容器内、紧跟答案区之后', () {
      final aiIdx = xml.indexOf('android:id="@+id/ai_process_box"');
      final ansIdx = xml.indexOf('android:id="@+id/scroll_answer"');
      expect(ansIdx, greaterThan(0));
      expect(aiIdx, greaterThan(ansIdx),
          reason: '过程框应在答案区之后（视觉上「答题悬浮窗下面」）');
      // 必须仍在 answer_container 内（其闭合标签之后才结束）
      final containerEnd = xml.indexOf('</LinearLayout>', aiIdx);
      expect(containerEnd, greaterThan(aiIdx), reason: '过程框应闭合在窗口容器内，不被裁到窗外');
    });
  });

  group('④ 过程框默认展开（用户不必先找到「展开」）', () {
    test('updateAiProcess 首次有内容时自动展开', () {
      final start = kt.indexOf('fun updateAiProcess(');
      expect(start, greaterThan(0));
      final end = kt.indexOf('\n    private fun ', start + 10);
      final body = kt.substring(start, end > 0 ? end : start + 2000);
      expect(body.contains('scroll_ai_process'), isTrue,
          reason: '应在有内容时展开过程框，避免用户以为内容丢失');
      // 2026-09-19：布尔 aiProcessUserCollapsed 升级为三态 aiProcessIntent
      //（AiProcessPanelPolicy），新增「手动展开→答案就绪不自动收起」。
      expect(body.contains('aiProcessIntent'), isTrue,
          reason: '用户手动收起后不应再自动弹开（尊重用户选择）');
    });

    test('已发生手写收起的标记变量存在', () {
      expect(kt.contains('aiProcessIntent'), isTrue);
    });

    test('用户手动展开后，答案就绪不再自动收起（2026-09-19 报障）', () {
      // 决策 1.B 的自动收起必须先问策略：EXPANDED（用户本轮展开过）→ 跳过。
      final guard = kt.indexOf('shouldAutoCollapseOnAnswerReady(aiProcessIntent)');
      expect(guard, greaterThan(0),
          reason: 'autoCollapseAiProcessOnAnswerReady 应经策略判断，手动展开不被同题重复渲染收回');
    });
  });
}
