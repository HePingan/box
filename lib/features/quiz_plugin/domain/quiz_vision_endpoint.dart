/// AI 读屏凭证模式（方案 A：服务端代理）。
///
/// - [ownKey]：直连 OpenAI 兼容端点，key 来自用户手填或内置兜底（老逻辑）。
/// - [platformProxy]：登录用户零 key 模式 —— Bearer 带登录 token 打平台
///   `/api/quiz/vision`，服务器持真实 key 转发 newapi。key 吊销不再影响客户端。
enum QuizVisionMode { ownKey, platformProxy }

/// 读屏端点/凭证解析结果（纯数据）。
///
/// 解析逻辑在 `QuizPluginEntry.resolveVisionEndpointMode`（单一入口）——
/// 刻意不放本文件：内置兜底 key 属于展示层常量，密钥不落 domain。
class QuizVisionEndpoint {
  const QuizVisionEndpoint({
    required this.mode,
    required this.baseUrl,
    required this.apiKey,
  });

  /// 代理路径段。引擎统一 POST `{base}/chat/completions`，服务端提供
  /// 别名路由 `/api/quiz/vision/chat/completions` 接收，引擎零改动。
  static const String proxyPathSegment = '/api/quiz/vision';

  final QuizVisionMode mode;

  /// 引擎将以 `$baseUrl/chat/completions` 提交。
  final String baseUrl;
  final String apiKey;
}

/// 读屏 HTTP 状态码 → 用户可读文案。
///
/// 代理模式给**可行动**文案（重新登录 / 明日再来 / 代理未开）；
/// 直连保留旧「渠道鉴权不稳」口径（同一 key 间歇 200/401 的历史实测结论）。
String visionHttpErrorText(int statusCode, {required bool viaProxy}) {
  if (viaProxy) {
    switch (statusCode) {
      case 401:
        return '读屏登录已过期，请到「我的」重新登录后再试';
      case 403:
        return '读屏代理不可用（未开启或暂被限制）';
      case 429:
        return '今日 AI 读屏次数已用完，明天再来吧';
      case 503:
        return '读屏服务繁忙，稍后再试';
    }
  }
  if (statusCode == 401 || statusCode == 403) {
    return '读屏 API 返回 $statusCode（渠道鉴权不稳，稍后再试）';
  }
  return '读屏 API 返回 $statusCode';
}
