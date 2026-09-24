// HTTP Digest 认证（RFC 7616 / 2617，qop=auth）——挑战解析与响应头构造。
//
// 只在服务器拒绝 Basic 并给出 `WWW-Authenticate: Digest ...` 时才用（自建
// nginx/apache 的 DAV 配置常见）；坚果云、群晖、Nextcloud 都是 Basic，走不到这里。
//
// 纯逻辑、无 IO：输入全靠参数，连随机数（cnonce）都由调用方生成——这样
// RFC 2617 的示例向量可以逐字对照验证（见测试）。

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// 服务器要求了本实现不支持的 Digest 形式（如 `qop=auth-int`、SHA-512-256）。
class DigestUnsupported implements Exception {
  const DigestUnsupported(this.reason);

  /// 人话原因，可直接拼进用户可见的错误文案。
  final String reason;

  @override
  String toString() => reason;
}

/// `WWW-Authenticate: Digest ...` 里的挑战参数。
class DigestChallenge {
  const DigestChallenge({
    required this.realm,
    required this.nonce,
    this.qop,
    this.opaque,
    this.algorithm,
    this.stale = false,
  });

  final String realm;
  final String nonce;

  /// 服务端给的 qop 列表（原样，可能形如 `auth,auth-int`）；null = RFC 2069 老式。
  final String? qop;
  final String? opaque;

  /// 摘要算法（`MD5` / `MD5-sess` / `SHA-256` …）；null 按 MD5 处理（RFC 2617 默认）。
  final String? algorithm;

  /// `stale=true` 表示"nonce 过期了，用新 nonce 再来一次"（不是密码错）。
  final bool stale;

  /// 从 `WWW-Authenticate` 头解析 Digest 挑战；没有或不完整时返回 null。
  ///
  /// 头里可能同时有多个挑战（`Basic realm="x", Digest realm="y", ...`），所以按
  /// `digest ` 关键字定位而不是要求整头以它开头。
  static DigestChallenge? tryParse(String? headerValue) {
    if (headerValue == null || headerValue.trim().isEmpty) return null;
    final at = headerValue.toLowerCase().indexOf('digest ');
    if (at < 0) return null;
    final params = _splitParams(headerValue.substring(at + 'digest '.length));
    final realm = params['realm'];
    final nonce = params['nonce'];
    if (realm == null || nonce == null) return null;
    return DigestChallenge(
      realm: realm,
      nonce: nonce,
      qop: params['qop'],
      opaque: params['opaque'],
      algorithm: params['algorithm'],
      stale: params['stale']?.toLowerCase() == 'true',
    );
  }

  /// 本实现能否满足该挑战；返回 null 表示可以，否则是人话原因。
  String? get unsupportedReason {
    try {
      _hashFor(algorithm);
      _pickQop(qop);
      return null;
    } on DigestUnsupported catch (e) {
      return e.reason;
    }
  }

  @override
  String toString() =>
      'DigestChallenge(realm=$realm, algorithm=${algorithm ?? 'MD5'}, qop=${qop ?? '-'}, stale=$stale)';
}

/// 客户端随机数 cnonce（16 字节十六进制）。
///
/// 用 [Random.secure]：cnonce 参与摘要，可预测的 cnonce 会让重放/碰撞容易得多。
String newDigestCnonce() {
  final rnd = Random.secure();
  return List<int>.generate(16, (_) => rnd.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

/// 构造 `Authorization` 头值（不含 `Authorization:` 前缀）。
///
/// [uri] 是请求行里的 uri（路径 + 查询，保持与请求一致，别做二次编码）；
/// [nc] 是同一 nonce 下的请求序号，从 1 开始递增（服务端用它防重放）。
///
/// 不支持的算法/qop 抛 [DigestUnsupported]——宁可不发这个头（让上层给出明确
/// 提示），也不要发一个服务器看不懂的响应头把自己锁死。
String buildDigestAuthorization({
  required DigestChallenge challenge,
  required String username,
  required String password,
  required String method,
  required String uri,
  required String cnonce,
  required int nc,
}) {
  final hash = _hashFor(challenge.algorithm);
  final qop = _pickQop(challenge.qop);

  String h(String input) => hash.convert(utf8.encode(input)).toString();

  var ha1 = h('$username:${challenge.realm}:$password');
  if ((challenge.algorithm ?? '').toLowerCase().endsWith('-sess')) {
    ha1 = h('$ha1:${challenge.nonce}:$cnonce');
  }
  final ha2 = h('$method:$uri');

  final ncHex = nc.toRadixString(16).padLeft(8, '0');
  final response = qop == null
      ? h('$ha1:${challenge.nonce}:$ha2')
      : h('$ha1:${challenge.nonce}:$ncHex:$cnonce:$qop:$ha2');

  final parts = <String>[
    'username="${_quote(username)}"',
    'realm="${_quote(challenge.realm)}"',
    'nonce="${_quote(challenge.nonce)}"',
    'uri="$uri"',
  ];
  if (challenge.algorithm != null) parts.add('algorithm=${challenge.algorithm}');
  if (qop != null) {
    parts
      ..add('qop=$qop')
      ..add('nc=$ncHex')
      ..add('cnonce="$cnonce"');
  }
  parts.add('response="$response"');
  if (challenge.opaque != null) parts.add('opaque="${_quote(challenge.opaque!)}"');
  return 'Digest ${parts.join(', ')}';
}

/// 算法名 → 摘要实现；null 按 MD5（RFC 2617 的默认值）。
Hash _hashFor(String? algorithm) {
  switch ((algorithm ?? 'MD5').toUpperCase()) {
    case 'MD5':
    case 'MD5-SESS':
      return md5;
    case 'SHA-256':
    case 'SHA-256-SESS':
      return sha256;
    default:
      throw DigestUnsupported('摘要算法 $algorithm');
  }
}

/// qop 列表 → 采用的 qop（null = 按 RFC 2069 无 qop 形式）。
String? _pickQop(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final options = raw
      .split(',')
      .map((s) => s.trim().toLowerCase())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
  if (options.contains('auth')) return 'auth';
  if (options.contains('auth-int')) {
    // auth-int 要对请求体做摘要：下载/上传大文件时要么重读一遍要么缓冲整个文件，
    // 代价与收益不成比例（服务端也很少只给 auth-int）。
    throw const DigestUnsupported('qop=auth-int（需要请求体摘要）');
  }
  // 既没有 auth 也没有 auth-int：按 RFC 2069 兼容形式处理。
  return null;
}

/// 逗号分隔的参数表 → 小写键的 map；值两边的引号剥掉，引号内的逗号不切分。
Map<String, String> _splitParams(String raw) {
  final out = <String, String>{};
  final buf = StringBuffer();
  var inQuote = false;
  final chunks = <String>[];
  for (final unit in raw.split('')) {
    if (unit == '"') inQuote = !inQuote;
    if (unit == ',' && !inQuote) {
      chunks.add(buf.toString());
      buf.clear();
      continue;
    }
    buf.write(unit);
  }
  chunks.add(buf.toString());

  for (final chunk in chunks) {
    final eq = chunk.indexOf('=');
    if (eq <= 0) continue;
    final key = chunk.substring(0, eq).trim().toLowerCase();
    var value = chunk.substring(eq + 1).trim();
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    }
    out[key] = value;
  }
  return out;
}

/// quoted-string 里的转义（RFC 2617）：`\` 与 `"` 要反斜杠转义。
String _quote(String value) =>
    value.replaceAll('\\', r'\\').replaceAll('"', r'\"');
