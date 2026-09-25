// 服务监控插件：页面状态的用例（注入假服务，不碰网络）。
//
// 注意：页面加载时有不确定进度圈（顶栏 spinner），`pumpAndSettle` 会等到超时，
// 所以一律用有界 pump（见仓库插件的既有约定）。
import 'dart:async';
import 'dart:convert';

import 'package:box/features/extensions/plugins/monitor/monitor_models.dart';
import 'package:box/features/extensions/plugins/monitor/monitor_page.dart';
import 'package:box/features/extensions/plugins/monitor/monitor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

String _body({required List<Map<String, Object?>> monitors}) => jsonEncode({
  'generatedAt': '2026-09-25T10:37:13+08:00',
  'panelUrl': 'https://ham.hpa888.top/',
  'monitors': monitors,
});

Map<String, Object?> _up(String name, {int ping = 110}) => {
  'name': name,
  'up': true,
  'pingMs': ping,
  'uptime24h': 100.0,
};

class _FakeService extends ServiceMonitorService {
  _FakeService({
    this.snapshotBody,
    this.cachedBody,
    this.cachedAt,
    this.failWith,
  });

  String? snapshotBody;
  String? cachedBody;
  DateTime? cachedAt;
  String? failWith;
  int fetchCalls = 0;

  /// 让 fetch 卡住直到测试放行（用来观察"还显示着上次的内容"那一刻）。
  Completer<void>? hold;

  @override
  Future<MonitorSnapshot> fetch() async {
    fetchCalls += 1;
    final gate = hold;
    if (gate != null) await gate.future;
    final fail = failWith;
    if (fail != null) throw MonitorFetchException(fail);
    final body = snapshotBody;
    if (body == null) throw MonitorFetchException('测试没给快照');
    return MonitorSnapshot.parse(body);
  }

  int clearCalls = 0;

  @override
  Future<void> clearCache() async {
    clearCalls += 1;
    cachedBody = null;
  }

  @override
  Future<MonitorCachedSnapshot?> cached() async {
    final body = cachedBody;
    if (body == null) return null;
    return MonitorCachedSnapshot(
      snapshot: MonitorSnapshot.parse(body),
      fetchedAt: cachedAt ?? DateTime.now().subtract(const Duration(minutes: 12)),
    );
  }
}

Future<void> _pumpPage(WidgetTester tester, _FakeService service) async {
  debugSetServiceMonitorRuntime(service: service);
  await tester.pumpWidget(const MaterialApp(home: ServiceMonitorPage()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  tearDown(() => debugSetServiceMonitorRuntime());

  testWidgets('首次加载成功：汇总、监控项、延迟与可用率都显示', (tester) async {
    final service = _FakeService(
      snapshotBody: _body(monitors: [_up('Box 更新服务', ping: 118)]),
    );
    await _pumpPage(tester, service);

    expect(find.text('全部在线'), findsOneWidget);
    expect(find.textContaining('1 / 1 项在线'), findsOneWidget);
    expect(find.text('Box 更新服务'), findsOneWidget);
    expect(find.textContaining('延迟 118 ms'), findsOneWidget);
    expect(find.textContaining('24h 可用率 100%'), findsOneWidget);
    expect(find.text('正常'), findsOneWidget);
    expect(service.fetchCalls, 1);
  });

  testWidgets('有异常项：横幅位置显示「N 项异常」，该行标异常', (tester) async {
    final service = _FakeService(
      snapshotBody: _body(monitors: [
        {'name': 'Box 更新服务', 'up': false, 'pingMs': 0, 'uptime24h': 97.5},
        _up('myb2api 码友邦桥接'),
      ]),
    );
    await _pumpPage(tester, service);

    expect(find.text('1 项异常'), findsOneWidget);
    expect(find.textContaining('1 / 2 项在线'), findsOneWidget);
    expect(find.text('异常'), findsOneWidget);
    expect(find.textContaining('24h 可用率 97.50%'), findsOneWidget);
  });

  testWidgets('冷启动：先显示上次的快照，刷新失败时保留并在横幅里写原因', (tester) async {
    final service = _FakeService(
      cachedBody: _body(monitors: [_up('上次看到的站点')]),
      cachedAt: DateTime.now().subtract(const Duration(minutes: 12)),
      failWith: '连不上服务端（检查网络）',
    );
    await _pumpPage(tester, service);

    // 缓存内容还在
    expect(find.text('上次看到的站点'), findsOneWidget);
    // 横幅把原因和"旧"都写清楚
    expect(find.textContaining('刷新失败'), findsOneWidget);
    expect(find.textContaining('连不上服务端'), findsOneWidget);
    expect(find.textContaining('显示的是上次的内容'), findsOneWidget);
    expect(find.textContaining('12 分钟前'), findsOneWidget);
  });

  testWidgets('刷新过程中：横幅说明正在刷新，并保留旧数据', (tester) async {
    final service = _FakeService(
      cachedBody: _body(monitors: [_up('上次看到的站点')]),
      cachedAt: DateTime.now().subtract(const Duration(minutes: 3)),
    );
    final gate = Completer<void>();
    service.hold = gate;
    service.snapshotBody = _body(monitors: [_up('新的站点')]);

    await _pumpPage(tester, service);
    expect(find.text('上次看到的站点'), findsOneWidget);
    expect(find.textContaining('正在刷新'), findsOneWidget);

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('新的站点'), findsOneWidget);
    expect(find.text('上次看到的站点'), findsNothing);
  });

  testWidgets('没有缓存又失败：错误页 + 重试能恢复', (tester) async {
    final service = _FakeService(failWith: '请求超时');
    await _pumpPage(tester, service);

    expect(find.text('拿不到监控快照'), findsOneWidget);
    expect(find.textContaining('请求超时'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    // 第二次成功
    service.failWith = null;
    service.snapshotBody = _body(monitors: [_up('恢复了')]);
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('恢复了'), findsOneWidget);
    expect(find.text('拿不到监控快照'), findsNothing);
    expect(service.fetchCalls, 2);
  });

  testWidgets('右上角刷新按钮能再拉一次', (tester) async {
    final service = _FakeService(
      snapshotBody: _body(monitors: [_up('站点 A')]),
    );
    await _pumpPage(tester, service);
    expect(service.fetchCalls, 1);

    service.snapshotBody = _body(monitors: [_up('站点 B')]);
    await tester.tap(find.byTooltip('刷新'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('站点 B'), findsOneWidget);
    expect(service.fetchCalls, 2);
  });

  testWidgets('复制面板地址：写入剪贴板并提示', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    final service = _FakeService(
      snapshotBody: _body(monitors: [_up('站点 A')]),
    );
    await _pumpPage(tester, service);

    await tester.tap(find.text('复制面板地址'));
    await tester.pump();
    expect(copied, 'https://ham.hpa888.top/');
    expect(find.text('监控面板地址已复制'), findsOneWidget);
  });

  testWidgets('更多菜单里的「清除本地快照」：清缓存并重新拉取', (tester) async {
    final service = _FakeService(
      cachedBody: _body(monitors: [_up('旧缓存')]),
      snapshotBody: _body(monitors: [_up('新拉到的')]),
    );
    await _pumpPage(tester, service);
    expect(find.text('新拉到的'), findsOneWidget);

    await tester.tap(find.byTooltip('更多'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('清除本地快照'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(service.clearCalls, 1);
    expect(find.text('新拉到的'), findsOneWidget);
  });

  testWidgets('证书剩余天数显示在行内；快到期/失效有提示', (tester) async {
    final service = _FakeService(
      snapshotBody: _body(monitors: [
        {'name': 'myb2api', 'up': true, 'pingMs': 118, 'uptime24h': 100.0,
         'certDays': 57, 'certValid': true},
        {'name': 'kimi2api', 'up': true, 'pingMs': 116, 'uptime24h': 100.0,
         'certDays': 43, 'certValid': true},
        {'name': 'zocr', 'up': true, 'pingMs': 120, 'uptime24h': 100.0,
         'certDays': 0, 'certValid': false},
      ]),
    );
    await _pumpPage(tester, service);

    expect(find.text('证书 57 天'), findsOneWidget);
    expect(find.text('证书 43 天'), findsOneWidget);
    expect(find.text('证书已失效'), findsOneWidget);
  });

  testWidgets('没有证书信息的项不显示证书那一段', (tester) async {
    final service = _FakeService(
      snapshotBody: _body(monitors: [
        {'name': '普通站点', 'up': true, 'pingMs': 110, 'uptime24h': 100.0},
      ]),
    );
    await _pumpPage(tester, service);

    expect(find.textContaining('延迟 110 ms'), findsOneWidget);
    expect(find.textContaining('证书'), findsNothing);
  });

  testWidgets('快照里没有监控项也不崩，给一句说明', (tester) async {
    final service = _FakeService(snapshotBody: _body(monitors: []));
    await _pumpPage(tester, service);
    expect(find.text('这份快照里没有监控项'), findsOneWidget);
  });
}
