// P1-6 回归测试：插件市场同步/安装链路的失败必须落到统一调试日志。
//
// 已修复的真实缺陷：
//   plugin_market_local_sync.dart:54  fetchStatus 失败 → 直接
//   `return const PluginMarketSyncResult(failed: true)`，异常对象丢弃；
//   plugin_tab.dart:120 的 catch 是 `catch (_) { /* 网络失败静默 */ }`；
//   app_shell.dart:160 `.catchError((_) {...})` 同样只吞。
//
//   后果：`PluginMarketSyncResult.failed` 这个字段**全仓零消费者**，
//   「同步失败过」在 App 里没有任何地方能查到。用户报「插件被莫名禁用」
//   「商店装了不显示」时，无 adb 的报障人拿不出任何证据，只能定性为
//   无法复现。而 AppLogger + 抽屉「更多 → 调试日志」早已是全项目统一的
//   排障入口，插件链路却一次都没写过。
//
// 预期修法：失败点与两处调用方 catch 一律走 AppLogger（error 级别），
// 不新建悬浮按钮、不建第二套日志；插件 Tab 的失败 SnackBar 附一句
// 「已记入调试日志」，让用户知道去哪复制。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 读源码并剥掉 `//` 行注释和 `/* */` 段注释——否则解释性注释里出现
/// AppLogger 字样会被误判为已埋点。
String _strip(String path) {
  final src = File(path).readAsStringSync();
  final noBlock = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ');
  return noBlock
      .split('\n')
      .map((line) {
        final idx = line.indexOf('//');
        return idx >= 0 ? line.substring(0, idx) : line;
      })
      .join('\n');
}

const kSyncSrc =
    'lib/features/extensions/market/data/plugin_market_local_sync.dart';
const kTabSrc = 'lib/features/extensions/presentation/plugin_tab.dart';
const kShellSrc = 'lib/app/app_shell.dart';

void main() {
  group('P1-6 同步失败必须留痕到统一调试日志', () {
    test('local_sync 必须 import AppLogger（唯一日志入口）', () {
      expect(
        _strip(kSyncSrc),
        contains("import 'package:box/utils/app_logger.dart';"),
        reason: '不导入 AppLogger 就无从写入统一调试日志',
      );
    });

    test('fetchStatus 失败必须记 error 级日志（含异常原文）', () {
      final src = _strip(kSyncSrc);
      final fetchTry = src.indexOf('await _api.fetchStatus');
      expect(fetchTry, greaterThan(-1), reason: '必须先存在 fetchStatus 调用');
      final afterCall = src.substring(fetchTry);
      expect(
        afterCall,
        matches(RegExp(r'logChannelError\(\s*LogChannel\.system')),
        reason: 'P1-6：fetchStatus 失败此前只 return failed:true，'
            '异常原文被丢，报障人拿不到证据',
      );
    });

    test('plugin_tab 的 catch 不得再是静默空实现', () {
      final src = _strip(kTabSrc);
      expect(
        src,
        matches(RegExp(r'LogChannel\.system')),
        reason: 'P1-6：plugin_tab._syncInstalledStatuses 的 catch 原为 '
            'catch(_){} 静默，用户完全不知道同步失败过',
      );
    });

    test('plugin_tab 失败 SnackBar 须提示「已记入调试日志」', () {
      expect(
        _strip(kTabSrc),
        contains('已记入调试日志'),
        reason: '要告诉无 adb 的报障人：证据在「更多 → 调试日志」里可复制',
      );
    });

    test('app_shell 回前台同步的 catchError 不得再吞掉 error 对象', () {
      final src = _strip(kShellSrc);
      expect(
        src,
        matches(RegExp(r'logChannelError\(\s*LogChannel\.system')),
        reason: 'P1-6：app_shell 回前台同步失败同样静默，'
            '「回后台再进来插件被禁用」将无从排查',
      );
    });
  });

  group('P1-6 降级路径保留静默（不得误报为故障）', () {
    test('reportInstall 上报失败的降级保持存在', () {
      final src = _strip(kSyncSrc);
      expect(
        src,
        matches(RegExp(r'_api\.reportInstall')),
        reason: 'reportInstall 是安装上报，失败应静默降级而非报错',
      );
    });
  });
}
