import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 接线契约：动作 → 路由 → 页面 → 市场条目，任何一环断了都是「看起来有、点了没反应」。
void main() {
  final core = File(
    'lib/features/extensions/core/home_plugin_core.dart',
  ).readAsStringSync();
  final pages = File(
    'lib/features/extensions/core/builtin_plugin_pages.dart',
  ).readAsStringSync();
  final market = File(
    'lib/features/extensions/market/domain/plugin_market_manifest.dart',
  ).readAsStringSync();

  test('动作枚举里有 openWatchLater，且给了中文标签与展示顺序', () {
    expect(core, contains('openWatchLater;'));
    expect(core, contains("return '打开稍后看'"));
    expect(core, contains('HomePluginActionType.openWatchLater,\n  ];'));
  });

  test('动作处理器：优先 payload 构造器，回落到普通路由', () {
    final start = core.indexOf('register(HomePluginActionType.openWatchLater.name');
    expect(start, greaterThan(0));
    final block = core.substring(start, start + 700);
    expect(block, contains("lookupPayload('openWatchLater')"));
    expect(block, contains("lookup('openWatchLater')"));
    expect(block, contains('actionContext.payload'));
  });

  test('注册表把动作接到页面（普通 + 带 payload 两条）', () {
    expect(pages, contains("'openWatchLater'"));
    expect(pages, contains('const WatchLaterPage()'));
    expect(pages, contains('WatchLaterPage(initialPayload: payload)'));
    expect(pages, contains('watch_later_page.dart'));
  });

  test('市场条目指向真动作，且声明了如实权限', () {
    final start = market.indexOf("id: 'market_video_watch_later'");
    expect(start, greaterThan(0));
    // 只切到下一个条目为止：固定窗口会把下一条的 comingSoon 一起圈进来，
    // 于是「本条目不是占位」的断言会被隔壁误伤（踩过一次）。
    final next = market.indexOf('MarketPluginTemplate(', start + 10);
    final block = market.substring(start, next > start ? next : start + 400);
    expect(block, contains("actionCode: 'openWatchLater'"));
    expect(block, contains("permissions: const ['network', 'storage']"));
    expect(block, isNot(contains('comingSoon: true')));
  });
}
