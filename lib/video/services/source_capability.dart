/// 源在「关键词搜索」这一档的**接口层能力**判定。
///
/// 起因（2026-10-03 实测：28 个源，走 App 同一条代理，关键词「战狼」）：
/// 8 个源在接口层就不可用 ——
/// - 豆瓣资源 / 茅台资源：返回 `{"code":1002,"msg":"Current API forbids keyword search"}`
///   （接口活着，但**禁止关键词搜索**）
/// - 卧龙资源 / 旺旺资源：api 地址返回的是 HTML 网页（已不是 VOD 接口）
/// - 无尽资源：403（WAF 拒机房 IP）；速播资源：522/502（源站宕机）
/// - 百度云 zy / 艾旦影视：404（那条第三方转发路径已下线）
///
/// 它们每次聚合搜索都陪跑：接口坏的占掉 fastFail 的 8 秒预算，而 1002 那类
/// 还会被解析成「成功但 0 结果」——在界面上完全看不见，只能靠总耗时感觉到。
///
/// 所以这里把判定做成两件可测的事：
/// 1. [classifySearchResponse]：一次真实响应 → 一个能力档（纯函数，不联网）；
/// 2. [SourceSearchCapabilityProbe]：只对**刚刚搜索失败的源**补一次探测，
///    用响应正文把「偶发抖动」与「接口层坏」分开 —— 后者直接自动隐藏，
///    不必再等它失败第二次。
library;

import 'video_api_service.dart';

/// 关键词搜索这一档的能力。
enum SourceSearchCapability {
  /// 没探到（超时/异常），不要据此做任何处置。
  unknown,

  /// 拿到标准 JSON 且 `code` 为成功值（`list` 可以为空 —— 那不是故障）。
  searchable,

  /// 接口活着但拒绝关键词搜索（`code` 非成功值，实测 `1002`）。
  keywordForbidden,

  /// 返回的不是 VOD 接口（HTML 网页 / 非 JSON）。
  notAnApi,

  /// 被拒（403/429）：多半是 WAF 拦机房 IP，换个出口可能可用，别急着抹杀。
  blocked,

  /// 连不上 / 5xx / 4xx 以外的 HTTP 故障：属网络类，先计数。
  unreachable,
}

/// 探测的原始响应。刻意保留正文：`1002` 这种「接口层拒绝」只有读到正文才知道。
/// （定义放在 [VideoApiService] 旁边，供能力分类器单向引用，避免库之间互相 import。）

/// 只按“这一次响应”判能力，不做任何重试与推断。
///
/// 判据顺序刻意从「确定性最高」往下走：状态码 → 正文形态 → `code` 字段。
SourceSearchCapability classifySearchResponse({
  required int? statusCode,
  required String body,
  String? contentType,
}) {
  if (statusCode == null) return SourceSearchCapability.unreachable;

  if (statusCode == 403 || statusCode == 429) {
    return SourceSearchCapability.blocked;
  }
  if (statusCode == 404 || statusCode == 410) {
    // 接口路径没了（实测百度云 zy / 艾旦影视那条第三方转发返回 404）。
    return SourceSearchCapability.notAnApi;
  }
  if (statusCode != 200) return SourceSearchCapability.unreachable;

  final trimmed = body.trimLeft();
  if (trimmed.isEmpty) return SourceSearchCapability.unknown;

  // 返回网页：地址已经不是一个 VOD 接口了。
  if (trimmed.startsWith('<')) return SourceSearchCapability.notAnApi;

  final looksLikeJson = trimmed.startsWith('{') || trimmed.startsWith('[');
  if (!looksLikeJson) return SourceSearchCapability.notAnApi;

  // 标准苹果 CMS 响应带 `code`：1 成功（有的实现用 0）。
  // 只取前 4000 字符找 code，避免大响应体上的正则开销。
  final head = trimmed.length > 4000 ? trimmed.substring(0, 4000) : trimmed;
  final match = RegExp(r'"code"\s*:\s*(-?\d+)').firstMatch(head);
  if (match == null) return SourceSearchCapability.unknown;

  final code = int.tryParse(match.group(1) ?? '');
  if (code == 1 || code == 0) return SourceSearchCapability.searchable;
  // 1002「Current API forbids keyword search」以及同族的权限类拒绝。
  return SourceSearchCapability.keywordForbidden;
}

/// 这一档是否属于「接口层坏了、重试也没用」——够格直接自动隐藏。
bool isStructurallyBroken(SourceSearchCapability capability) {
  return capability == SourceSearchCapability.keywordForbidden ||
      capability == SourceSearchCapability.notAnApi;
}

/// 这一档是否值得在界面上说一句（用户看到的「跳过」原因）。
String describeCapability(SourceSearchCapability capability) {
  switch (capability) {
    case SourceSearchCapability.keywordForbidden:
      return '接口禁止关键词搜索';
    case SourceSearchCapability.notAnApi:
      return '接口地址已不是 VOD 接口';
    case SourceSearchCapability.blocked:
      return '被站点拒绝（403）';
    case SourceSearchCapability.unreachable:
      return '连不上';
    case SourceSearchCapability.searchable:
      return '正常';
    case SourceSearchCapability.unknown:
      return '未探到';
  }
}

/// 对若干源各探一次「关键词搜索」，返回源 key → 能力。
///
/// 只用在**搜索失败的源**上（不额外打扰正常源），并发 4、单源 8 秒，
/// 整体失败绝不向上抛：能力探测永远不该影响搜索本身。
class SourceSearchCapabilityProbe {
  const SourceSearchCapabilityProbe({
    this.timeout = const Duration(seconds: 8),
    this.maxConcurrent = 4,
    this.keyword = '战狼',
    this.probeOverride,
  });

  final Duration timeout;
  final int maxConcurrent;

  /// 探测用的关键词：取一个稳定、各站都有的词，避免“没这个片”被误判。
  final String keyword;

  /// 仅供测试：替换真实网络探测。生产代码永不赋值。
  final Future<SourceProbeResponse> Function(String baseUrl, String keyword)?
  probeOverride;

  Future<SourceProbeResponse> _probe(String baseUrl) {
    final override = probeOverride;
    if (override != null) return override(baseUrl, keyword);
    return VideoApiService.probeSearchResponse(
      baseUrl,
      keyword: keyword,
      timeout: timeout,
    );
  }

  /// 逐个探测（并发受限），任何一个失败都只记 [SourceSearchCapability.unknown]。
  Future<List<({String baseUrl, SourceSearchCapability capability})>> probeAll(
    List<String> baseUrls,
  ) async {
    final out = <({String baseUrl, SourceSearchCapability capability})>[];
    var cursor = 0;

    Future<void> worker() async {
      while (true) {
        final index = cursor++;
        if (index >= baseUrls.length) return;
        final baseUrl = baseUrls[index];
        SourceSearchCapability capability;
        try {
          final response = await _probe(baseUrl);
          capability = classifySearchResponse(
            statusCode: response.statusCode,
            body: response.body,
            contentType: response.contentType,
          );
        } catch (_) {
          capability = SourceSearchCapability.unknown;
        }
        out.add((baseUrl: baseUrl, capability: capability));
      }
    }

    final workers = baseUrls.length < maxConcurrent
        ? baseUrls.length
        : maxConcurrent;
    await Future.wait(List.generate(workers, (_) => worker()));
    return out;
  }
}
