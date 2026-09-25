// 服务器运维插件：「服务器」页签的用例（注入假服务，不碰网络）。
//
// 注意：页面加载时有不确定进度圈（顶栏 spinner），`pumpAndSettle` 会等到超时，
// 所以一律用有界 pump（见仓库插件的既有约定）。
import 'dart:async';
import 'dart:convert';

import 'package:box/features/extensions/plugins/server_ops/host_models.dart';
import 'package:box/features/extensions/plugins/server_ops/host_service.dart';
import 'package:box/features/extensions/plugins/server_ops/host_sparkline.dart';
import 'package:box/features/extensions/plugins/server_ops/host_tab.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _body({bool online = true, bool extended = false}) => jsonEncode({
      'generatedAt': '2026-09-25T16:00:00+08:00',
      'hosts': [
        {
          'id': 'hpa888',
          'name': '阿里云 · 主服务端',
          'ip': '47.109.97.1',
          'online': online,
          if (online) ...{
            'cpuPercent': 3.1,
            'cpuCount': 4,
            'memTotalBytes': 7843819520,
            'memUsedBytes': 4307644416,
            'memPercent': 54.9,
            'swapTotalBytes': 2147483648,
            'swapUsedBytes': 268435456,
            'diskTotalBytes': 63224078336,
            'diskUsedBytes': 42084376576,
            'diskPercent': 66.6,
            'load1': 1.53,
            'load5': 0.83,
            'load15': 0.46,
            'uptimeSeconds': 445041,
            'netRxBytesPerSec': 15205,
            'netTxBytesPerSec': 47497,
            // 默认不给扩展字段：289 线上的老快照就是这样（界面不许显示
            // 盘 IO / 温度这些假 0）。
            if (extended) ...{
              'swapPercent': 12.5,
              'diskReadBytesPerSec': 1048576,
              'diskWriteBytesPerSec': 2097152,
              'temperatureC': 52.4,
            },
          },
        },
        {
          'id': 'offline-box',
          'name': '备用机',
          'ip': '10.0.0.9',
          'online': false,
        },
      ],
    });

class _FakeHostService extends HostService {
  _FakeHostService({
    this.snapshotBody,
    this.cachedBody,
    this.cachedAt,
    this.failWith,
    this.histories = const {},
  });

  String? snapshotBody;
  String? cachedBody;
  DateTime? cachedAt;
  String? failWith;
  Map<String, HostHistory> histories;

  int fetchCalls = 0;

  /// 让 fetch 卡住直到测试放行（用来观察"还显示着上次的内容"那一刻）。
  Completer<void>? hold;

  @override
  Future<HostSnapshot> fetch() async {
    fetchCalls += 1;
    final gate = hold;
    if (gate != null) await gate.future;
    final fail = failWith;
    if (fail != null) throw HostFetchException(fail);
    final body = snapshotBody;
    if (body == null) throw HostFetchException('测试没给快照');
    return HostSnapshot.parse(body);
  }

  @override
  Future<HostCachedSnapshot?> cached() async {
    final body = cachedBody;
    if (body == null) return null;
    return HostCachedSnapshot(
      snapshot: HostSnapshot.parse(body),
      fetchedAt: cachedAt ?? DateTime.now().subtract(const Duration(minutes: 12)),
    );
  }

  @override
  Future<Map<String, HostHistory>> loadHistories() async => histories;

  @override
  Future<Map<String, HostHistory>> recordSample(
    HostSnapshot snapshot, {
    DateTime? now,
  }) async =>
      histories;

  int clearCalls = 0;

  @override
  Future<void> clearCache() async {
    clearCalls += 1;
    cachedBody = null;
  }

  @override
  Future<void> clearHistories() async {
    histories = const {};
  }
}

Future<void> _pumpHostTab(WidgetTester tester, _FakeHostService service) async {
  debugSetServerOpsRuntime(hostService: service);
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: ServerOpsHostTab())),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  tearDown(() => debugSetServerOpsRuntime());

  testWidgets('首次加载成功：采样时刻、在线/离线、指标与折线都显示', (tester) async {
    final service = _FakeHostService(snapshotBody: _body());
    await _pumpHostTab(tester, service);

    expect(find.text('阿里云 · 主服务端'), findsOneWidget);
    expect(find.text('47.109.97.1'), findsOneWidget);
    expect(find.text('在线'), findsOneWidget);
    expect(find.text('3.1% · 4 核'), findsOneWidget);
    expect(find.textContaining('54.9%'), findsWidgets);
    // 采样时刻显式显示（数据源是 2 分钟一份的静态文件，不能假装实时）。
    expect(find.textContaining('采样时刻 2026-09-25'), findsOneWidget);
    expect(find.text('1 / 2 台在线'), findsOneWidget);
  });

  testWidgets('离线机器显示"离线"，不显示 0%', (tester) async {
    final service = _FakeHostService(snapshotBody: _body());
    await _pumpHostTab(tester, service);

    expect(find.text('备用机'), findsOneWidget);
    expect(find.text('离线'), findsOneWidget);
    expect(find.textContaining('这台机器当前离线'), findsOneWidget);
    expect(find.text('1 台离线'), findsOneWidget);
  });

  testWidgets('有历史时画出折线说明；没有历史时说"暂无历史"', (tester) async {
    final service = _FakeHostService(
      snapshotBody: _body(),
      histories: {
        'hpa888': const HostHistory(
          cpu: [1.0, 2.0, 3.0],
          mem: [50.0, 51.0],
        ),
      },
    );
    await _pumpHostTab(tester, service);

    expect(find.byType(HostSparkline), findsWidgets);
    expect(find.textContaining('最近 3 个点'), findsOneWidget);
    expect(find.text('暂无历史'), findsWidgets, reason: '磁盘没有历史点');
  });

  testWidgets('首次加载失败：进错误态并给重试入口', (tester) async {
    final service = _FakeHostService(failWith: '连不上服务端（检查网络）');
    await _pumpHostTab(tester, service);

    expect(find.text('拿不到主机快照'), findsOneWidget);
    expect(find.textContaining('连不上服务端'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('扩展指标（盘 IO / Swap / 温度）在字段齐全时显示', (tester) async {
    final service = _FakeHostService(snapshotBody: _body(extended: true));
    await _pumpHostTab(tester, service);

    expect(find.text('盘 IO 读 1.0 MB/s  /  写 2.0 MB/s'), findsOneWidget);
    expect(find.text('Swap 256.0 MB / 2.0 GB（12.5%）'), findsOneWidget);
    expect(find.text('温度 52.4 ℃'), findsOneWidget);
    // 原有指标不受影响。
    expect(find.text('3.1% · 4 核'), findsOneWidget);
  });

  testWidgets('老快照缺扩展字段：Swap 照显，盘 IO 与温度整行不显示（不显示 0）',
      (tester) async {
    final service = _FakeHostService(snapshotBody: _body());
    await _pumpHostTab(tester, service);

    // Swap 的字段 289 就在采（总量/用量），所以这一行应该出现。
    expect(find.textContaining('Swap 256.0 MB'), findsOneWidget);
    // 盘 IO / 温度没字段：整行不显示，而不是 "0 B/s" / "0.0 ℃"。
    expect(find.textContaining('盘 IO'), findsNothing);
    expect(find.textContaining('温度'), findsNothing);
    expect(find.textContaining('℃'), findsNothing);
    expect(find.textContaining('0 B/s'), findsNothing);
    // 页面照常渲染。
    expect(find.text('阿里云 · 主服务端'), findsOneWidget);
  });

  testWidgets('机器没启用 swap（total=0）时整行不显示', (tester) async {
    final service = _FakeHostService(
      snapshotBody: jsonEncode({
        'hosts': [
          {
            'id': 'a',
            'name': '无 swap 机',
            'online': true,
            'swapTotalBytes': 0,
            'swapUsedBytes': 0,
            // 云主机没温度传感器：采集器报 null（不是 0）。
            'temperatureC': null,
          },
        ],
      }),
    );
    await _pumpHostTab(tester, service);

    expect(find.text('无 swap 机'), findsOneWidget);
    expect(find.textContaining('Swap'), findsNothing);
    expect(find.textContaining('温度'), findsNothing);
    expect(find.textContaining('盘 IO'), findsNothing);
  });

  testWidgets('刷新失败但保留旧内容：横幅写明"显示的是上次的内容（N 分钟前）"',
      (tester) async {
    final service = _FakeHostService(
      cachedBody: _body(),
      cachedAt: DateTime.now().subtract(const Duration(minutes: 12)),
      failWith: '服务端返回 HTTP 502',
    );
    await _pumpHostTab(tester, service);

    expect(find.textContaining('刷新失败'), findsOneWidget);
    expect(find.textContaining('显示的是上次的内容（12 分钟前）'), findsOneWidget);
    // 旧内容还在（主机卡片没被抹掉）。
    expect(find.text('阿里云 · 主服务端'), findsOneWidget);
    expect(service.fetchCalls, greaterThan(0));
  });

  testWidgets('冷启动先渲染上次的快照（刷新在途时也有内容可看）', (tester) async {
    final service = _FakeHostService(
      cachedBody: _body(),
      snapshotBody: _body(),
    );
    service.hold = Completer<void>();
    debugSetServerOpsRuntime(hostService: service);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ServerOpsHostTab())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('阿里云 · 主服务端'), findsOneWidget);
    expect(find.textContaining('正在刷新'), findsOneWidget);

    service.hold!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.textContaining('正在刷新'), findsNothing);
  });

  testWidgets('清除本地快照：清掉后重新拉', (tester) async {
    final service = _FakeHostService(
      cachedBody: _body(),
      snapshotBody: _body(),
    );
    await _pumpHostTab(tester, service);
    final before = service.fetchCalls;

    await tester.tap(find.byTooltip('更多'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('清除本地快照'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.clearCalls, 1);
    expect(service.fetchCalls, greaterThan(before));
  });
}
