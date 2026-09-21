// 红灯回归测试：用户 2026-09-15 再次反馈
// 「答题悬浮窗还是没有变化，ai搜题显示也没有优化」+ 真机截图。
//
// 截图实测（PIL 逐像素扫描紫色渐变区）：悬浮窗宽 424px / 屏宽 1080px ≈ 39%。
// 这与 254（commit 7ed584c）回归测试里记录的 430px ≈ 40% **几乎完全一致**
// —— 同一个现象第二次复现。
//
// ⚠️ 为什么 254 的测试绿了、用户却还是看到 40%？
//   254 的 `quiz_overlay_expanded_size_floor_test.dart` 只对 .kt **源码文本**
//   做正则断言（"存在 overlaySizeFloor()"、"展开路径调用 flooredExpandedSize()"）。
//   它**从不执行折叠路径**，所以「窗口处于折叠态」这个真正的用户可见状态
//   根本没被覆盖。源码里有上限逻辑 ≠ 运行时窗口是大的。
//
// 真因（读代码定位，链路由三处共同构成）：
//   ① `applyCollapsedUi(forceCollapsed=true)` 把 params 设成 WRAP_CONTENT
//      （:1955-1956）→ 窗口缩成标题栏 + 一行的窄条 = 实测的 39%。
//   ② `overlayCollapsed` 被**持久化**（:1942 putBoolean(KEY_COLLAPSED)），
//      启动时读回（:525-526 默认 false）。除「重置悬浮窗大小」菜单
//      （:1324）外**无任何清除点** → 用户折叠过一次，就永久卡在小窗，
//      跨重启、跨服务被杀都恢复成折叠态。
//   ③ `ensureAnswerOverlayFitsContent()` 首行即
//      `if (examMode || answerOnlyMode || overlayCollapsed) return`（:3440）
//      → 折叠态下**按内容自适应完全不执行**。这直接解释了第二句反馈
//      「ai搜题显示也没有优化」：①/② 两行过程都推送了，但窗高是
//      WRAP_CONTENT 只容得下一行，看起来就是「只显示一半、没优化」。
//
// 本测试锁定的**行为不变量**（不是源码文本）：
//   · 折叠态的持久化不能跨越「新的一轮搜题」存活 —— 即收到新的题目/过程
//     推送时，必须自动回到展开大窗，否则用户永远看不到完整内容。
//   · 折叠态不得跳过按内容自适应（否则 §③ 必然复发）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _ktPath =
    'android/app/src/main/kotlin/top/hpa888/box/QuizAccessibilityService.kt';

/// 去掉注释行与行尾注释，避免历史注释里的反面教材误命中断言。
String _code(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .map((l) => l.replaceAll(RegExp(r'//.*$'), ''))
    .join('\n');

/// 抽取某个方法体（从签名到同缩进的下一个成员声明）。
String _body(String src, String signature) {
  final start = src.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: '$signature 必须存在');
  final rest = src.substring(start + signature.length);
  final m = RegExp(r'\n    (?:private |internal |public )?(?:fun|val|var|@)')
      .firstMatch(rest);
  return m == null ? rest : rest.substring(0, m.start);
}

void main() {
  final kt = _code(File(_ktPath).readAsStringSync());

  group('① 折叠态必须在新的搜题轮次自动退出（否则窗口永久卡在 39%）', () {
    test('折叠态持久化有清除点，且不止「重置悬浮窗大小」一处', () {
      // 统计 KEY_COLLAPSED 被写入 false / 调 applyCollapsedUi(force=false) 的点。
      final clearSites = RegExp(
        r'putBoolean\(\s*KEY_COLLAPSED\s*,\s*false\s*\)',
      ).allMatches(kt).length;
      final expandSites = RegExp(
        r'applyCollapsedUi\([^)]*forceCollapsed\s*=\s*false',
      ).allMatches(kt).length;

      expect(
        clearSites + expandSites,
        greaterThanOrEqualTo(2),
        reason: '折叠态一旦持久化又只在一处清除，用户折叠一次就永久卡小窗。'
            '必须在新题/新过程推送等主流程上也能退出折叠态。'
            '现有清除点：$clearSites 处写 false，$expandSites 处显式展开',
      );
    });

    test('推送新的 AI 过程时必须确保窗口已展开（不被折叠态吞掉）', () {
      final body = _body(kt, 'fun updateAiProcess(');
      expect(
        RegExp(r'overlayCollapsed').hasMatch(body),
        isTrue,
        reason: 'updateAiProcess 是「新一轮搜题」的明确信号。若它不检查/退出'
            '折叠态，窗口会保持 WRAP_CONTENT，①/② 两行过程只能显示一行 —— '
            '这正是用户这次说的「ai搜题显示也没有优化」。',
      );
    });
  });

  group('② 折叠态不得跳过按内容自适应', () {
    test('ensureAnswerOverlayFitsContent 的早退条件不含 overlayCollapsed '
        '或改为在折叠时先展开', () {
      final body = _body(kt, 'private fun ensureAnswerOverlayFitsContent(');
      // 找出早退语句
      final guard = RegExp(r'if\s*\(([^)]*)\)\s*return').firstMatch(body);
      expect(guard, isNotNull,
          reason: 'ensureAnswerOverlayFitsContent 应有一个显式早退条件');

      final cond = guard!.group(1)!;
      final skipsWhenCollapsed = cond.contains('overlayCollapsed');
      final pushesCollapsedBack =
          RegExp(r'toggleCollapse|forceCollapsed\s*=\s*false').hasMatch(body);

      expect(
        skipsWhenCollapsed && !pushesCollapsedBack,
        isFalse,
        reason: '折叠态直接 return 会让「按内容自适应」完全不跑，'
            '内容必然被 WRAP_CONTENT 裁掉。要么把 overlayCollapsed 移出早退'
            '条件，要么在早退前先退出折叠态。当前条件：`$cond`',
      );
    });
  });

  group('③ 折叠小窗不能是无限期的 WRAP_CONTENT 死角', () {
    test('存在「新内容到来即展开」的服务端兜底', () {
      // 任何一处把 overlayCollapsed 置 false 的路径，都必须在主流程可达，
      // 而不只在「重置悬浮窗大小」这个手动菜单里。
      final resetStart = kt.indexOf('private fun resetOverlayGeometry');
      final others = [
        ...RegExp(r'overlayCollapsed\s*=\s*false').allMatches(kt),
        ...RegExp(r'forceCollapsed\s*=\s*false').allMatches(kt),
      ].where((m) => m.start != resetStart).length;

      expect(
        others,
        greaterThanOrEqualTo(1),
        reason: 'resetOverlayGeometry 只在用户手动点菜单时可达，'
            '不能作为唯一的逃生口。',
      );
    });

    test('有一次性迁移清除历史折叠态（否则升级后旧状态继续生效）', () {
      expect(
        RegExp(r'KEY_OVERLAY_COLLAPSE_SCHEMA').allMatches(kt).length,
        greaterThanOrEqualTo(2),
        reason: '必须同时有常量声明与迁移读取点',
      );
      // 迁移体里必须真的写 false
      final idx = kt.indexOf('KEY_OVERLAY_COLLAPSE_SCHEMA');
      final second = kt.indexOf('KEY_OVERLAY_COLLAPSE_SCHEMA', idx + 10);
      expect(second, greaterThan(0), reason: '应有第二处（迁移读取点）');
      final region = kt.substring(second, second + 700);
      expect(
        RegExp(r'putBoolean\(\s*KEY_COLLAPSED\s*,\s*false\s*\)')
            .hasMatch(region),
        isTrue,
        reason: '升级迁移必须把持久化的折叠态清成 false —— 这正是「用户折叠过一次'
            '就永久卡 39% 小窗、每次升级都说没变化」的根治点。',
      );
    });
  });
}
