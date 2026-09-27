// 网络诊断页面：注入假服务，不碰真网络。
//
// 守的两条底线：① 认不出的地址要当场说清楚，不能装作在检测；
// ② 失败项必须写出原因 —— 「失败」两个字等于没诊断。
import 'package:box/features/extensions/plugins/net_diag/application/net_diag_service.dart';
import 'package:box/features/extensions/plugins/net_diag/domain/net_diag_models.dart';
import 'package:box/features/extensions/plugins/net_diag/presentation/net_diag_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeService extends NetDiagService {
  _FakeService(this.results);

  final List<NetDiagCheckResult> results;
  final List<String> remembered = [];
  List<String> recent = const [];

  @override
  Future<List<String>> loadRecent() async => recent;

  @override
  Future<void> rememberTarget(String raw) async => remembered.add(raw);

  @override
  Future<NetDiagReport> diagnose(
    NetDiagTarget target, {
    void Function(NetDiagCheckResult)? onResult,
  }) async {
    for (final r in results) {
      onResult?.call(r);
    }
    return NetDiagReport(
      target: target,
      results: results,
      startedAt: DateTime(2026, 9, 27, 12),
    );
  }
}


/// 逐项带延迟返回的假服务：用来观察「四项并发、谁先回来谁先填」的中间状态。
class _GatedService extends NetDiagService {
  _GatedService(this.results, this.delays);

  final List<NetDiagCheckResult> results;
  final List<Duration> delays;

  @override
  Future<List<String>> loadRecent() async => const [];

  @override
  Future<void> rememberTarget(String raw) async {}

  @override
  Future<NetDiagReport> diagnose(
    NetDiagTarget target, {
    void Function(NetDiagCheckResult)? onResult,
  }) async {
    for (var i = 0; i < results.length; i++) {
      await Future<void>.delayed(delays[i]);
      onResult?.call(results[i]);
    }
    return NetDiagReport(
      target: target,
      results: results,
      startedAt: DateTime(2026, 9, 27, 12),
    );
  }
}

Future<void> _pump(WidgetTester tester, NetDiagService service) async {
  debugSetNetDiagRuntime(service: service);
  addTearDown(() => debugSetNetDiagRuntime());
  await tester.pumpWidget(const MaterialApp(home: NetDiagPage()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('认不出的地址：当场给红字，不进入检测', (tester) async {
    final service = _FakeService(const []);
    await _pump(tester, service);

    await tester.enterText(find.byType(TextField), '这不是地址');
    await tester.tap(find.text('检测'));
    await tester.pumpAndSettle();

    expect(find.textContaining('认不出来'), findsOneWidget);
    expect(find.textContaining('正在检测'), findsNothing);
    expect(service.remembered, isEmpty, reason: '地址都不合法，不该记进历史');
  });

  testWidgets('空输入：提示先填主机名', (tester) async {
    await _pump(tester, _FakeService(const []));
    await tester.tap(find.text('检测'));
    await tester.pumpAndSettle();
    expect(find.textContaining('先填一个主机名'), findsOneWidget);
  });

  testWidgets('四项结果逐条渲染：结论 + 耗时', (tester) async {
    final service = _FakeService([
      const NetDiagCheckResult(
        kind: NetDiagCheckKind.dns,
        ok: true,
        summary: '解析出 1 个地址',
        details: ['1.2.3.4'],
        elapsedMs: 12,
      ),
      const NetDiagCheckResult(
        kind: NetDiagCheckKind.tcp,
        ok: true,
        summary: '端口 443 可以连上',
        elapsedMs: 30,
      ),
      const NetDiagCheckResult(
        kind: NetDiagCheckKind.tls,
        ok: true,
        summary: '证书有效，剩余 88 天',
        elapsedMs: 60,
      ),
      const NetDiagCheckResult(
        kind: NetDiagCheckKind.http,
        ok: true,
        summary: 'HTTP 200',
        elapsedMs: 70,
      ),
    ]);
    await _pump(tester, service);

    await tester.enterText(find.byType(TextField), 'box.hpa888.top');
    await tester.tap(find.text('检测'));
    await tester.pumpAndSettle();

    expect(find.textContaining('域名解析：解析出 1 个地址'), findsOneWidget);
    expect(find.textContaining('TCP 连通：端口 443 可以连上'), findsOneWidget);
    expect(find.textContaining('TLS 证书：证书有效，剩余 88 天'), findsOneWidget);
    expect(find.textContaining('HTTP 响应：HTTP 200'), findsOneWidget);
    expect(find.text('12ms'), findsOneWidget);
    expect(service.remembered, ['box.hpa888.top'], reason: '合法输入要记进历史');
    expect(find.text('复制结论文本'), findsOneWidget);
  });

  testWidgets('失败项把原因写出来，而不是只写「失败」', (tester) async {
    final service = _FakeService([
      const NetDiagCheckResult(
        kind: NetDiagCheckKind.tcp,
        ok: false,
        summary: '失败',
        error: '连不上：Connection refused',
        elapsedMs: 5,
      ),
    ]);
    await _pump(tester, service);

    await tester.enterText(find.byType(TextField), 'example.com:9');
    await tester.tap(find.text('检测'));
    await tester.pumpAndSettle();

    expect(find.textContaining('原因：连不上：Connection refused'), findsOneWidget);
    expect(find.textContaining('正在检测'), findsNothing, reason: '结束时不该还停在检测中');
  });

  testWidgets('最近查询可点回填', (tester) async {
    final service = _FakeService(const [])..recent = const ['box.hpa888.top'];
    await _pump(tester, service);
    expect(find.text('box.hpa888.top'), findsOneWidget);

    await tester.tap(find.text('box.hpa888.top'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'box.hpa888.top');
  });

  testWidgets('没写协议/端口时，界面说明是按推测值检测的', (tester) async {
    final service = _FakeService(const []);
    await _pump(tester, service);

    await tester.enterText(find.byType(TextField), 'box.hpa888.top');
    await tester.tap(find.text('检测'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('按 https://box.hpa888.top:443 检测'),
      findsOneWidget,
      reason: '推断出来的值要让用户看见，别以为是自己写的',
    );
  });

  testWidgets('用户写全了协议与端口：不再多嘴（控制组）', (tester) async {
    final service = _FakeService(const []);
    await _pump(tester, service);

    await tester.enterText(find.byType(TextField), 'https://example.com:8443');
    await tester.tap(find.text('检测'));
    await tester.pumpAndSettle();
    expect(find.textContaining('按 https://example.com:8443 检测'), findsNothing);
  });

  testWidgets('开场就如实说明不做 ICMP ping、不经过服务器', (tester) async {
    await _pump(tester, _FakeService(const []));
    expect(find.textContaining('不支持 ICMP ping'), findsOneWidget);
    expect(find.textContaining('不经过 Box 服务器'), findsOneWidget);
  });

  testWidgets('四项并发：行位置固定，没回来的显示「检测中」，回来一个填一个', (tester) async {
    NetDiagCheckResult r(NetDiagCheckKind k, String s) => NetDiagCheckResult(
      kind: k,
      ok: true,
      summary: s,
      details: const [],
      elapsedMs: 10,
    );
    final service = _GatedService(
      [
        r(NetDiagCheckKind.dns, '解析出 1 个地址'),
        r(NetDiagCheckKind.tcp, '端口 443 可连接'),
        r(NetDiagCheckKind.tls, '证书还剩 82 天'),
        r(NetDiagCheckKind.http, 'HTTP 200'),
      ],
      const [
        Duration(milliseconds: 50),
        Duration(milliseconds: 80),
        Duration(milliseconds: 120),
        Duration(milliseconds: 160),
      ],
    );
    await _pump(tester, service);

    await tester.enterText(find.byType(TextField), 'box.hpa888.top');
    await tester.tap(find.text('检测'));
    await tester.pump();

    expect(
      find.textContaining('：检测中'),
      findsNWidgets(4),
      reason: '四项同时开跑，谁都没回来时四行都在占位（而不是空白或转圈到看不出在干什么）',
    );

    await tester.pump(const Duration(milliseconds: 60));
    expect(find.textContaining('：检测中'), findsNWidgets(3));
    expect(find.textContaining('解析出 1 个地址'), findsOneWidget, reason: '最先回来的那项先填上');

    await tester.pumpAndSettle();
    expect(find.textContaining('：检测中'), findsNothing);
    expect(find.textContaining('HTTP 200'), findsOneWidget);
  });
}
