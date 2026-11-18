import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/quiz_vision_endpoint.dart';
import '../domain/quiz_vision_usage.dart';

/// 服务端读屏配置 + **调用方自己**的今日额度（`GET {base}/config`）。
///
/// 为什么需要（2026-11-18 审计 P3-4 / P3-7）：
/// - 后台早就把「生效模型」做成了可切换（三个 admin 端点），但客户端只有在
///   设置页里看到 `qodercn/qfmodel` 这种本地值 —— 后台换了模型，自检页还显示旧值，
///   排查时会被自己的界面骗。
/// - 额度此前只能从**响应头**里捡（`X-Quiz-Vision-Used/Cap`），也就是「必须先发过
///   一次读屏请求」才知道今天还剩几次。现在有了主动查询，额度对用户可见。
class QuizVisionServerConfig {
  const QuizVisionServerConfig({
    required this.enabled,
    required this.model,
    required this.thinkingOff,
    required this.dailyCap,
    this.usedToday,
    this.remainingToday,
    this.failedToday,
    this.resetsAt,
    this.upstreamBudgetSeconds,
  });

  final bool enabled;
  final String model;
  final bool thinkingOff;
  final int dailyCap;

  /// 以下三项需要**有身份**（登录会话或设备令牌）才会返回；匿名时为空。
  final int? usedToday;
  final int? remainingToday;
  final int? failedToday;

  /// 额度重置时刻（服务端按 UTC 日界，北京时间每天 08:00）。
  final DateTime? resetsAt;

  /// 后端上游超时预算（秒）。客户端硬顶必须比它大。
  final int? upstreamBudgetSeconds;

  /// 解析失败时给一句可读原因。
  static QuizVisionServerConfig? fromJson(Object? raw) {
    if (raw is! Map) return null;
    int? intOf(String key) {
      final value = raw[key];
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value.trim());
      return null;
    }

    final cap = intOf('dailyCapPerAccount');
    if (cap == null) return null;
    return QuizVisionServerConfig(
      enabled: raw['enabled'] == true,
      model: (raw['model'] ?? '').toString().trim(),
      thinkingOff: raw['thinkingOff'] != false,
      dailyCap: cap,
      usedToday: intOf('usedToday'),
      remainingToday: intOf('remainingToday'),
      failedToday: intOf('failedToday'),
      resetsAt: DateTime.tryParse((raw['resetsAt'] ?? '').toString()),
      upstreamBudgetSeconds: intOf('upstreamBudgetSeconds'),
    );
  }

  /// 自检页/设置页用：模型那一行。
  String describeModel() {
    if (!enabled) return '后台未配置读屏上游（启用后台渠道会失败）';
    final name = model.isEmpty ? '未指定（由后台默认）' : model;
    return '$name${thinkingOff ? '（已关思考）' : '（带思考，可能偏慢）'}';
  }

  /// 自检页/设置页用：额度那一行。
  ///
  /// 失败次数单独说：2026-11-18 起上游失败**不计额度**，但用户仍然会看到
  /// 「今天试了 5 次都没答案」——把 failedToday 摊开比藏起来有用。
  String describeQuota() {
    if (usedToday == null) {
      return '未知（未登录且本机无设备令牌，服务端不回个人额度）';
    }
    final reset = resetsAt == null
        ? ''
        : '，${_resetText(resetsAt!)}重置';
    final failed = (failedToday ?? 0) > 0 ? '；上游失败 $failedToday 次（不计额度）' : '';
    return '今日已用 $usedToday/$dailyCap 次（剩余 ${remainingToday ?? (dailyCap - usedToday!)}）$reset$failed';
  }

  /// 服务端给的是 UTC 重置时刻，直接显示本地时间即可（用户在中国就是 08:00）。
  static String _resetText(DateTime utc) {
    final local = utc.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }
}

/// 主动拉取服务端配置与额度。
///
/// ⚠️ **不能顺手签发设备令牌**：签发是每 IP 每天 5 次的限额，自检页多开两次就会
/// 把读屏自己顶成 429（2026-10-01 踩过）。所以这里只用「本机已有」的凭证
/// （见 [QuizVisionCredentialResolver.peek]），没有就返回 null 由界面显示「未知」。
class QuizVisionServerConfigClient {
  QuizVisionServerConfigClient({
    http.Client? httpClient,
    Duration? timeout,
  }) : _http = httpClient ?? http.Client(),
       _timeout = timeout ?? const Duration(seconds: 6);

  final http.Client _http;
  final Duration _timeout;

  /// 返回 null 表示拿不到（无凭证 / 网络失败 / 老服务端）。**不抛异常**。
  Future<QuizVisionServerConfig?> fetch(QuizVisionEndpoint endpoint) async {
    if (endpoint.isUnavailable) return null;
    final url = '${endpoint.baseUrl}/config';
    try {
      final resp = await _http.get(
        Uri.parse(url),
        headers: {
          if (endpoint.apiKey.trim().isNotEmpty)
            'Authorization': 'Bearer ${endpoint.apiKey.trim()}',
        },
      ).timeout(_timeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      // utf8.decode(bodyBytes)：中文文案不能靠 response.body（latin-1 会乱码）。
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      final config = QuizVisionServerConfig.fromJson(decoded);
      if (config == null) return null;
      // 落到全局用量里：自检页/设置页/「复制结论」共用同一份口径。
      QuizVisionUsage.dailyCap = config.dailyCap;
      if (config.usedToday != null) QuizVisionUsage.usedToday = config.usedToday;
      QuizVisionUsage.failedToday = config.failedToday;
      QuizVisionUsage.resetsAt = config.resetsAt;
      QuizVisionUsage.updatedAt = DateTime.now();
      return config;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
