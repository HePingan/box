import 'quiz_config.dart';

/// AI 读屏凭证（方案 A：服务端代理；本轮扩展：未登录走匿名设备令牌）。
///
/// 客户端**零内置密钥**：APK 里不再有任何 `sk-` 形态的密钥字面量
/// （历史事故：内置 key 被渠道吊销 → 全体用户读屏失效，只能发版救）。
/// 凭证只有两个来源：**用户手填**（[QuizVisionMode.ownKey]）或**服务端签发**
/// （代理两档，客户端只拿 token，真 key 不出服务器）。
///
/// - [ownKey]：直连 OpenAI 兼容端点，凭证来自用户手填（老逻辑原样，绝不改道）。
/// - [platformProxy]：已登录用户 —— Bearer 带登录 session token 打平台
///   `/api/quiz/vision`，服务器持真实 key 转发上游。
/// - [deviceProxy]：**未登录**用户 —— 同一条代理，Bearer 换成服务端签发的
///   匿名设备令牌（本机 Keystore 存储）。两条代理路径的线缆形状完全一致。
/// - [unavailable]：没有任何可用凭证（未登录且设备令牌签发失败/服务器地址缺失）。
///   此时**必须如实报错**（见 [QuizVisionEndpoint.errorMessage]），
///   既不许回落到内置 key（已删除），也不许退化成「未搜到答案」。
enum QuizVisionMode { ownKey, platformProxy, deviceProxy, unavailable }

/// 直连兜底**端点**（B 档渠道）：用户手填了 key 但没填地址时用。
///
/// 只放端点、不放密钥 —— 密钥只能来自用户手填或服务端签发。
const String defaultVisionApiUrl = 'https://newapi.hpa888.top/v1';


/// 读屏端点/凭证解析结果（纯数据）。
class QuizVisionEndpoint {
  const QuizVisionEndpoint({
    required this.mode,
    required this.baseUrl,
    required this.apiKey,
    this.errorMessage = '',
  });

  /// 无凭证可用：带可读原因。[baseUrl] 留空，明确「不该发起请求」。
  const QuizVisionEndpoint.unavailable(String reason)
    : mode = QuizVisionMode.unavailable,
      baseUrl = '',
      apiKey = '',
      errorMessage = reason;

  /// 代理路径段。引擎统一 POST `{base}/chat/completions`，服务端提供
  /// 别名路由 `/api/quiz/vision/chat/completions` 接收，引擎零改动。
  static const String proxyPathSegment = '/api/quiz/vision';

  final QuizVisionMode mode;

  /// 引擎将以 `$baseUrl/chat/completions` 提交。
  final String baseUrl;
  final String apiKey;

  /// 仅 [QuizVisionMode.unavailable] 有值：给用户看的失败原因（必非空）。
  final String errorMessage;

  bool get isUnavailable => mode == QuizVisionMode.unavailable;

  /// 是否走平台代理（两种代理档共用一套错误文案与「确定性失败不重试」口径）。
  bool get viaProxy =>
      mode == QuizVisionMode.platformProxy || mode == QuizVisionMode.deviceProxy;
}

/// 解析本次读屏请求的端点与凭证 —— **单一入口**
/// （test/quiz_vision_endpoint_resolution_test.dart 逐条回归）。
///
/// 分流：
///   ① 手填 key 或端点 → 老直连逻辑**原样**（绝不静默改道到代理）；
///   ② 全空 + 已登录 → 平台代理：base=账号服务器+/api/quiz/vision，
///      Bearer 用 session token；
///   ③ 全空 + 未登录 → 平台代理：Bearer 用服务端签发的匿名设备令牌；
///   ④ 都没有 → [QuizVisionMode.unavailable] + 可读原因（不静默失败）。
///
/// 纯函数：不读存储、不发网络。[sessionToken]/[deviceToken] 由
/// `QuizVisionCredentialResolver`（data 层）负责取得后传入。
QuizVisionEndpoint resolveQuizVisionEndpoint(
  QuizConfig config, {
  required String serverUrl,
  String sessionToken = '',
  String deviceToken = '',
}) {
  final userUrl = config.apiUrl.trim();
  final userKey = config.apiKey.trim();
  final server = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');

  // ① 手填过 key 或端点 → 老逻辑原样，绝不改道。
  if (userKey.isNotEmpty || userUrl.isNotEmpty) {
    return QuizVisionEndpoint(
      mode: QuizVisionMode.ownKey,
      baseUrl: userUrl.isEmpty ? defaultVisionApiUrl : userUrl,
      apiKey: userKey,
    );
  }

  // ② 已登录 → 平台代理（Bearer = session token，客户端零 key）。
  final session = sessionToken.trim();
  if (session.isNotEmpty) {
    if (server.isEmpty) {
      return const QuizVisionEndpoint.unavailable(
        '读屏需要平台代理，但拿不到账号服务器地址；请重新登录后再试',
      );
    }
    return QuizVisionEndpoint(
      mode: QuizVisionMode.platformProxy,
      baseUrl: '$server${QuizVisionEndpoint.proxyPathSegment}',
      apiKey: session,
    );
  }

  // ③ 未登录 → 同一条代理，Bearer = 服务端签发的匿名设备令牌。
  final device = deviceToken.trim();
  if (device.isNotEmpty) {
    if (server.isEmpty) {
      return const QuizVisionEndpoint.unavailable(
        '读屏需要平台代理，但拿不到账号服务器地址；请检查网络后再试',
      );
    }
    return QuizVisionEndpoint(
      mode: QuizVisionMode.deviceProxy,
      baseUrl: '$server${QuizVisionEndpoint.proxyPathSegment}',
      apiKey: device,
    );
  }

  // ④ 无凭证：如实报错（历史上这里是「内置 key 直连」，现在绝不回落）。
  return const QuizVisionEndpoint.unavailable(
    '读屏未取得可用凭证（未登录且未拿到匿名设备令牌）；请检查网络后重试，或先登录账号',
  );
}

/// 代理档 401 文案 —— **唯一来源**：`visionHttpErrorText` 与
/// `QuizPluginEntry` 的设备令牌自愈判定共用同一个常量，避免两处字面量漂移。
const String visionProxyCredentialExpiredText =
    '读屏凭证已失效：登录用户请到「我的」重新登录；未登录请稍后重试（会自动重新签发设备令牌）';

/// 读屏 HTTP 状态码 → 用户可读文案。
///
/// 代理两种档共用代理分支：401/403/429 都是确定性结论（凭证失效 / 代理未开 /
/// 日限额），必须给**可行动**文案；直连保留旧「渠道鉴权不稳」口径
/// （同一 key 间歇 200/401 的历史实测结论）。
String visionHttpErrorText(int statusCode, {required bool viaProxy}) {
  if (viaProxy) {
    switch (statusCode) {
      case 401:
        return visionProxyCredentialExpiredText;
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
