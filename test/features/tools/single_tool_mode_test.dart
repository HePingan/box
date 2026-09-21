import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:box/design_system/widgets/app_back_button.dart';
import 'package:box/features/api_hub/presentation/api_hub_page.dart';

/// 用户诉求（真机口述）：
///   「我点击工具页的一个工具，希望直接进入看到工具，
///     而不是进入页面后还要下滑才能看到」
///
/// 根因：ApiHubPage 的 sliver 顺序是
///   hero → 快捷区 → 最近使用 → 分组 chip → 工具网格(63 条，极高) → 目标面板
/// 目标面板排在最后，63 条网格把它顶到屏幕外 —— 进去停在第一屏，必须下滑。
///
/// 方案 C：从工具页进来时（initialTool 非空）进入「单工具模式」——
/// 只留 hero + 目标面板，快捷区/最近/分组/网格收进「切换其他工具」按钮后面。
///
/// 断言用 [Finder.hitTestable]：这是唯一能证明「元素真的在视口内且可交互」
/// 的方式。只写 findsOneWidget 会对「已构建但在屏幕外」的元素通过 —— 那正是
/// 本 bug 的盲区；tester.getRect 返回滚动坐标系位置，同样抓不到。
///
/// 注意这里必须注入 stub client：不注入的话测试环境所有请求返回 400，
/// `_buildActivePanel` 会走 `加载失败` 分支，真实面板标题压根不渲染，
/// 于是「看不到面板」就成了测试自己造出来的假象（已踩过）。
void main() {
  /// 只覆盖 currency，够本用例用。
  ///
  /// 返回**真实响应形状**（Frankfurter 的 `rates` 结构），不能图省事给 `{}` ——
  /// 面板拿到空 rates 会渲染成另一种形态，断言标题之外的字段会失准。
  MockClient stubClient() {
    return MockClient((request) async {
      final host = request.url.host;
      if (host.contains('frankfurter')) {
        return http.Response(
          jsonEncode({
            'amount': 1.0,
            'base': 'USD',
            'date': '2026-09-12',
            'rates': {'CNY': 7.12, 'EUR': 0.92, 'JPY': 157.3},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 200,
          headers: {'content-type': 'application/json'});
    });
  }

  /// 默认 800x600 视口 —— 这是关键。单工具模式下第一屏必须能看到面板，
  /// 不许再把窗口拉到 4800px 高来掩盖「面板在很下方」这个事实。
  Future<void> pumpHub(WidgetTester tester, {String? toolId}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ApiHubPage(initialTool: toolId, httpClientForTesting: stubClient()),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  group('单工具模式（从工具页点进某个工具）', () {
    testWidgets('第一屏就能看到目标工具面板，无需下滑', (tester) async {
      await pumpHub(tester, toolId: 'currency');

      // 'Frankfurter 汇率换算' 是 ApiHubCurrencyPanel 的真实标题
      // （widgets/api_hub_tool_panels.dart），不是编的文案。
      expect(
        find.text('Frankfurter 汇率换算').hitTestable(),
        findsWidgets,
        reason:
            '目标面板标题在 800x600 首屏里不可见/不可交互 —— '
            '用户进去要下滑，正是被反馈的问题',
      );
    });

    testWidgets('面板落在首屏范围内（位置证据）', (tester) async {
      await pumpHub(tester, toolId: 'currency');

      final rect = tester.getRect(find.text('Frankfurter 汇率换算').first);
      expect(
        rect.top,
        inInclusiveRange(0, 600),
        reason: '面板标题 top=${rect.top}，超出 600px 视口',
      );
      expect(
        rect.bottom,
        greaterThan(0),
        reason: '面板被顶到视口上方去了',
      );
    });

    testWidgets('单工具模式收起「常用 API 快捷区」', (tester) async {
      await pumpHub(tester, toolId: 'currency');
      expect(
        find.text('常用 API 快捷区'),
        findsNothing,
        reason: '从工具页点进来还铺着快捷区，就是把工具本身往下推',
      );
    });

    testWidgets('单工具模式收起工具网格（63 条全量目录）', (tester) async {
      await pumpHub(tester, toolId: 'currency');
      // '天气预报' 是网格条目名（tool_catalog:61），不是当前面板内容
      expect(
        find.text('天气预报'),
        findsNothing,
        reason: '网格还在，63 条会把目标面板顶到屏幕外',
      );
    });

    testWidgets('返回按钮仍在首屏（收起其他块不能把出口也收掉）', (tester) async {
      await pumpHub(tester, toolId: 'currency');
      expect(
        find.byType(AppBackButton).hitTestable(),
        findsWidgets,
        reason: '单工具模式必须保留返回，否则用户出不去',
      );
    });

    testWidgets('提供「切换其他工具」出口，且点击能展开目录', (tester) async {
      await pumpHub(tester, toolId: 'currency');

      final trigger = find.text('切换其他工具');
      expect(
        trigger.hitTestable(),
        findsWidgets,
        reason: '收起网格后必须给回全量目录的入口，否则功能被藏死',
      );

      // 不只是「有个按钮」—— 按下去必须真能拿回网格。
      await tester.tap(trigger.hitTestable().first);
      await tester.pumpAndSettle();
      expect(
        find.text('天气预报'),
        findsWidgets,
        reason: '点了「切换其他工具」却没出现网格，出口是死的',
      );
    });
  });

  group('非单工具模式（直接进 API 能力中心）', () {
    testWidgets('initialTool 为空时保留完整页面（快捷区 + 网格）', (tester) async {
      await pumpHub(tester);

      expect(
        find.text('常用 API 快捷区'),
        findsWidgets,
        reason: '直接进能力中心时，快捷区和网格是主功能，不能一起收掉',
      );
    });
  });
}
