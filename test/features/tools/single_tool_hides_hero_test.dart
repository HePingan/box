import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:box/design_system/widgets/app_back_button.dart';
import 'package:box/features/api_hub/presentation/api_hub_page.dart';

/// 用户诉求（真机截图 + 口述）：
///   「上面也能不能隐藏，看着很丑」
///
/// 「上面」= hero 总览卡（返回条 + `12 TOOLS` + PUBLIC APIS + 大标题
/// 「API 能力中心」+ 副标题 + 三个统计胶囊 + 两个属性胶囊）。
///
/// 从工具页点某个工具进来时，这些都是**与当前工具无关的总览噪音**，
/// 还占掉小半屏 —— 用户已经说了要点哪个工具，不需要再看目录统计。
/// 方案 C 只收了快捷区/最近/分组/网格，漏了 hero。
///
/// 保留的唯一必需元素是返回按钮（不然出不去），所以单工具模式下落成
/// 一条紧凑返回条，而不是整块 hero。
void main() {
  MockClient stubClient() {
    return MockClient((request) async {
      if (request.url.host.contains('frankfurter')) {
        return http.Response(
          jsonEncode({
            'amount': 1.0,
            'base': 'USD',
            'date': '2026-09-12',
            'rates': {'CNY': 7.12, 'EUR': 0.92},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 200,
          headers: {'content-type': 'application/json'});
    });
  }

  Future<void> pumpHub(WidgetTester tester, {String? toolId}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ApiHubPage(
          initialTool: toolId,
          httpClientForTesting: stubClient(),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  group('单工具模式隐藏 hero 总览卡（点工具进来时）', () {
    testWidgets('不再渲染大标题「API 能力中心」', (tester) async {
      await pumpHub(tester, toolId: 'currency');
      expect(
        find.text('API 能力中心'),
        findsNothing,
        reason: '单工具模式下还铺着 hero 总览卡，就是用户说的「上面很丑」',
      );
    });

    testWidgets('不再渲染 PUBLIC APIS eyebrow 与目录统计胶囊', (tester) async {
      await pumpHub(tester, toolId: 'currency');
      expect(find.text('PUBLIC APIS'), findsNothing, reason: 'eyebrow 是总览噪音');
      expect(find.text('保留能力'), findsNothing, reason: '统计胶囊是总览噪音');
      expect(find.text('在线可测'), findsNothing);
      expect(find.text('免密钥优先'), findsNothing, reason: '属性胶囊也是总览噪音');
    });

    testWidgets('不再渲染过时的硬编码计数（12 TOOLS）', (tester) async {
      await pumpHub(tester, toolId: 'currency');
      expect(
        find.textContaining('TOOLS'),
        findsNothing,
        reason: '单工具模式不该出现总览计数',
      );
    });

    testWidgets('返回按钮必须保留（隐藏 hero 不能把出口也隐藏掉）', (tester) async {
      await pumpHub(tester, toolId: 'currency');
      expect(
        find.byType(AppBackButton).hitTestable(),
        findsWidgets,
        reason: 'hero 收掉了但返回也没了，用户就出不去了',
      );
    });

    testWidgets('目标工具面板仍占首屏（紧凑化后更该在第一屏）', (tester) async {
      await pumpHub(tester, toolId: 'currency');
      expect(
        find.text('Frankfurter 汇率换算').hitTestable(),
        findsWidgets,
        reason: '隐藏 hero 后目标面板必须还在首屏可见',
      );
    });

    testWidgets('面板顶部位置显著上移（hero 让位的位置证据）', (tester) async {
      await pumpHub(tester, toolId: 'currency');
      final top = tester.getRect(find.text('Frankfurter 汇率换算').first).top;
      // 阈值 120 是有依据的：单工具模式上方只剩一条紧凑返回条（~56px）
      // 加 hero 卡片的外边距。改前实测 top=247（hero 整块还在），
      // 用 280 会让这条假绿 —— 所以卡在 120。
      expect(
        top,
        lessThan(120),
        reason: '面板 top=$top；隐藏 hero 后应只剩一条返回条的高度',
      );
    });
  });

  group('非单工具模式保留完整 hero', () {
    testWidgets('直接进 API 能力中心时 hero 总览卡照旧', (tester) async {
      await pumpHub(tester);
      expect(
        find.text('API 能力中心'),
        findsWidgets,
        reason: '直接进能力中心时 hero 是主信息，不能一起收掉',
      );
    });
  });
}
