// 快照陈旧提醒（287 D4）：采样断了不能静默。
//
// 判定用纯函数（不依赖真实时间），界面另用有界 pump 验一次。
import 'dart:convert';

import 'package:box/features/extensions/plugins/monitor/monitor_models.dart';
import 'package:box/features/extensions/plugins/monitor/monitor_page.dart';
import 'package:box/features/extensions/plugins/monitor/monitor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeService extends ServiceMonitorService {
  _FakeService(this.body);

  final String body;

  @override
  Future<MonitorSnapshot> fetch() async => MonitorSnapshot.parse(body);

  @override
  Future<MonitorCachedSnapshot?> cached() async => null;
}

String _body(DateTime at) => jsonEncode({
      'generatedAt': at.toIso8601String(),
      'panelUrl': 'https://ham.hpa888.top/',
      'monitors': [
        {'name': 'myb2api', 'up': true, 'pingMs': 90},
      ],
    });

void main() {
  final now = DateTime(2026, 9, 25, 13, 0);

  group('判定', () {
    test('阈值内不算陈旧（偶发抖动不是故障）', () {
      expect(
        isMonitorSnapshotStale(now.subtract(const Duration(minutes: 9)),
            now: now),
        isFalse,
      );
    });

    test('超过 10 分钟算陈旧（连续 5 次没动静）', () {
      expect(
        isMonitorSnapshotStale(now.subtract(const Duration(minutes: 11)),
            now: now),
        isTrue,
      );
    });

    test('时间未知不下结论（别把"不知道"显示成"断了"）', () {
      expect(isMonitorSnapshotStale(null, now: now), isFalse);
    });

    test('时间在未来（时钟偏差）不报陈旧', () {
      expect(
        isMonitorSnapshotStale(now.add(const Duration(minutes: 5)), now: now),
        isFalse,
      );
    });

    test('阈值可调（用例不必等真时间）', () {
      expect(
        isMonitorSnapshotStale(now.subtract(const Duration(minutes: 3)),
            now: now, staleAfter: const Duration(minutes: 2)),
        isTrue,
      );
    });
  });

  group('界面', () {
    tearDown(() => debugSetServiceMonitorRuntime());

    Future<void> pumpWith(WidgetTester tester, DateTime generatedAt) async {
      debugSetServiceMonitorRuntime(service: _FakeService(_body(generatedAt)));
      await tester.pumpWidget(const MaterialApp(home: ServiceMonitorPage()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('陈旧时顶部给一条提醒（说清多久没更新）', (tester) async {
      await pumpWith(tester, DateTime.now().subtract(const Duration(minutes: 42)));

      expect(find.textContaining('快照已经很久没更新了'), findsOneWidget);
      expect(find.textContaining('42 分钟前'), findsWidgets);
    });

    testWidgets('新鲜时不提醒（不给无谓的横幅）', (tester) async {
      await pumpWith(tester, DateTime.now());

      expect(find.textContaining('快照已经很久没更新了'), findsNothing);
    });
  });
}
