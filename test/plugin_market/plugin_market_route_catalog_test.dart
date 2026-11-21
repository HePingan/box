import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/extensions/core/builtin_plugin_pages.dart';
import 'package:box/features/extensions/core/home_plugin_core.dart';

/// navigate 动作的路由码是**两端共享的契约**：
///
/// - App 侧事实源：`registerBuiltinRouteDefaults()` 里逐条 register 的字符串；
/// - 服务端镜像：`tool/image_platform_quota_server.dart` 的 `_allowedPluginRoutes`
///   （投稿期据此拒掉「指向不存在页面」的插件）。
///
/// 两边一旦漂移，就会出现「本地能跳、线上投稿被 400」或反过来
/// 「服务端放行、客户端查不到 → 点了没反应」。这个测试把两边钉在一起。
void main() {
  test('后端路由白名单与 App 注册表逐条一致', () {
    final appCodes = HomePluginRouteRegistry.registeredCodes().toSet();
    expect(appCodes, isNotEmpty, reason: 'App 路由注册表是空的，registerDefaults 没生效');

    final source = File('tool/image_platform_quota_server.dart').readAsStringSync();
    final block = RegExp(
      r'_allowedPluginRoutes\s*=\s*\{(.*?)\};',
      dotAll: true,
    ).firstMatch(source);
    expect(block, isNotNull, reason: '后端找不到 _allowedPluginRoutes 常量');

    final serverCodes = RegExp(r"'([^']+)'")
        .allMatches(block!.group(1)!)
        .map((m) => m.group(1)!)
        .toSet();

    expect(
      serverCodes,
      appCodes,
      reason: '服务端白名单与 App 注册表漂移：'
          '仅服务端有 ${serverCodes.difference(appCodes)}，'
          '仅 App 有 ${appCodes.difference(serverCodes)}',
    );
  });

  test('navigate 查不到路由时必须有提示，不能静默 return', () {
    // 契约：navigate handler 里 builder == null 的分支要给出提示文案。
    // 旧写法是裸 `if (builder == null) return;` —— 用户点了毫无反应，
    // 而「插件动作未注册」的兜底提示因为 handler 存在永远触发不到。
    final source =
        File('lib/features/extensions/core/home_plugin_core.dart').readAsStringSync();
    final handler = RegExp(
      r"register\(HomePluginActionType\.navigate\.name,(.*?)\n    \}\);",
      dotAll: true,
    ).firstMatch(source);
    expect(handler, isNotNull, reason: '找不到 navigate handler');

    final body = handler!.group(1)!;
    expect(
      body.contains('if (builder == null) return;'),
      isFalse,
      reason: 'navigate 又在查不到路由时静默返回了',
    );
    expect(
      body.contains('_showSnack'),
      isTrue,
      reason: 'navigate 查不到路由时必须提示用户',
    );
  });

  test('投稿页 navigate 走下拉，不再让作者手填路由码', () {
    final source = File(
      'lib/features/extensions/market/presentation/plugin_submit_page.dart',
    ).readAsStringSync();
    expect(
      source.contains("_actionCode == 'navigate'"),
      isTrue,
      reason: '投稿页必须针对 navigate 单独渲染',
    );
    expect(
      source.contains('registeredCodes()'),
      isTrue,
      reason: '路由码选项必须来自注册表（单一事实源）',
    );
    expect(
      source.contains('kHomePluginRouteLabels'),
      isTrue,
      reason: '下拉要给中文页面名，裸 code 对作者没有意义',
    );
  });

  test('路由中文名表与注册表逐条对齐（下拉不会出现空标签）', () {
    final codes = HomePluginRouteRegistry.registeredCodes().toSet();
    final labels = kHomePluginRouteLabels.keys.toSet();
    expect(
      labels,
      codes,
      reason: '标签表漂移：缺 ${codes.difference(labels)}，'
          '多 ${labels.difference(codes)}',
    );
  });
}
