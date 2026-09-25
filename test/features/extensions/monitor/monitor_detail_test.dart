// 监控详情与迷你折线（287 P3）：
//   * 列表行里有折线（有历史才画）；
//   * 点一行能进详情，详情里有"什么时候开始不通"、最近心跳、证书与可用率；
//   * 没有历史时不画线，给一句说明而不是空框。
//
// 一律有界 pump（页面顶栏有不确定进度圈，pumpAndSettle 会等到超时）。
import 'dart:convert';

import 'package:box/features/extensions/plugins/monitor/monitor_detail_page.dart';
import 'package:box/features/extensions/plugins/monitor/monitor_models.dart';
import 'package:box/features/extensions/plugins/monitor/monitor_page.dart';
import 'package:box/features/extensions/plugins/monitor/monitor_service.dart';
import 'package:box/features/extensions/plugins/monitor/monitor_sparkline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _body(List<Map<String, Object?>> monitors) => jsonEncode({
      'generatedAt': '2026-09-25T12:00:00+08:00',
      'panelUrl': 'https://ham.hpa888.top/',
      'seriesStepSec': 120,
      'monitors': monitors,
    });

Map<String, Object?> _down() => {
      'name': 'Box 更新服务',
      'up': false,
      'pingMs': 0,
      'uptime24h': 97.5,
      'certDays': 12,
      'certValid': true,
      'seriesPing': [118, 120, null, null, null],
      'seriesUp': [1, 1, 0, 0, 0],
    };

class _FakeService extends ServiceMonitorService {
  _FakeService(this.body);

  final String body;

  @override
  Future<MonitorSnapshot> fetch() async => MonitorSnapshot.parse(body);

  @override
  Future<MonitorCachedSnapshot?> cached() async => null;
}

Future<void> _pumpPage(WidgetTester tester, ServiceMonitorService service) async {
  debugSetServiceMonitorRuntime(service: service);
  await tester.pumpWidget(const MaterialApp(home: ServiceMonitorPage()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  tearDown(() => debugSetServiceMonitorRuntime());

  testWidgets('有历史时列表行里画折线，并标出"已不通约 N 分钟"', (tester) async {
    await _pumpPage(tester, _FakeService(_body([_down()])));

    expect(find.byType(MonitorSparkline), findsOneWidget);
    expect(find.text('异常'), findsOneWidget);
    expect(find.textContaining('已不通约'), findsOneWidget);
  });

  testWidgets('没有历史时不画线，写"暂无历史"（不是空框）', (tester) async {
    await _pumpPage(
      tester,
      _FakeService(_body([
        {'name': 'myb2api', 'up': true, 'pingMs': 90},
      ])),
    );

    expect(find.text('暂无历史'), findsOneWidget);
  });

  testWidgets('点一行进详情：不通时长、最近心跳、证书、可用率都在', (tester) async {
    await _pumpPage(tester, _FakeService(_body([_down()])));

    await tester.tap(find.text('Box 更新服务'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // 页面切换动画
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(MonitorDetailPage), findsOneWidget);
    // 列表页还在导航栈里，所以"已不通约 6 分钟"会出现两次 —— 只认详情页里那个。
    expect(
      find.descendant(
        of: find.byType(MonitorDetailPage),
        matching: find.textContaining('已不通约 6 分钟'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('最近 5 次采样'), findsOneWidget);
    expect(find.textContaining('24 小时可用率'), findsOneWidget);
    // 列表行里也会写可用率，所以这些值都要限定在详情页里找。
    expect(
      find.descendant(
        of: find.byType(MonitorDetailPage),
        matching: find.textContaining('97.50%'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(MonitorDetailPage),
        matching: find.text('证书 12 天'),
      ),
      findsOneWidget,
    );
    // 最近心跳里"不通"那几次要写出来（不是显示成 0ms）。
    expect(find.text('不通'), findsWidgets);
    expect(find.text('118 ms'), findsOneWidget);
  });
}
