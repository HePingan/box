// 网络诊断的真实端到端验证：用 dart:io 真连一台真机。
//
// 为什么要这条：单测里的传输层是假的，只能证明「逻辑对」；要证明「真机上会好」
// 必须让生产实现（IoNetDiagTransport）真的发一次请求。默认不随 `flutter test`
// 跑（带 `live` 标签），CI 用 `--exclude-tags live` 排除。
@Tags(['live'])
@Timeout(Duration(minutes: 3))
library;

import 'package:box/features/extensions/plugins/net_diag/domain/net_diag_models.dart';
import 'package:box/features/extensions/plugins/net_diag/domain/net_diag_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final probe = NetDiagProbe(timeout: const Duration(seconds: 10));

  test('正面：真连自家入口，四项都能出结论', () async {
    final target = parseNetDiagTarget('https://box.hpa888.top')!;
    final rs = await probe.runAll(target);
    final byKind = {for (final r in rs) r.kind: r};

    expect(byKind[NetDiagCheckKind.dns]!.ok, isTrue, reason: '解析不出地址说明 DNS 这条路断了');
    expect(byKind[NetDiagCheckKind.tcp]!.ok, isTrue, reason: '443 本该能连上');
    expect(byKind[NetDiagCheckKind.tls]!.ok, isTrue, reason: '证书本该有效');
    expect(
      byKind[NetDiagCheckKind.tls]!.summary,
      contains('剩余'),
      reason: '真实证书要能算出剩余天数',
    );
    expect(
      byKind[NetDiagCheckKind.http]!.details.join(),
      contains('状态码'),
      reason: 'HTTP 项要带回真实状态码',
    );
  });

  test('反面：真连一个没人听的端口，必须给出可读原因（不是一直转圈）', () async {
    // 127.0.0.1 的高位端口在本机不会有服务，用来验证失败路径真的能测出来。
    final target = parseNetDiagTarget('http://127.0.0.1:9')!;
    final rs = await probe.runAll(target);
    final tcp = rs.firstWhere((r) => r.kind == NetDiagCheckKind.tcp);

    expect(tcp.ok, isFalse, reason: '这个端口不该能连上');
    expect(tcp.error, isNotNull);
    expect(tcp.error!.trim(), isNotEmpty, reason: '失败必须带原因');
  });
}
