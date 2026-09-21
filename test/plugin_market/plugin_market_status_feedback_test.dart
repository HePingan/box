// P1-1 / P1-2 回归测试：扩展页对插件市场状态同步的反馈。
//
// 已修复的真实缺陷：
//   P1-1—— `syncInstalledStatuses()` 返回 `PluginMarketSyncResult.riskCleared`
//          （N 个插件风险已清除、恢复上架），但 plugin_tab.dart 的
//          `_syncInstalledStatuses` 只取 `risks` 就 return，把 riskCleared
//          完整丢弃 → 用户看不到任何提示，不知道插件已可手动启用。
//   P1-2—— `_openPluginMarket` push 商店页后直接返回，不再同步；
//          市场页全文无 syncInstalledStatuses 调用（仅 plugin_tab.initState
//          + app_shell 回前台）。于是「刚在商店装好/卸掉」要等下一次回前台
//          或手动点刷新才反映到已装列表。
//
// 验证方式（源码契约层）：直接读 plugin_tab.dart 源码，锁「riskCleared
// 必须被消费」「push 后必须 force 同步」这两个事实，防止将来被改回去。
// 数据侧契约（riskCleared 真的会被产出）由
// plugin_market_risk_cleared_test.dart 覆盖。
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 读源码并剥掉 `//` 行注释 —— 否则解释性注释里出现的标识符会被误判成用法。
String _read(String path) {
  return File(path)
      .readAsLinesSync()
      .map((line) {
        final idx = line.indexOf('//');
        return idx >= 0 ? line.substring(0, idx) : line;
      })
      .join('\n');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final src = _read('lib/features/extensions/presentation/plugin_tab.dart');

  group('P1-1 riskCleared 必须被消费并提示', () {
    test('_syncInstalledStatuses 源码必须引用 result.riskCleared', () {
      expect(
        src,
        matches(RegExp(r'result\.riskCleared')),
        reason: 'P1-1：riskCleared 曾被完整丢弃，用户看不到恢复上架提示',
      );
    });

    test('提示文案必须包含「恢复上架」与「可手动启用」语义', () {
      expect(
        src,
        contains('恢复上架'),
        reason: '提示必须明确告诉用户插件已恢复上架',
      );
      expect(
        src,
        contains('可手动启用'),
        reason: '提示必须告诉用户下一步可以做什么',
      );
    });
  });

  group('P1-2 商店页返回后必须补同步', () {
    test('_openPluginMarket 必须在 Navigator.push 之后调用 force 同步', () {
      final pushIdx = src.indexOf('await Navigator.push');
      expect(pushIdx, greaterThan(-1), reason: '必须先存在商店页 push');
      final afterPush = src.substring(pushIdx);
      expect(
        afterPush,
        matches(RegExp(r'_syncInstalledStatuses\(\s*force:\s*true\s*\)')),
        reason: 'P1-2：push 返回后必须 force:true 再同步一次，'
            '否则商店里装/卸的插件不会立即反映到已装列表',
      );
    });
  });
}
