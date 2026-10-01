// 读屏凭证解析（quiz-vision 方案 A 第二轮：客户端零内置密钥）。
//
// 为什么需要这一层：读屏的基准档从「内置 key 直连」换成了「平台代理」，
// 而代理需要一个 Bearer —— 已登录用 session token，未登录用服务端签发的
// **匿名设备令牌**。取 token 涉及存储与网络，不能塞进展示层，
// 于是把「读凭证」收敛到这里，展示层只拿一个纯数据结果
// （[QuizVisionEndpoint]，分流规则在 domain 的 [resolveQuizVisionEndpoint]）。
//
// 口径：
//   * **永不抛**：任何一步失败都翻成可读原因返回 unavailable 档 —— 上层必须
//     如实展示，绝不静默退化成「未搜到答案」，也绝不回落内置 key（已删）；
//   * 手填凭证的用户**完全不碰**这条链路（不读存储、不签发设备令牌）；
//   * 令牌与设备标识只进安全存储，绝不进日志。
//
// 单测接缝：平台通道在单测里不存在，故构造器可注入 [store]/[client]/[accountStore]，
// 全局实例亦可用 [debugSetQuizVisionCredentialResolver] 替换。
import '../domain/quiz_vision_timeouts.dart';
import 'dart:async';

import '../../../utils/app_logger.dart';
import '../../../utils/log_channels.dart';
import '../../account/data/account_store.dart';
import '../../account/domain/account_models.dart';
import '../domain/quiz_config.dart';
import '../domain/quiz_vision_endpoint.dart';
import 'quiz_vision_device_token_client.dart';
import 'quiz_vision_device_token_store.dart';

class QuizVisionCredentialResolver {
  QuizVisionCredentialResolver({
    QuizVisionDeviceTokenStore? store,
    QuizVisionDeviceTokenClient? client,
    BoxAccountStore? accountStore,
  }) : _store = store ?? quizVisionDeviceTokenStore,
       _client = client ?? QuizVisionDeviceTokenClient(),
       _accountStore = accountStore ?? BoxAccountStore();

  final QuizVisionDeviceTokenStore _store;
  final QuizVisionDeviceTokenClient _client;
  final BoxAccountStore _accountStore;

  /// 凭证解析（含本机存储读取）的超时上限。
  ///
  /// 为什么必须有（2026-10-01 真机事故续）：发请求之前除了截图，还有一处**无界等待**
  /// —— 读本机存储（Keystore / SharedPreferences）。它一旦不回，界面同样永远停在
  /// 「读屏中」且服务端零请求。任何等待都要有终点：超时翻成 unavailable + 可读原因。
  /// 单测会把这里调小到几十毫秒。
  static Duration resolveTimeout = QuizVisionTimeouts.resolve;

  /// 解析本次读屏凭证。**不抛异常**：失败一律返回带可读原因的
  /// [QuizVisionMode.unavailable]。
  Future<QuizVisionEndpoint> resolve(QuizConfig config) =>
      _bounded(() => _resolveInner(config), what: '读屏凭证解析');

  /// 超时兜底：把任意解析流程收敛成「有终点的结果」。
  Future<QuizVisionEndpoint> _bounded(
    Future<QuizVisionEndpoint> Function() task, {
    required String what,
  }) async {
    try {
      return await task().timeout(resolveTimeout);
    } on TimeoutException catch (_) {
      _log('$what超时（${resolveTimeout.inSeconds}s，本机存储无响应）', warn: true);
      return QuizVisionEndpoint.unavailable('$what超时（本机存储无响应），请重试');
    }
  }

  /// [resolve] 的实现体（不做超时包装，超时统一由 [_bounded] 负责）。
  Future<QuizVisionEndpoint> _resolveInner(QuizConfig config) async {
    // 手填过 key 或端点：老直连逻辑原样，不读存储、不签发设备凭证。
    final userConfigured =
        config.apiUrl.trim().isNotEmpty || config.apiKey.trim().isNotEmpty;
    final serverUrl = await _loadServerUrl();
    if (userConfigured) {
      return resolveQuizVisionEndpoint(config, serverUrl: serverUrl);
    }

    // 已登录：Bearer = session token（服务器持真 key 转发）。
    final session = await _loadSession();
    final sessionToken = session?.token.trim() ?? '';
    if (sessionToken.isNotEmpty) {
      final saved = session!.serverUrl.trim();
      return resolveQuizVisionEndpoint(
        config,
        serverUrl: saved.isEmpty ? serverUrl : saved,
        sessionToken: sessionToken,
      );
    }

    // 未登录：本机设备令牌优先；没有就向账号服务器签发一次。
    // 签发失败**不降级**（客户端已无内置 key），如实带原因返回。
    final cached = await _readDeviceToken();
    if (cached.isNotEmpty) {
      return resolveQuizVisionEndpoint(
        config,
        serverUrl: serverUrl,
        deviceToken: cached,
      );
    }

    final deviceId = await _ensureDeviceId();
    final issued = await _client.issue(serverUrl: serverUrl, deviceId: deviceId);
    if (!issued.isSuccess) {
      _log('读屏设备令牌签发失败：${issued.error}', warn: true);
      return QuizVisionEndpoint.unavailable(issued.error);
    }
    final token = issued.token!;
    // 落盘失败不影响本次读屏（本次直接用内存里的新令牌），只留痕。
    try {
      await _store.writeDeviceToken(token);
    } catch (e) {
      _log('读屏设备令牌落盘失败（本次仍用内存令牌）：$e', warn: true);
    }
    return resolveQuizVisionEndpoint(
      config,
      serverUrl: serverUrl,
      deviceToken: token,
    );
  }

  /// 匿名档解析：**跳过登录档**（即使本机有会话令牌）。
  ///
  /// 用途：登录档的会话令牌被服务端判失效（代理 401）时降级重试 —— 读屏不该
  /// 因为"登录过期"而彻底不可用（2026-10-01 真机事故：服务端会话 30 天 TTL 到期，
  /// 登录用户读屏直接死在「凭证已失效」，而匿名档本来就是通的）。
  ///
  /// 手填凭证的用户仍按原样直连（不会把请求改道到平台）。失败不抛，返回 unavailable。
  Future<QuizVisionEndpoint> resolveAnonymous(QuizConfig config) =>
      _bounded(() => _resolveAnonymousInner(config), what: '读屏匿名凭证解析');

  /// [resolveAnonymous] 的实现体（超时统一由 [_bounded] 负责）。
  Future<QuizVisionEndpoint> _resolveAnonymousInner(QuizConfig config) async {
    final userConfigured =
        config.apiUrl.trim().isNotEmpty || config.apiKey.trim().isNotEmpty;
    if (userConfigured) {
      return resolveQuizVisionEndpoint(config, serverUrl: '');
    }
    final serverUrl = await _loadServerUrl();
    final cached = await _readDeviceToken();
    if (cached.isNotEmpty) {
      return resolveQuizVisionEndpoint(
        config,
        serverUrl: serverUrl,
        deviceToken: cached,
      );
    }
    final deviceId = await _ensureDeviceId();
    final issued = await _client.issue(serverUrl: serverUrl, deviceId: deviceId);
    if (!issued.isSuccess) {
      _log('读屏匿名降级：设备令牌签发失败 ${issued.error}', warn: true);
      return QuizVisionEndpoint.unavailable(issued.error);
    }
    final token = issued.token!;
    try {
      await _store.writeDeviceToken(token);
    } catch (e) {
      _log('读屏匿名降级：设备令牌落盘失败（本次用内存令牌）：$e', warn: true);
    }
    return resolveQuizVisionEndpoint(
      config,
      serverUrl: serverUrl,
      deviceToken: token,
    );
  }

  /// 设备令牌被服务端拒（代理 401）时调用：清掉本机令牌，
  /// 下次 [resolve] 会自动重新签发（自愈），用户无需重装/重登。
  ///
  /// 只清令牌、保留设备标识：服务端按标识记账与限额，换标识等于换设备。
  Future<void> invalidateDeviceToken() async {
    try {
      await _store.clearDeviceToken();
      _log('读屏设备令牌被拒，已清除本机令牌，下次自动重新签发');
    } catch (e) {
      _log('读屏设备令牌清除失败：$e', warn: true);
    }
  }

  /// 账号服务器地址：读失败回落线上默认地址（不是内置密钥，无凭证风险）。
  Future<String> _loadServerUrl() async {
    try {
      return await _accountStore.loadServerUrl();
    } catch (e) {
      _log('账号服务器地址读取失败，回落默认地址：$e', warn: true);
      return BoxAccountDefaults.serverUrl;
    }
  }

  /// 登录态：读失败按未登录处理（会走设备令牌档，而不是静默停摆）。
  Future<BoxAccountSession?> _loadSession() async {
    try {
      return await _accountStore.loadSession();
    } catch (e) {
      _log('登录态读取失败，按未登录处理：$e', warn: true);
      return null;
    }
  }

  Future<String> _readDeviceToken() async {
    try {
      return (await _store.readDeviceToken())?.trim() ?? '';
    } catch (e) {
      _log('读屏设备令牌读取失败，按未签发处理：$e', warn: true);
      return '';
    }
  }

  /// 设备标识：本机没有就生成一次并落盘（同一台设备复用同一个标识）。
  Future<String> _ensureDeviceId() async {
    try {
      final existing = (await _store.readDeviceId())?.trim() ?? '';
      if (existing.isNotEmpty) return existing;
    } catch (e) {
      _log('设备标识读取失败，重新生成：$e', warn: true);
    }
    final generated = generateQuizDeviceId();
    try {
      await _store.writeDeviceId(generated);
    } catch (e) {
      _log('设备标识落盘失败（本次仍用内存标识）：$e', warn: true);
    }
    return generated;
  }

  void _log(String message, {bool warn = false}) {
    AppLogger.instance.logTo(
      LogChannel.quiz,
      message,
      level: warn ? LogLevel.warn : LogLevel.info,
    );
  }
}

QuizVisionCredentialResolver _active = QuizVisionCredentialResolver();

/// 当前生效的解析器（读屏路径唯一取用点；测试注入优先）。
QuizVisionCredentialResolver get quizVisionCredentialResolver => _active;

/// 测试接缝：不传参恢复默认实现（与 debugSetOpsSecretStore 同形状）。
void debugSetQuizVisionCredentialResolver([
  QuizVisionCredentialResolver? resolver,
]) {
  _active = resolver ?? QuizVisionCredentialResolver();
}
