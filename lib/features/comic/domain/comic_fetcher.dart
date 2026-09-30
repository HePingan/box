// 取数的两种走法：**直连站点** 与 **经自己的服务器中转**。
//
// 为什么要有这个接口：章节取图那套逻辑（章节页拿 aid/cid → 取图接口按 offset 分批）
// 与"走哪条路"无关，只与"怎么发请求"有关。抽成同一个接口后，同一份分批逻辑既能跑
// 直连、也能跑中转，不必两处各自演化。
//
// 两条路的取舍（2026-09-28 实测纠正，之前判断反了）：
//   * **直连**才是默认。手机本来就能打开站点；直连的优点是不经服务器、不耗服务器流量。
//   * 站点对**客户端特征**挑剔，这才是真正的坑：同一个地址、同一台机器，
//     **Android Chrome UA → HTTP 200 全量 HTML**（实测搜索页 21 条、详情 398 话、
//     取图接口 200、封面图 `tuer.justpic01pt.com:666` 200 / 48 KB / image/jpeg）；
//     **桌面 UA → HTTP 307 且 body 为 0 字节**；不带 UA 偶发直接**丢连接**。
//     所以直连必须**带手机 UA**，否则看起来像"站点被墙"（当初就是这么误判的）。
//   * **中转**留着当退路：手机那条网真到不了站点、或站点按 IP 拦时机房也不一定行，
//     配了设备令牌就走它（见 comic_relay.dart）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'comic_source_engine.dart' show ComicProbeException;

/// 直连时用的 UA：**必须**是手机浏览器的样子（桌面 UA 会被站点 307 掉，见文件头注释）。
///
/// 用一个固定串而不是 `WebView` 的真实 UA：直连这条路跑在 dart:io 里，拿不到 WebView
/// 的 UA；而且 UA 固定下来，出问题时可复现。
const String kComicMobileUserAgent =
    'Mozilla/5.0 (Linux; Android 13; SM-S9180) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36';

/// 取图（封面 / 章节图）要带的头：手机 UA + 语言偏好。
///
/// 为什么不靠 Flutter 自带的 `Image.network`：那条路一份头都不带。图床跟站点一样
/// 看客户端特征（实测：不带 UA 的请求直接被丢连接），结果就是**站点里看得到封面、
/// App 里「封面加载不出来」**。所有取图都要经过这里（封面也一样）。
Map<String, String> comicDirectHeaders() => <String, String>{
  'User-Agent': kComicMobileUserAgent,
  'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
};

/// 这个地址是不是**我们自己的中转**（主机 + 路径前缀都对得上）。
bool isComicRelayAddress(String url, String endpoint) {
  final self = Uri.tryParse(endpoint.trim());
  final dest = Uri.tryParse(url.trim());
  if (self == null || dest == null || self.host.isEmpty) return false;
  return dest.host == self.host && dest.path.startsWith(self.path);
}

/// 取**这一张图**要带的头：**只有指向自建中转的地址才附令牌**，其余（漫画站、图床）
/// 一律只给手机 UA。
///
/// 为什么按地址分：令牌是我们自己服务器的凭据，发给第三方图床就是泄露（哪怕对方只是
/// 漫画站的 CDN）。图床地址是直连取的，只有中转包出来的地址才需要令牌。
Map<String, String> comicImageHeadersFor(
  String url, {
  String? relayEndpoint,
  String? relayToken,
}) {
  final token = (relayToken ?? '').trim();
  final endpoint = (relayEndpoint ?? '').trim();
  if (token.isNotEmpty &&
      endpoint.isNotEmpty &&
      isComicRelayAddress(url, endpoint)) {
    return <String, String>{
      'X-Box-Token': token,
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    };
  }
  return comicDirectHeaders();
}

/// 取数器：中转与直连都实现它（接口一样，调用方不用关心走哪条）。
abstract class ComicFetcher {
  /// 额外请求头（中转是 `X-Box-Token`，直连是手机 UA）。
  Map<String, String> get headers;

  /// 取**这个地址**要带的头：默认就是 [headers]；中转会按地址区分
  /// （只有自己的中转地址才附令牌，见 [comicImageHeadersFor]）。
  Map<String, String> headersFor(String url) => headers;

  /// 取一个地址的**文本**（HTML / JSON）。
  Future<String> getText(String url);

  /// 表单 POST（站点的取图接口只认表单）。
  Future<String> postForm(String url, Map<String, String> form);

  /// 把原始地址变成"取数器认得"的地址：中转要包一层，直连原样返回。
  String wrap(String url);

  /// 关掉底层连接池。
  void close();
}

/// 直连站点：手机自己去取（默认这条路）。
class ComicDirectFetcher implements ComicFetcher {
  ComicDirectFetcher({
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  /// 单次请求上限（站点偶发丢连接，别把界面拖成"一直转圈"）。
  final Duration timeout;

  final http.Client _client;

  @override
  Map<String, String> get headers => comicDirectHeaders();

  /// 直连对谁都给同一份头（手机 UA）：站点与图床都认这一个。
  @override
  Map<String, String> headersFor(String url) => comicDirectHeaders();

  @override
  Future<String> getText(String url) => _send(get: true, url: url);

  @override
  Future<String> postForm(String url, Map<String, String> form) =>
      _send(get: false, url: url, form: form);

  /// 直连没有"包地址"这回事：图片地址原样交给图片缓存（它自己带 [headers]）。
  @override
  String wrap(String url) => url;

  @override
  void close() => _client.close();

  // ── 内部 ──────────────────────────────────────────────────────

  Future<String> _send({
    required bool get,
    required String url,
    Map<String, String>? form,
  }) async {
    final uri = Uri.parse(url);
    final http.Response resp;
    try {
      resp = await (get
              ? _client.get(uri, headers: headers)
              : _client.post(uri, headers: headers, body: form))
          .timeout(timeout);
    } on TimeoutException {
      throw ComicProbeException('直连超时（等了 ${timeout.inSeconds} 秒，站点这一侧没回）');
    } catch (e) {
      // 站点偶发**直接丢连接**（实测同一地址三次里有一次连不上），也可能是网络本身的问题。
      throw ComicProbeException('连不上站点：${_short(e)}');
    }
    // 自己按 UTF-8 解：`resp.body` 在响应没带 charset 时按 latin1 解，中文会乱码。
    final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
    if (resp.statusCode != 200) {
      throw ComicProbeException(_failureText(resp.statusCode, body));
    }
    return body;
  }

  /// 非 200 的人话说明（直连不涉及令牌，措辞与中转区分开）。
  static String _failureText(int code, String body) {
    final hint = switch (code) {
      301 || 302 || 307 || 308 => '站点把请求跳走了（多半是客户端特征不被接受：要带手机 UA）',
      401 || 403 => '站点拒绝了这个请求（HTTP $code）',
      429 => '站点限流了（HTTP 429），等一下再试',
      _ => '站点返回 HTTP $code',
    };
    final t = body.trim();
    // 只在真是 JSON 错误体时带一句细节，别把整页 HTML 塞进错误文案。
    if (t.startsWith('{') && t.length <= 300) {
      try {
        final m = jsonDecode(t);
        if (m is Map && m['error'] is String) {
          return '$hint：${(m['error'] as String).trim()}';
        }
      } catch (_) {
        // 不是 JSON：就只说 hint。
      }
    }
    return hint;
  }

  static String _short(Object e) {
    final s = e.toString();
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }
}
