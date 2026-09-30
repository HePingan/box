// 匿名设备令牌的签发客户端（quiz-vision 方案 A 第二轮）。
//
// 契约（与服务端同时冻结，字段名/状态码都是线缆的一部分）：
//   POST <账号服务器>/api/quiz/vision/device-token
//   body:   {"deviceId": "<8-64 字符的不透明设备标识>"}
//   200  →  {"token":"<64 位 hex>","deviceId":"...","dailyCap":100,"expiresInDays":null}
//   429  →  限流；400 → 设备标识被拒。
//
// 口径：**一切失败都翻成中文可读原因**，绝不抛给调用方、绝不静默降级
//（客户端已无内置 key，静默降级等于静默失败）。token 只进内存/安全存储，
// 绝不进日志与错误文案。
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// 签发结果：要么有 token，要么有可读原因，不会两个都空。
class QuizVisionDeviceTokenResult {
  const QuizVisionDeviceTokenResult.success(this.token) : error = '';

  const QuizVisionDeviceTokenResult.failure(this.error) : token = null;

  final String? token;
  final String error;

  bool get isSuccess => token != null && token!.isNotEmpty;
}

/// 生成不透明的设备标识：16 字节随机 → 32 字符十六进制
/// （契约要求 8~64 字符；随机而非 ANDROID_ID 之类的硬件号，避免可关联）。
String generateQuizDeviceId({Random? random}) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class QuizVisionDeviceTokenClient {
  QuizVisionDeviceTokenClient({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  /// 签发端点（与 `QuizVisionEndpoint.proxyPathSegment` 同源的子路径）。
  static const String pathSegment = '/api/quiz/vision/device-token';

  /// 签发是读屏的前置步骤，不能把等待拖长（代理本身还有 45s 预算）。
  static const Duration requestTimeout = Duration(seconds: 10);

  final http.Client _httpClient;

  Future<QuizVisionDeviceTokenResult> issue({
    required String serverUrl,
    required String deviceId,
  }) async {
    final base = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) {
      return const QuizVisionDeviceTokenResult.failure('账号服务器地址为空，无法签发读屏设备令牌');
    }
    final id = deviceId.trim();
    if (id.length < 8 || id.length > 64) {
      return QuizVisionDeviceTokenResult.failure(
        '设备标识长度不合法（${id.length} 字符，契约要求 8~64）',
      );
    }

    http.Response response;
    try {
      response = await _httpClient
          .post(
            Uri.parse('$base$pathSegment'),
            headers: const {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({'deviceId': id}),
          )
          .timeout(requestTimeout);
    } on TimeoutException {
      return QuizVisionDeviceTokenResult.failure(
        '读屏设备令牌签发超时（${requestTimeout.inSeconds}s）',
      );
    } catch (e) {
      return QuizVisionDeviceTokenResult.failure('读屏设备令牌签发请求异常：$e');
    }

    final status = response.statusCode;
    if (status != 200) {
      switch (status) {
        case 400:
          return const QuizVisionDeviceTokenResult.failure(
            '读屏设备令牌签发被拒（HTTP 400：设备标识不合法）',
          );
        case 403:
          return const QuizVisionDeviceTokenResult.failure(
            '读屏设备令牌签发被拒（HTTP 403：代理未开放）',
          );
        case 429:
          return const QuizVisionDeviceTokenResult.failure(
            '读屏设备令牌签发过于频繁（HTTP 429），请稍后再试',
          );
      }
      return QuizVisionDeviceTokenResult.failure('读屏设备令牌签发失败（HTTP $status）');
    }

    Map<String, dynamic> decoded;
    try {
      // 显式按 UTF-8 解码：错误体里若有中文，走 latin-1 会变乱码。
      final raw = jsonDecode(utf8.decode(response.bodyBytes));
      if (raw is! Map<String, dynamic>) {
        return const QuizVisionDeviceTokenResult.failure('读屏设备令牌签发响应不是 JSON 对象');
      }
      decoded = raw;
    } catch (_) {
      return const QuizVisionDeviceTokenResult.failure('读屏设备令牌签发响应无法解析');
    }

    final token = decoded['token']?.toString().trim() ?? '';
    if (token.isEmpty) {
      return const QuizVisionDeviceTokenResult.failure('读屏设备令牌签发响应缺少 token 字段');
    }
    return QuizVisionDeviceTokenResult.success(token);
  }
}
