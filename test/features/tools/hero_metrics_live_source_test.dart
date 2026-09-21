import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/api_hub/application/public_api_registry.dart';
import 'package:box/features/api_hub/presentation/api_hub_page.dart';
import 'package:box/features/tools/application/tool_catalog.dart';

/// hero 总览卡的数字必须来自真实来源，不能硬编码。
///
/// 改前实测：hero 里 `12 TOOLS`（:829）与 `12 保留能力`（:849）是**两处
/// 写死的字面量**，而目录实际有 124 条目、37 个已接线 —— 用户看到的
/// 是「12」，与 App 真实能力差了 25 个。同一事实存了三份副本且全部漂移，
/// 正是「硬编码字面量绕过唯一事实源」的典型缺陷。
///
/// 这里锁死：数字一律从 [kToolTargets] / [PublicApiRegistry.all] 派生。
/// 以后接一个工具、加一个面板，hero 自动跟着变，不需要有人记得改文案。
void main() {
  group('hero 数字接真实来源（不再硬编码）', () {
    testWidgets('badge 显示真实已接线数，不是写死的 12', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ApiHubPage()),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final realCount = kToolTargets.length;
      expect(find.text('$realCount TOOLS'), findsWidgets,
          reason: 'badge 应显示 kToolTargets 的真实条目数（$realCount）');

      // 防回归：写死的 12 一旦重新出现就抓住。注意不能在真实数恰好
      // 是 12 时误报，所以先断言真实数不是 12。
      if (realCount != 12) {
        expect(find.text('12 TOOLS'), findsNothing,
            reason: '写死的 12 TOOLS 又回来了 —— 数字与目录脱节');
      }
    });

    testWidgets('统计胶囊显示真实目录可用率，不是写死的 12/5', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ApiHubPage()),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final available = availableToolEntries().length;
      final total = allToolEntries().length;

      // ApiHubMetric 把 value 和 label 渲染进同一个 Text（实测形如
      // 「37 可用工具」），所以不能 find.text('37') 精确匹配，要用
      // textContaining。这里断言完整串，顺带锁住 label 没被改坏。
      expect(find.textContaining('$available 可用工具'), findsWidgets,
          reason: '「可用工具」胶囊应显示已接线条目数（$available）');
      expect(find.textContaining('$total 目录条目'), findsWidgets,
          reason: '「目录条目」胶囊应显示目录总数（$total）');

      if (available != 12) {
        expect(find.textContaining('12 可测'), findsNothing,
            reason: '写死的 12 又回来了 —— 与真实来源脱节');
      }
    });

    testWidgets('面板数显示 registry 真实条目数', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ApiHubPage()),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(
          find.textContaining('${PublicApiRegistry.all.length} 在线面板'),
          findsWidgets,
          reason: '总览卡应体现 registry 里的面板数');
    });

    testWidgets('数字与来源保持一致（改了来源，UI 自动跟）', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ApiHubPage()),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // 三个来源必须同时体现 —— 任何一个是常量，都会在来源变动后
      // 与其余两个脱节。
      final labels = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .toList();

      final expectParts = [
        '${kToolTargets.length} TOOLS',
        '${availableToolEntries().length} 可用工具',
        '${allToolEntries().length} 目录条目',
        '${PublicApiRegistry.all.length} 在线面板',
      ];
      for (final p in expectParts) {
        expect(labels.any((l) => l.contains(p)), isTrue,
            reason: '总览卡缺少来自真实来源的「$p」；实际=$labels');
      }

      // 反向：真实数不是 12/5 时，写死的旧文案一个都不该在。
      if (kToolTargets.length != 12) {
        expect(labels.any((l) => l.contains('12 TOOLS')), isFalse);
        expect(labels.any((l) => l.contains('12 保留能力')), isFalse);
        expect(labels.any((l) => l.contains('5 在线可测')), isFalse);
      }
    });
  });
}
