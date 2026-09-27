// 网络诊断：四项检测的行为（注入假传输层，单测不联网）。
//
// 每条失败路径都要求「有原因」—— 这是这个插件存在的意义：把「一直转圈」
// 变成「为什么不通」。
import 'dart:async';
import 'dart:io';

import 'package:box/features/extensions/plugins/net_diag/domain/net_diag_models.dart';
import 'package:box/features/extensions/plugins/net_diag/domain/net_diag_probe.dart';
import 'package:flutter_test/flutter_test.dart';

/// 可编排的假传输层。
class _FakeTransport implements NetDiagTransport {
  _FakeTransport({
    this.addresses = const ['1.2.3.4'],
    this.dnsError,
    this.tcpError,
    this.tlsError,
    this.tlsNotAfter,
    this.httpStatus = 200,
    this.httpLocation,
  });

  List<String> addresses;
  Object? dnsError;
  Object? tcpError;
  Object? tlsError;
  DateTime? tlsNotAfter;
  int httpStatus;
  String? httpLocation;

  int lookupCalls = 0;
  int tcpCalls = 0;
  int tlsCalls = 0;
  int httpCalls = 0;

  @override
  Future<List<String>> lookupHost(String host) async {
    lookupCalls++;
    if (dnsError != null) throw dnsError!;
    return addresses;
  }

  @override
  Future<TcpProbeResult> connectTcp(String host, int port, Duration timeout) async {
    tcpCalls++;
    if (tcpError != null) throw tcpError!;
    return const TcpProbeResult(connected: true);
  }

  @override
  Future<TlsProbeResult> handshakeTls(String host, int port, Duration timeout) async {
    tlsCalls++;
    if (tlsError != null) throw tlsError!;
    return TlsProbeResult(
      subject: 'CN=$host',
      issuer: 'CN=Test CA',
      notBefore: DateTime.now().subtract(const Duration(days: 30)),
      notAfter: tlsNotAfter ?? DateTime.now().add(const Duration(days: 90)),
      protocol: 'TLSv1.3',
    );
  }

  @override
  Future<HttpProbeResult> getHttp(String url, Duration timeout) async {
    httpCalls++;
    return HttpProbeResult(
      statusCode: httpStatus,
      location: httpLocation,
      serverHeader: 'test/1.0',
    );
  }
}

NetDiagCheckResult _of(List<NetDiagCheckResult> rs, NetDiagCheckKind kind) =>
    rs.firstWhere((r) => r.kind == kind);

void main() {
  final target = parseNetDiagTarget('https://example.com')!;

  test('全通：四项都 ok，DNS 给出解析出的地址', () async {
    final fake = _FakeTransport(addresses: const ['1.2.3.4', '5.6.7.8']);
    final rs = await NetDiagProbe(transport: fake).runAll(target);

    expect(rs, hasLength(4));
    expect(rs.every((r) => r.ok), isTrue);
    expect(_of(rs, NetDiagCheckKind.dns).details, ['1.2.3.4', '5.6.7.8']);
    expect(_of(rs, NetDiagCheckKind.tls).summary, contains('剩余'));
    expect(fake.httpCalls, 1);
  });

  test('输入是 IP 时不查 DNS，并且说明为什么跳过', () async {
    final fake = _FakeTransport();
    final rs = await NetDiagProbe(
      transport: fake,
    ).runAll(parseNetDiagTarget('1.2.3.4')!);

    expect(fake.lookupCalls, 0, reason: 'IP 字面量不该走解析');
    final dns = _of(rs, NetDiagCheckKind.dns);
    expect(dns.ok, isTrue);
    expect(dns.summary, contains('无需解析'));
  });

  test('DNS 失败：只有这一项失败，其它项照跑', () async {
    final fake = _FakeTransport(dnsError: const SocketException('lookup failed'));
    final rs = await NetDiagProbe(transport: fake).runAll(target);

    final dns = _of(rs, NetDiagCheckKind.dns);
    expect(dns.ok, isFalse);
    expect(dns.error, isNotNull);
    expect(_of(rs, NetDiagCheckKind.tcp).ok, isTrue, reason: '一项失败不该拖垮其它项');
    expect(fake.tcpCalls, 1);
  });

  test('端口连不上：原因是拒绝连接，不是「失败」两个字', () async {
    final fake = _FakeTransport(
      tcpError: const SocketException('refused', osError: OSError('Connection refused', 111)),
    );
    final rs = await NetDiagProbe(transport: fake).runAll(target);

    final tcp = _of(rs, NetDiagCheckKind.tcp);
    expect(tcp.ok, isFalse);
    expect(tcp.error, contains('Connection refused'));
  });

  test('超时：原因是等了几秒（不许表现成一直在加载）', () async {
    final fake = _FakeTransport(tcpError: TimeoutException('slow'));
    final rs = await NetDiagProbe(
      transport: fake,
      timeout: const Duration(seconds: 3),
    ).runAll(target);

    final tcp = _of(rs, NetDiagCheckKind.tcp);
    expect(tcp.ok, isFalse);
    expect(tcp.error, contains('3 秒'));
  });

  test('证书 30 天内到期：算通过但要提醒', () async {
    final fake = _FakeTransport(
      tlsNotAfter: DateTime.now().add(const Duration(days: 12)),
    );
    final tls = _of(
      await NetDiagProbe(transport: fake).runAll(target),
      NetDiagCheckKind.tls,
    );

    expect(tls.ok, isTrue);
    expect(tls.summary, contains('12 天'));
    expect(tls.warning, isNotNull, reason: '快到期了要给提醒');
  });

  test('证书健康时不给多余提醒（控制组）', () async {
    final fake = _FakeTransport(
      tlsNotAfter: DateTime.now().add(const Duration(days: 200)),
    );
    final tls = _of(
      await NetDiagProbe(transport: fake).runAll(target),
      NetDiagCheckKind.tls,
    );
    expect(tls.ok, isTrue);
    expect(tls.warning, isNull);
  });

  test('证书已过期：判失败并写明过期时间', () async {
    final fake = _FakeTransport(
      tlsNotAfter: DateTime.now().subtract(const Duration(days: 2)),
    );
    final tls = _of(
      await NetDiagProbe(transport: fake).runAll(target),
      NetDiagCheckKind.tls,
    );
    expect(tls.ok, isFalse);
    expect(tls.error, contains('过期'));
  });

  test('TLS 握手失败：判失败并带上原因', () async {
    final fake = _FakeTransport(
      tlsError: const HandshakeException('CERTIFICATE_VERIFY_FAILED'),
    );
    final tls = _of(
      await NetDiagProbe(transport: fake).runAll(target),
      NetDiagCheckKind.tls,
    );
    expect(tls.ok, isFalse);
    expect(tls.error, contains('CERTIFICATE_VERIFY_FAILED'));
  });

  test('明文 http：不查 TLS 也不报假失败，但要说明不适用', () async {
    final fake = _FakeTransport();
    final rs = await NetDiagProbe(
      transport: fake,
    ).runAll(parseNetDiagTarget('http://example.com')!);

    final tls = _of(rs, NetDiagCheckKind.tls);
    expect(tls.ok, isTrue);
    expect(tls.details.join(), contains('不适用'));
    expect(fake.tlsCalls, 0, reason: '没写 https 就别去握手');
  });

  test('HTTP 404：算失败并带上状态码；3xx 算通过但说明要跳转', () async {
    final notFound = _of(
      await NetDiagProbe(transport: _FakeTransport(httpStatus: 404)).runAll(target),
      NetDiagCheckKind.http,
    );
    expect(notFound.ok, isFalse);
    expect(notFound.error, contains('404'));

    final moved = _of(
      await NetDiagProbe(
        transport: _FakeTransport(httpStatus: 301, httpLocation: 'https://www.example.com/'),
      ).runAll(target),
      NetDiagCheckKind.http,
    );
    expect(moved.ok, isTrue);
    expect(moved.summary, contains('跳转'));
    expect(moved.details.join(), contains('https://www.example.com/'));
  });

  test('报告文本包含四项结论与来源说明（用户要能复制走）', () async {
    final rs = await NetDiagProbe(transport: _FakeTransport()).runAll(target);
    final text = NetDiagReport(
      target: target,
      results: rs,
      startedAt: DateTime(2026, 9, 27, 12),
    ).toPlainText();

    for (final kind in NetDiagCheckKind.values) {
      expect(text, contains(kind.label));
    }
    expect(text, contains('不经过 Box 服务器'));
    expect(text, contains('不含 ICMP ping'));
  });
}
