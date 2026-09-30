// 漫画中转：App → 自己的服务器 → 漫画站。**是退路，不是默认**（默认直连，见 comic_fetcher.dart）。
//
// 什么时候才需要它（2026-09-28 实测**纠正过一次判断**）：站点手机**能直连** —— 原先记的
// 「漫画站在手机那条网上被拦」是错的；真相是站点挑**客户端特征**：桌面 UA → `307` 且 body
// 0 字节、不带 UA 偶发直接丢连接、**手机 UA → 200 全量内容**。所以直连带上手机 UA 就够用。
// 中转留给「手机那条网真的到不了站点」这类情况（按 IP 拦、网络限流）——**配了设备令牌才走**。
//
// 走中转时的形状：
//
//   GET  <endpoint>?u=<urlencode(原始地址)>   → 200 原始响应体（HTML / 图片字节）
//   POST <endpoint>?u=…（表单）               → 只有站点的取图接口允许
//                                              `/api/comic/read/pics`、`/api/comic/read/index`
//   401 令牌无效 / 403 该主机不在白名单 / 502 取不到（JSON 体里有 `error` 字段）
//
// 两条纪律（与只读运维 API 同一套）：
//   * 设备令牌**只进请求头**（`X-Box-Token`）—— 绝不进 URL、绝不进错误文案、绝不进日志；
//   * 失败一律抛 [ComicProbeException]，并把服务器给的原因带上 —— 401/403/502 在界面上
//     必须分得清，否则用户只会看到「加载失败」四个字，没法自查。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'comic_fetcher.dart';
import 'comic_source_engine.dart' show ComicProbeException;

/// 中转客户端：把「原始地址」换成一个只跟自己服务器说话的请求。
class ComicRelay implements ComicFetcher {
  ComicRelay({
    required this.endpoint,
    required this.token,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  /// 中转入口（书源里的 `relay.endpoint`），如 `https://box.hpa888.top/comicrelay/fetch`。
  final String endpoint;

  /// 设备令牌（与只读运维 API 共用同一份）。**只进请求头**。
  final String token;

  /// 单次请求上限（服务器侧 25 秒，这里留点余量）。
  final Duration timeout;

  final http.Client _client;

  /// 请求头：令牌只在这里出现（**只发给本中转自己**）。
  @override
  Map<String, String> get headers => {
    'X-Box-Token': token,
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
  };

  /// 取**这一张图**要带的头：只有本中转自己的地址附令牌；图床地址（封面/章节图大多是
  /// 直连图床）只给手机 UA —— 把令牌发给第三方就是泄露。
  @override
  Map<String, String> headersFor(String url) =>
      comicImageHeadersFor(url, relayEndpoint: endpoint, relayToken: token);

  /// 取一个地址的**文本**（HTML / JSON）。
  @override
  Future<String> getText(String url) => _send(get: true, url: url);

  /// 表单 POST（站点的取图接口只认表单）。
  @override
  Future<String> postForm(String url, Map<String, String> form) =>
      _send(get: false, url: url, form: form);

  /// 能不能（且需要）包中转：只包 http/https，且**不包本中转自己的地址**（防重复包裹）。
  bool canRelay(String url) {
    final u = url.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) return false;
    if (Uri.tryParse(u) == null) return false;
    // 已经是本中转的地址（主机 + 路径前缀对得上）→ 不再包一层。
    // 判据与取图请求头共用一份（见 comic_fetcher.dart 的 isComicRelayAddress）。
    return !isComicRelayAddress(u, endpoint);
  }

  /// 把原始地址包成中转地址（图片下载用；令牌在请求头里，不在这个地址里）。
  @override
  String wrap(String url) {
    final u = url.trim();
    if (!canRelay(u)) return u;
    return _targetFor(u).toString();
  }

  /// 关掉底层连接池（页面销毁时用）。
  @override
  void close() => _client.close();

  // ── 内部 ──────────────────────────────────────────────────────

  Uri _targetFor(String url) =>
      Uri.parse(endpoint).replace(queryParameters: {'u': url});

  Future<String> _send({
    required bool get,
    required String url,
    Map<String, String>? form,
  }) async {
    final target = _targetFor(url);
    final http.Response resp;
    try {
      resp = await (get
              ? _client.get(target, headers: headers)
              : _client.post(target, headers: headers, body: form))
          .timeout(timeout);
    } on TimeoutException {
      throw ComicProbeException('中转超时（等了 ${timeout.inSeconds} 秒，服务器这一侧没回）');
    } catch (e) {
      throw ComicProbeException('中转请求失败：${_short(e)}');
    }
    // 自己按 UTF-8 解：`resp.body` 在响应没带 charset 时按 latin1 解，中文会乱码。
    final body = _decode(resp.bodyBytes);
    if (resp.statusCode != 200) {
      throw ComicProbeException(_failureText(resp.statusCode, body));
    }
    return body;
  }

  /// 非 200 的人话说明 + 服务器给的原因（**不含令牌**）。
  static String _failureText(int code, String body) {
    final hint = switch (code) {
      401 => '设备令牌无效或没填（设置 → 服务器 → 设备令牌）',
      403 => '这个主机不在中转白名单里',
      429 => '请求太频繁（中转限流），等一下再试',
      502 => '中转取不到（站点这一侧不可达）',
      _ => '中转返回 HTTP $code',
    };
    final detail = _jsonError(body);
    return detail == null ? hint : '$hint：$detail';
  }

  /// 服务器在 JSON 体里给的 `error`（没有就 null）。
  /// 只取这一个字段 —— 整个响应体塞进错误文案等于把不该露的东西带出去。
  static String? _jsonError(String body) {
    final t = body.trim();
    if (!t.startsWith('{')) return null;
    try {
      final m = jsonDecode(t);
      if (m is Map) {
        final e = m['error'];
        if (e is String && e.trim().isNotEmpty) return e.trim();
      }
    } catch (_) {
      // 不是 JSON：没有可带的细节，交给 hint。
    }
    return null;
  }

  static String _decode(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);

  static String _short(Object e) {
    final s = e.toString();
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }
}
