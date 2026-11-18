// 未命中/失败提示「保底停留」回归（2026-11-18 用户报障）。
//
// 报障原文：「有些时候 AI 读屏不成功，这个提示闪烁一下就没了，太快了看不清提示」。
// 真因：失败提示画出来之后，同题的下一拍扫描又推一条 `searching`，而原生渲染
// 遇到 searching 会无条件把正文置空 ⇒ 提示一闪而过。
//
// 修法：同题的失败提示在 6 秒内不被 searching 抹掉 —— 这次 searching 降级成
// `retrying`，正文带回去的是上一条失败提示（原生对 retrying 不清空正文）。
//
// 这个文件把三条边界钉死，防止以后「顺手简化」把保底停留又去掉：
//   ① 同题 + 窗口内 + searching → retrying，且正文是原提示；
//   ② 换题（指纹不同）/ 窗口过期 / 非 searching → 一律不动；
//   ③ 没有可保留的提示时也不动（否则会出现「空正文 + 重试中」的死白屏）。
import 'dart:io';

import 'package:box/features/quiz_plugin/presentation/quiz_plugin_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(QuizPluginEntry.debugResetVisionState);

  group('失败提示保底停留', () {
    test('同题 + 窗口内：searching 降级为 retrying，并带回原提示', () {
      QuizPluginEntry.debugRecordMiss('fp-1', 'AI 读屏超时（后端预算 35s），请重试');
      final r = QuizPluginEntry.debugApplyMissSticky(
        'searching',
        '正在搜题（题干+选项）...',
        'fp-1',
      );
      expect(r['status'], 'retrying');
      expect(r['answers'], 'AI 读屏超时（后端预算 35s），请重试',
          reason: '重试态必须把上一条提示带回去，否则正文又空了');
    });

    test('换题（指纹不同）：保持 searching，正常清空重绘', () {
      QuizPluginEntry.debugRecordMiss('fp-1', '未搜到答案');
      final r = QuizPluginEntry.debugApplyMissSticky('searching', '正在搜题…', 'fp-2');
      expect(r['status'], 'searching');
      expect(r['answers'], '正在搜题…');
    });

    test('窗口过期（6 秒后）：不再阻挠 searching', () {
      QuizPluginEntry.debugRecordMiss(
        'fp-1',
        '未搜到答案',
        at: DateTime.now().subtract(const Duration(seconds: 7)),
      );
      final r = QuizPluginEntry.debugApplyMissSticky('searching', '正在搜题…', 'fp-1');
      expect(r['status'], 'searching');
    });

    test('窗口边界内（5 秒）：仍然拦住', () {
      QuizPluginEntry.debugRecordMiss(
        'fp-1',
        '未搜到答案',
        at: DateTime.now().subtract(const Duration(seconds: 5)),
      );
      final r = QuizPluginEntry.debugApplyMissSticky('searching', '正在搜题…', 'fp-1');
      expect(r['status'], 'retrying');
    });

    test('非 searching 状态如 hit/miss 一律不动', () {
      QuizPluginEntry.debugRecordMiss('fp-1', '未搜到答案');
      for (final status in ['hit', 'miss', 'ambiguous']) {
        final r = QuizPluginEntry.debugApplyMissSticky(status, '正文', 'fp-1');
        expect(r['status'], status);
        expect(r['answers'], '正文');
      }
    });

    test('没登记过提示 / 指纹缺失：不动（避免「空正文 + 重试中」）', () {
      expect(
        QuizPluginEntry.debugApplyMissSticky('searching', '正在搜题…', 'fp-1')['status'],
        'searching',
        reason: '没有可保留的提示时不该降级',
      );
      QuizPluginEntry.debugRecordMiss('fp-1', '未搜到答案');
      expect(
        QuizPluginEntry.debugApplyMissSticky('searching', '正在搜题…', null)['status'],
        'searching',
      );
      expect(
        QuizPluginEntry.debugApplyMissSticky('searching', '正在搜题…', '')['status'],
        'searching',
      );
    });

    test('reset 之后不再拦（换用户/重进插件不会带着旧提示）', () {
      QuizPluginEntry.debugRecordMiss('fp-1', '未搜到答案');
      QuizPluginEntry.debugResetVisionState();
      final r = QuizPluginEntry.debugApplyMissSticky('searching', '正在搜题…', 'fp-1');
      expect(r['status'], 'searching');
    });
  });

  group('保底停留窗口取值', () {
    test('窗口不得短于 4 秒且不得长于 10 秒', () {
      // 太短：用户还没看完就没了（这条就是原始报障）；
      // 太长：失败后用户重试，正文一直停在旧提示会显得没反应。
      expect(QuizPluginEntry.missStickyWindow.inSeconds, greaterThanOrEqualTo(4));
      expect(QuizPluginEntry.missStickyWindow.inSeconds, lessThanOrEqualTo(10));
    });
  });

  group('原生侧契约（改原生渲染时别把 retrying 抹掉）', () {
    String readKt(String name) {
      final f = File(
        'android/app/src/main/kotlin/top/hpa888/box/$name',
      );
      expect(f.existsSync(), isTrue, reason: '找不到 $name（工作目录应为仓库根）');
      return f.readAsStringSync();
    }

    test('service：searching 清空正文，retrying 保留正文', () {
      final kt = readKt('QuizAccessibilityService.kt');
      expect(kt.contains('val isRetryingNow = overlayStatus == "retrying"'), isTrue,
          reason: 'retrying 必须有独立判定，否则回到「只认 searching」');
      expect(
        kt.contains('isRetryingNow -> buildMissDisplayAnswer(a)'),
        isTrue,
        reason: 'retrying 正文要按失败提示渲染（用户正在看的就是这条提示）',
      );
      // 清空正文只允许发生在 searching 分支
      expect(kt.contains('if (isSearchingNow) {\n            aTv?.text = ""'),
          isTrue);
    });

    test('service：retrying 不算「答案已就绪」（否则过程框被收起）', () {
      final kt = readKt('QuizAccessibilityService.kt');
      expect(
        kt.contains('s != "searching" && s != "retrying"'),
        isTrue,
        reason: '把 retrying 当成就绪会让 AI 过程框提前收起',
      );
    });

    test('service：徽章把 retrying 显示成「重试中」而不是「未命中」', () {
      final kt = readKt('QuizAccessibilityService.kt');
      expect(kt.contains('status == "retrying" -> OverlayBadge("重试中"'), isTrue);
    });

    test('普通悬浮窗兜底也要渲染 retrying（否则走「答案：xxx」提取把提示改写）', () {
      final kt = readKt('QuizOverlayManager.kt');
      expect(kt.contains('currentStatus == "retrying"'), isTrue);
    });

    test('endsVisionRun 不得把 retrying 当终态（会复位 AI 按钮/停 ticker）', () {
      final kt = readKt('VisionRunningStatePolicy.kt');
      final terminalLine = RegExp(
        r'"(hit|miss|ambiguous|retrying)"[^\n]*-> true',
      ).allMatches(kt).map((m) => m.group(1)).toList();
      expect(terminalLine, isNot(contains('retrying')),
          reason: 'retrying 不是终态');
    });
  });
}
