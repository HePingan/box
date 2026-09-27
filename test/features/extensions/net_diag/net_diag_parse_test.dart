// 网络诊断：输入解析与错误翻译（纯逻辑，不联网）。
import 'dart:async';
import 'dart:io';
import 'package:box/features/extensions/plugins/net_diag/domain/net_diag_models.dart';
import 'package:box/features/extensions/plugins/net_diag/domain/net_diag_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('输入解析', () {
    test('只给主机名：按 https 与 443 推，并标出这是推出来的', () {
      final t = parseNetDiagTarget('box.hpa888.top')!;
      expect(t.host, 'box.hpa888.top');
      expect(t.scheme, 'https');
      expect(t.port, 443);
      expect(t.explicitPort, isFalse);
      expect(t.explicitScheme, isFalse);
    });

    test('主机名带端口：端口认用户的', () {
      final t = parseNetDiagTarget('example.com:8443')!;
      expect(t.host, 'example.com');
      expect(t.port, 8443);
      expect(t.explicitPort, isTrue);
    });

    test('完整 URL：只取主机与端口，路径丢掉', () {
      final t = parseNetDiagTarget('https://example.com/a/b?x=1#f')!;
      expect(t.host, 'example.com');
      expect(t.port, 443);
      expect(t.scheme, 'https');
      expect(t.explicitScheme, isTrue);
    });

    test('协议省了的 //host 写法也要认（真机上用户就是这么写的）', () {
      final t = parseNetDiagTarget('//example.com/dav')!;
      expect(t.host, 'example.com');
      expect(t.port, 443);
    });

    test('http 默认端口是 80；端口写 80 但没写协议时按 http 处理', () {
      expect(parseNetDiagTarget('http://example.com')!.port, 80);
      final t = parseNetDiagTarget('example.com:80')!;
      expect(t.port, 80);
      expect(t.scheme, 'http');
      expect(t.isHttps, isFalse);
    });

    test('IP 字面量认得出来（不必做 DNS 解析）', () {
      expect(parseNetDiagTarget('1.2.3.4')!.isIpLiteral, isTrue);
      expect(parseNetDiagTarget('1.2.3.4:22')!.port, 22);
      expect(parseNetDiagTarget('[::1]:443')!.host, '::1');
      expect(parseNetDiagTarget('example.com')!.isIpLiteral, isFalse);
    });

    test('末尾点、大小写、带凭据的写法都归一化', () {
      expect(parseNetDiagTarget('Example.COM.')!.host, 'example.com');
      expect(parseNetDiagTarget('user:pw@example.com')!.host, 'example.com');
    });

    test('认不出来的输入返回 null，不猜', () {
      for (final bad in ['', '   ', 'a b', 'http://', 'host:99999', 'host:abc', ':::', '中文域名']) {
        expect(
          parseNetDiagTarget(bad),
          isNull,
          reason: '「$bad」不该被当成可探测的目标',
        );
      }
    });
  });

  group('失败原因要能读懂（不许吞成空串）', () {
    test('超时 → 说出等了几秒', () {
      final text = describeNetDiagError(
        TimeoutException('timeout', const Duration(seconds: 8)),
        const Duration(seconds: 8),
      );
      expect(text, contains('8 秒'));
    });

    test('SocketException 的 osError 文案要带出来', () {
      final text = describeNetDiagError(
        const SocketException('failed', osError: OSError('Connection refused', 111)),
        const Duration(seconds: 8),
      );
      expect(text, contains('Connection refused'));
    });

    test('OsError 里没有 message 时给兜底文案，不返回空', () {
      final text = describeNetDiagError(
        const SocketException('failed', osError: OSError('')),
        const Duration(seconds: 8),
      );
      expect(text.trim(), isNotEmpty);
      expect(text, contains('连不上'));
    });
  });
}
