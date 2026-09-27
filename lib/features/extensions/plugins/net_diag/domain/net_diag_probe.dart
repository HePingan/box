// 网络诊断的探测实现。
//
// 分了传输层接缝（[NetDiagTransport]）：真机用 dart:io，单测注入假实现
// —— 单测不许联网（仓库纪律），而「真机会不会好」要另有一条 live 用例证明，
// 不能只靠假传输层。
library;

import 'dart:async';
import 'dart:io';

import 'net_diag_models.dart';

/// TCP 连通探测的结果。
class TcpProbeResult {
  const TcpProbeResult({required this.connected});
  final bool connected;
}

/// TLS 握手的结果（证书信息取自对端实际出示的证书）。
class TlsProbeResult {
  const TlsProbeResult({
    required this.subject,
    required this.issuer,
    required this.notBefore,
    required this.notAfter,
    required this.protocol,
  });

  final String subject;
  final String issuer;
  final DateTime notBefore;
  final DateTime notAfter;
  final String? protocol;
}

/// HTTP 响应探测的结果（只看响应头，不下载正文）。
class HttpProbeResult {
  const HttpProbeResult({
    required this.statusCode,
    required this.location,
    required this.serverHeader,
  });

  final int statusCode;
  final String? location;
  final String? serverHeader;
}

/// 探测要用到的底层能力。真机实现见 [IoNetDiagTransport]。
abstract class NetDiagTransport {
  /// 域名解析。解析不出（NXDOMAIN 等）由实现抛异常，调用方翻译成原因。
  Future<List<String>> lookupHost(String host);

  Future<TcpProbeResult> connectTcp(
    String host,
    int port,
    Duration timeout,
  );

  Future<TlsProbeResult> handshakeTls(
    String host,
    int port,
    Duration timeout,
  );

  Future<HttpProbeResult> getHttp(String url, Duration timeout);
}

/// 基于 dart:io 的真实现。
class IoNetDiagTransport implements NetDiagTransport {
  const IoNetDiagTransport();

  @override
  Future<List<String>> lookupHost(String host) async {
    final list = await InternetAddress.lookup(host);
    return list.map((a) => a.address).toSet().toList(growable: false);
  }

  @override
  Future<TcpProbeResult> connectTcp(
    String host,
    int port,
    Duration timeout,
  ) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    socket.destroy();
    return const TcpProbeResult(connected: true);
  }

  @override
  Future<TlsProbeResult> handshakeTls(
    String host,
    int port,
    Duration timeout,
  ) async {
    final socket = await SecureSocket.connect(
      host,
      port,
      timeout: timeout,
      onBadCertificate: (_) => true, // 诊断要看证书内容，不因自签名而中断
    );
    final cert = socket.peerCertificate;
    final info = TlsProbeResult(
      subject: cert?.subject ?? '（对端没有出示证书）',
      issuer: cert?.issuer ?? '',
      notBefore: cert?.startValidity ?? DateTime.fromMillisecondsSinceEpoch(0),
      notAfter: cert?.endValidity ?? DateTime.fromMillisecondsSinceEpoch(0),
      protocol: socket.selectedProtocol,
    );
    socket.destroy();
    return info;
  }

  @override
  Future<HttpProbeResult> getHttp(String url, Duration timeout) async {
    final client = HttpClient()..connectionTimeout = timeout;
    client.userAgent = 'BoxApp/NetDiag';
    try {
      final request = await client.getUrl(Uri.parse(url));
      // 不跟随跳转：诊断要报告「跳去哪儿」而不是被悄悄带走。
      request.followRedirects = false;
      final response = await request.close().timeout(timeout);
      final result = HttpProbeResult(
        statusCode: response.statusCode,
        location: response.headers.value(HttpHeaders.locationHeader),
        serverHeader: response.headers.value(HttpHeaders.serverHeader),
      );
      // 不读正文：诊断只需要响应头，下载整页在手机上既慢又费流量。
      await response.drain<void>().catchError((_) {});
      return result;
    } finally {
      client.close(force: true);
    }
  }
}

/// 一轮诊断：四项各自独立，一项失败不影响其它项。
class NetDiagProbe {
  NetDiagProbe({
    NetDiagTransport? transport,
    this.timeout = const Duration(seconds: 8),
  }) : _transport = transport ?? const IoNetDiagTransport();

  final NetDiagTransport _transport;

  /// 每项的默认超时。写死在这里并回报给界面，用户就不用猜「还要等多久」。
  final Duration timeout;

  /// 证书剩余天数低于这个值就给提醒（不是失败）。
  static const int certWarnDays = 30;

  /// 跑完全部四项，**四项并发**。
  ///
  /// 串行的代价是实打实的：每项超时 8 秒，最坏要等 4×8=32 秒。并发后最坏 8 秒。
  /// 每项一出结果就回调一次（回调顺序＝完成顺序，不固定），界面据此把固定四行逐行填上。
  /// 返回的列表按 [NetDiagCheckKind] 固定顺序排好，便于复制文本与断言稳定。
  Future<List<NetDiagCheckResult>> runAll(
    NetDiagTarget target, {
    void Function(NetDiagCheckResult)? onResult,
  }) async {
    final futures = <Future<NetDiagCheckResult>>[
      _dns(target),
      _tcp(target),
      _tls(target),
      _http(target),
    ];

    final collected = <NetDiagCheckResult>[];
    await Future.wait(
      futures.map((f) async {
        final r = await f;
        collected.add(r);
        onResult?.call(r);
        return r;
      }),
    );

    collected.sort((a, b) => a.kind.index.compareTo(b.kind.index));
    return collected;
  }

  Future<NetDiagCheckResult> _timed(
    NetDiagCheckKind kind,
    Future<NetDiagCheckResult> Function() body,
  ) async {
    final sw = Stopwatch()..start();
    try {
      final r = await body();
      sw.stop();
      return r.copyWith(elapsedMs: sw.elapsedMilliseconds);
    } catch (e) {
      // 故意吞：**这项的失败本身就是结论**（界面要显示"为什么不通"，而不是抛出去
      // 让整轮诊断崩掉）。原因经 describeNetDiagError 翻译成人话后写进 error 字段。
      sw.stop();
      return NetDiagCheckResult(
        kind: kind,
        ok: false,
        summary: '失败',
        error: describeNetDiagError(e, timeout),
        elapsedMs: sw.elapsedMilliseconds,
      );
    }
  }

  Future<NetDiagCheckResult> _dns(NetDiagTarget t) {
    return _timed(NetDiagCheckKind.dns, () async {
      if (t.isIpLiteral) {
        return NetDiagCheckResult(
          kind: NetDiagCheckKind.dns,
          ok: true,
          summary: '输入就是 IP，无需解析',
          details: [t.host],
        );
      }
      final addrs = await _transport.lookupHost(t.host).timeout(timeout);
      if (addrs.isEmpty) {
        return const NetDiagCheckResult(
          kind: NetDiagCheckKind.dns,
          ok: false,
          summary: '没有解析出地址',
          error: '解析结果为空',
        );
      }
      return NetDiagCheckResult(
        kind: NetDiagCheckKind.dns,
        ok: true,
        summary: '解析出 ${addrs.length} 个地址',
        details: addrs.take(6).toList(),
      );
    });
  }

  Future<NetDiagCheckResult> _tcp(NetDiagTarget t) {
    return _timed(NetDiagCheckKind.tcp, () async {
      await _transport.connectTcp(t.host, t.port, timeout).timeout(timeout);
      return NetDiagCheckResult(
        kind: NetDiagCheckKind.tcp,
        ok: true,
        summary: '端口 ${t.port} 可以连上',
      );
    });
  }

  Future<NetDiagCheckResult> _tls(NetDiagTarget t) {
    return _timed(NetDiagCheckKind.tls, () async {
      if (!t.isHttps) {
        return const NetDiagCheckResult(
          kind: NetDiagCheckKind.tls,
          ok: true,
          summary: '明文 http，没有证书',
          details: ['这一项不适用：只有 https 才有证书'],
        );
      }
      final cert = await _transport
          .handshakeTls(t.host, t.port, timeout)
          .timeout(timeout);
      final now = DateTime.now();
      // 向上取整到「天」：还剩 11.5 天时说 12 天符合口语习惯；
      // 整数截断会让「明天到期」显示成 0 天。
      final days = (cert.notAfter.difference(now).inMinutes / 1440).ceil();
      final details = <String>[
        '颁发给：${cert.subject}',
        if (cert.issuer.trim().isNotEmpty) '签发者：${cert.issuer}',
        '有效期至：${cert.notAfter.toIso8601String().split(".").first}',
        if (cert.protocol != null && cert.protocol!.isNotEmpty)
          '协商协议：${cert.protocol}',
      ];
      if (cert.notAfter.isBefore(now)) {
        return NetDiagCheckResult(
          kind: NetDiagCheckKind.tls,
          ok: false,
          summary: '证书已过期',
          details: details,
          error: '证书已于 ${cert.notAfter.toIso8601String().split(".").first} 过期',
        );
      }
      return NetDiagCheckResult(
        kind: NetDiagCheckKind.tls,
        ok: true,
        summary: '证书有效，剩余 $days 天',
        details: details,
        warning: days <= certWarnDays ? '不到 $certWarnDays 天（$days 天）就该续期了' : null,
      );
    });
  }

  Future<NetDiagCheckResult> _http(NetDiagTarget t) {
    return _timed(NetDiagCheckKind.http, () async {
      final r = await _transport.getHttp(t.url, timeout).timeout(timeout);
      final details = <String>[
        '状态码：${r.statusCode}',
        if (r.serverHeader != null) '服务器：${r.serverHeader}',
        if (r.location != null) '跳转到：${r.location}',
      ];
      final ok = r.statusCode >= 200 && r.statusCode < 400;
      return NetDiagCheckResult(
        kind: NetDiagCheckKind.http,
        ok: ok,
        summary: r.statusCode >= 300 && r.statusCode < 400
            ? 'HTTP ${r.statusCode}（服务端要求跳转）'
            : 'HTTP ${r.statusCode}',
        details: details,
        error: ok ? null : '服务端返回 ${r.statusCode}',
      );
    });
  }
}

/// 把底层异常翻译成用户能懂的原因。**不许把失败吞成空串。**
String describeNetDiagError(Object error, Duration timeout) {
  if (error is TimeoutException) {
    return '超时：${timeout.inSeconds} 秒内没有响应';
  }
  if (error is SocketException) {
    final os = error.osError;
    final detail = (os?.message ?? error.message).trim();
    return detail.isEmpty ? '连不上（网络错误）' : '连不上：$detail';
  }
  if (error is HandshakeException) {
    final m = error.message.trim();
    return m.isEmpty ? 'TLS 握手失败' : 'TLS 握手失败：$m';
  }
  if (error is HttpException) {
    final m = error.message.trim();
    return m.isEmpty ? 'HTTP 请求失败' : 'HTTP 请求失败：$m';
  }
  if (error is FormatException) {
    return '地址格式不对：${error.message}';
  }
  return error.toString().trim();
}
