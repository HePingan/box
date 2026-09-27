// 网络诊断的输入解析与结果模型。
//
// 定位：**手机上直连目标**，不经过我们的服务器 —— App 此前只能看服务端探针
// 给出的结论（monitors.json），出了自家那两台就什么都查不了。
//
// 明确不做 ICMP ping：Dart 没有发 ICMP 的能力（要原生），所以用 TCP 连接测试
// 与 TLS 握手代替，并在界面上直说这件事 —— 不把「TCP 通」写成「ping 通」。
library;

/// 一项检测。
enum NetDiagCheckKind {
  dns,
  tcp,
  tls,
  http;

  String get label => switch (this) {
    NetDiagCheckKind.dns => '域名解析',
    NetDiagCheckKind.tcp => 'TCP 连通',
    NetDiagCheckKind.tls => 'TLS 证书',
    NetDiagCheckKind.http => 'HTTP 响应',
  };
}

/// 解析后的探测目标。
class NetDiagTarget {
  const NetDiagTarget({
    required this.raw,
    required this.host,
    required this.scheme,
    required this.port,
    required this.explicitPort,
    required this.explicitScheme,
  });

  /// 用户原样输入（回显用，别让用户以为自己输的被改了）。
  final String raw;
  final String host;
  final String scheme;
  final int port;

  /// 端口/协议是用户写明的，还是我们推出来的 —— 结论里要能说清。
  final bool explicitPort;
  final bool explicitScheme;

  bool get isHttps => scheme == 'https';

  /// 主机部分是不是字面量 IP（是的话不必做 DNS 解析）。
  bool get isIpLiteral => _ipv4.hasMatch(host) || host.contains(':');

  String get authority => '$host:$port';
  String get url => '$scheme://$host:$port';
}

final RegExp _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
final RegExp _hostPart = RegExp(r'^[A-Za-z0-9._\-\[\]:]+$');

/// 解析用户输入。无法解析时返回 null（界面据此提示，不要猜）。
///
/// 认这些写法：`example.com` · `example.com:8443` · `https://example.com/x` ·
/// `//example.com`（协议省了）· `1.2.3.4:22` · `[::1]:443`。
NetDiagTarget? parseNetDiagTarget(String input) {
  final raw = input.trim();
  if (raw.isEmpty) return null;
  if (raw.contains(RegExp(r'\s'))) return null;

  var rest = raw;
  String? scheme;
  final schemeMatch = RegExp(r'^([A-Za-z][A-Za-z0-9+.\-]*)://').firstMatch(rest);
  if (schemeMatch != null) {
    scheme = schemeMatch.group(1)!.toLowerCase();
    rest = rest.substring(schemeMatch.end);
  } else if (rest.startsWith('//')) {
    rest = rest.substring(2);
  }
  // 去掉路径 / 查询 / 锚点：诊断只看主机与端口。
  rest = rest.split(RegExp(r'[/?#]')).first;
  // 去掉可能的凭据段（user:pass@host）。
  final at = rest.lastIndexOf('@');
  if (at >= 0) rest = rest.substring(at + 1);
  if (rest.isEmpty) return null;
  if (!_hostPart.hasMatch(rest)) return null;

  var host = rest;
  var portText = '';
  var explicitPort = false;

  if (rest.startsWith('[')) {
    final close = rest.indexOf(']');
    if (close < 0) return null;
    host = rest.substring(1, close);
    final tail = rest.substring(close + 1);
    if (tail.isNotEmpty) {
      if (!tail.startsWith(':')) return null;
      portText = tail.substring(1);
      explicitPort = true;
    }
  } else {
    final colon = rest.lastIndexOf(':');
    if (colon >= 0) {
      host = rest.substring(0, colon);
      portText = rest.substring(colon + 1);
      explicitPort = true;
    }
  }

  if (host.isEmpty) return null;
  host = host.toLowerCase();
  if (host.endsWith('.')) host = host.substring(0, host.length - 1);
  if (host.isEmpty) return null;

  var port = scheme == 'http' ? 80 : 443;
  if (explicitPort) {
    final parsed = int.tryParse(portText);
    if (parsed == null || parsed < 1 || parsed > 65535) return null;
    port = parsed;
  }

  final explicitScheme = scheme != null;
  final effectiveScheme = scheme ?? (explicitPort && port == 80 ? 'http' : 'https');

  return NetDiagTarget(
    raw: raw,
    host: host,
    scheme: effectiveScheme,
    port: port,
    explicitPort: explicitPort,
    explicitScheme: explicitScheme,
  );
}

/// 一项检测的结果。失败也要有原因 —— 不许把失败表现成「一直在加载」。
class NetDiagCheckResult {
  const NetDiagCheckResult({
    required this.kind,
    required this.ok,
    required this.summary,
    this.details = const [],
    this.elapsedMs = 0,
    this.error,
    this.warning,
  });

  final NetDiagCheckKind kind;
  final bool ok;

  /// 一句话结论（界面主文案）。
  final String summary;
  final List<String> details;
  final int elapsedMs;

  /// 失败原因（ok=false 时必须有）。
  final String? error;

  /// 通过但值得提醒（如证书 30 天内到期）。
  final String? warning;

  NetDiagCheckResult copyWith({int? elapsedMs}) => NetDiagCheckResult(
    kind: kind,
    ok: ok,
    summary: summary,
    details: details,
    elapsedMs: elapsedMs ?? this.elapsedMs,
    error: error,
    warning: warning,
  );
}

/// 一次完整诊断的报告（可复制成文本）。
class NetDiagReport {
  const NetDiagReport({
    required this.target,
    required this.results,
    required this.startedAt,
  });

  final NetDiagTarget target;
  final List<NetDiagCheckResult> results;
  final DateTime startedAt;

  bool get allOk => results.every((r) => r.ok);
  int get failedCount => results.where((r) => !r.ok).length;

  /// 纯文本结论（用户要能复制走贴给别人）。
  String toPlainText() {
    final b = StringBuffer()
      ..writeln('网络诊断 ${target.raw}')
      ..writeln('主机 ${target.authority}（协议 ${target.scheme}）')
      ..writeln('时间 ${startedAt.toIso8601String()}')
      ..writeln('');
    for (final r in results) {
      final mark = r.ok ? (r.warning == null ? 'OK  ' : 'WARN') : 'FAIL';
      b.writeln('[$mark] ${r.kind.label}（${r.elapsedMs}ms）：${r.summary}');
      if (r.error != null) b.writeln('      原因：${r.error}');
      if (r.warning != null) b.writeln('      提醒：${r.warning}');
      for (final d in r.details) {
        b.writeln('      · $d');
      }
    }
    b.writeln('');
    b.writeln('（本结论由手机直连目标得出，不经过 Box 服务器；不含 ICMP ping）');
    return b.toString();
  }
}
