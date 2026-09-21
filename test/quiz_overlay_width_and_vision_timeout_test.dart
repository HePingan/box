import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 用户 2026-09-13 第四次反馈（真机截图：⋯ + 「AI…」+ 眼睛 + 文档，无相似度胶囊；
/// 下方纯白无进度）：
///
///   「ai搜题几分钟没反应，适当加宽悬浮窗吧」
///
/// 两个独立缺陷：
///   E. 悬浮窗太窄 —— `defaultOverlaySize()` 把 280/480 当成 **px** 用，
///      iQOO 1440px/密度3.5 上窗只有 137dp，标题栏(需求≈200dp)必然溢出。
///   F. AI 搜题要等几分钟 —— 重试循环里 `.timeout(hardTimeout)` **每次重试**
///      都重新起算 45s，5 次尝试最坏 ≈ 257s（4 分钟+）。
///
/// 本文件是这两条的**回归锁**。
void main() {
  final kt = File(
    '/root/box/android/app/src/main/kotlin/top/hpa888/box/QuizAccessibilityService.kt',
  ).readAsStringSync();
  final engine = File(
    '/root/box/lib/features/quiz_plugin/data/quiz_engine.dart',
  ).readAsStringSync();

  group('防假绿：源文件必须真实读到', () {
    test('Kotlin / Dart 源都读全了', () {
      expect(kt.length, greaterThan(10000), reason: 'Kotlin 源未读入');
      expect(engine.length, greaterThan(10000), reason: 'engine 源未读入');
    });
  });

  group('E. 悬浮窗默认宽度必须按 dp 计算（不再 px/dp 混用）', () {
    test('defaultOverlaySize 不得再出现 px 字面量 coerceIn(280, 480)', () {
      // 不用定长窗口：函数体随修复增长会让 {0,900} 截断/匹配失败，
      // 那是测试脆弱而非代码有问题（2026-09-13 踩过）。
      final m = RegExp(
        r'private fun defaultOverlaySize\(\)[\s\S]*?\n    \}\n',
      ).firstMatch(kt);
      expect(m, isNotNull, reason: '应能定位 defaultOverlaySize');
      final body = m!.group(0)!;
      // 只检查真实代码，忽略注释（注释里会引用旧写法做说明）。
      final codeOnly = body
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(
        codeOnly.contains('coerceIn(280, 480)'),
        isFalse,
        reason: '280/480 是 dp 意图被当 px 用，窄窗 137dp 的元凶',
      );
      expect(
        codeOnly.contains('dm.density'),
        isTrue,
        reason: '必须按密度换算，与 OVERLAY_MIN_WIDTH_DP 同口径',
      );
    });

    test('默认宽度必须 ≥ 200dp（标题栏三键+胶囊放得下）', () {
      // 2026-09-15 修订：尺寸公式已抽到 OverlayGeometryPolicy（P0-1 单一事实源），
      // 故不再断言「defaultOverlaySize() 函数体里有某字符串」——那是断言**位置**，
      // 一旦合理重构就假红（本次即如此），而公式写错时反而可能仍绿。
      // 现在断言**语义**：policy 里宽度确实被夹到 MIN_WIDTH_DP，且该常量为 240dp。
      final policy = File(
        'android/app/src/main/kotlin/top/hpa888/box/OverlayGeometryPolicy.kt',
      ).readAsStringSync();
      final minDecl = RegExp(r'const val MIN_WIDTH_DP\s*=\s*(\d+)').firstMatch(policy);
      expect(minDecl, isNotNull, reason: 'policy 必须有 MIN_WIDTH_DP 常量');
      expect(int.parse(minDecl!.group(1)!), greaterThanOrEqualTo(200),
          reason: '宽度下限须 ≥200dp，否则标题栏三键+胶囊放不下');
      expect(
        RegExp(r'coerceIn\(MIN_WIDTH_DP\.toFloat\(\)').hasMatch(policy),
        isTrue,
        reason: '宽度必须真的夹到 MIN_WIDTH_DP（语义断言而非文本位置断言）',
      );
    });

    // 已修订（2026-09-14）：原断言要求「一次性窄窗迁移（legacyTooNarrow /
    // wDpNow < 200f）」。真机连报三次「没有变化」后确认该方案有本质缺陷：
    // 迁移只在升级后首次启动生效，跑过即作废 → 后续升级永不放大。
    // 现改为**每次启动都施加的无条件下限**（floorW/floorH + coerceAtLeast），
    // 见 quiz_region_button_and_ai_process_v7_test.dart group ①。
    test('必须有每次启动都生效的尺寸下限（而非一次性迁移）', () {
      expect(kt.contains('KEY_OVERLAY_SIZE_SCHEMA'), isTrue,
          reason: 'schema 常量仍用于记录已写入的尺寸版本');
      expect(
        RegExp(r'coerceAtLeast\(floor[WH]\)').hasMatch(kt),
        isTrue,
        reason: '必须在 loadOverlaySize 里对保存值施加无条件下限',
      );
      expect(
        RegExp(r'schema\s*<\s*[0-9]+').hasMatch(kt),
        isFalse,
        reason: '不得再依赖「schema < N 才放大一次」的门闸',
      );
    });
  });

  group('F. AI 搜题硬超时不得被重试放大成几分钟', () {
    test('单次超时必须用「剩余预算」而不是固定 45s', () {
      expect(
        RegExp(r'\.timeout\(remaining\)').hasMatch(engine),
        isTrue,
        reason: '每次重试都重起 45s → 5 次 ≈ 4 分钟，必须改剩余预算',
      );
      expect(
        RegExp(r'final remaining = hardTimeout - \(stopwatch\.elapsed')
            .hasMatch(engine),
        isTrue,
        reason: 'remaining 必须由 start 时刻推算，否则预算算错',
      );
    });

    test('剩余预算耗尽必须 break（总时长封顶 45s）', () {
      expect(
        RegExp(r'if \(remaining <= Duration\.zero\)').hasMatch(engine),
        isTrue,
        reason: '预算耗尽要立刻跳出重试循环',
      );
    });
  });

  group('F2. 超时后 ticker 必须停下并给出终态文案', () {
    test('startVisionTicker 里 45s 后必须 stop 并写终态', () {
      final m = RegExp(r'private fun startVisionTicker\(root: View\)')
          .firstMatch(kt);
      final body = kt.substring(m!.end, (m.end + 2200).clamp(0, kt.length));
      expect(body.contains('s >= 45'), isTrue,
          reason: '旧实现 45s 后仍每秒刷新，用户以为「还在转」');
      expect(
        RegExp(r'stopVisionTicker\(root\)[\s\S]{0,260}?vision_progress_box')
            .hasMatch(body),
        isTrue,
        reason: '必须停 ticker 后重新显示横幅承载超时文案',
      );
      expect(body.contains('已超时'), isTrue, reason: '要有明确的终态文案');
    });
  });
}
