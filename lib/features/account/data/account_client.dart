import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/account_models.dart';
import '../domain/personal_center_models.dart';
import '../domain/usage_models.dart';

/// 注册结果。服务端注册响应里本来就带 `quota`，过去只取 token/user 白丢了，
/// 导致刚注册完还要再打一次 /api/image/quota 才知道自己有多少额度。
class BoxRegisterResult {
  const BoxRegisterResult({required this.session, this.quota});

  final BoxAccountSession session;
  final PersonalQuota? quota;
}

class BoxAccountClient {
  BoxAccountClient({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Future<BoxRegisterResult> register({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final normalizedServer = normalizeServerUrl(serverUrl);
    final response = await _httpClient.post(
      _uri(normalizedServer, '/api/auth/register'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username.trim(), 'password': password}),
    );
    final decoded = _decodeResponse(response);
    final token = decoded['token']?.toString() ?? '';
    final userJson = decoded['user'];
    if (token.isEmpty || userJson is! Map<String, dynamic>) {
      throw const BoxAccountException('注册接口返回格式不完整。');
    }
    final quotaJson = decoded['quota'];
    return BoxRegisterResult(
      session: BoxAccountSession(
        serverUrl: normalizedServer,
        token: token,
        user: BoxAccountUser.fromJson(userJson),
      ),
      quota: quotaJson is Map
          ? PersonalQuota.fromJson(Map<String, dynamic>.from(quotaJson))
          : null,
    );
  }

  Future<BoxAccountSession> login({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final normalizedServer = normalizeServerUrl(serverUrl);
    final response = await _httpClient.post(
      _uri(normalizedServer, '/api/auth/login'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username.trim(), 'password': password}),
    );
    final decoded = _decodeResponse(response);
    final token = decoded['token']?.toString() ?? '';
    final userJson = decoded['user'];
    if (token.isEmpty || userJson is! Map<String, dynamic>) {
      throw const BoxAccountException('登录接口返回格式不完整。');
    }
    return BoxAccountSession(
      serverUrl: normalizedServer,
      token: token,
      user: BoxAccountUser.fromJson(userJson),
    );
  }

  Future<BoxAccountUser> updateMyProfile({
    required String serverUrl,
    required String token,
    required String nickname,
  }) async {
    final response = await _httpClient.patch(
      _uri(normalizeServerUrl(serverUrl), '/api/me/profile'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'nickname': nickname.trim()}),
    );
    return BoxAccountUser.fromJson(_decodeResponse(response));
  }

  Future<BoxAccountUser> me({
    required String serverUrl,
    required String token,
  }) async {
    final response = await _httpClient.get(
      _uri(normalizeServerUrl(serverUrl), '/api/auth/me'),
      headers: {'Authorization': 'Bearer $token'},
    );
    return BoxAccountUser.fromJson(_decodeResponse(response));
  }

  /// 我的平台额度。服务端 GET /api/image/quota 按当前 token 判定归属，
  /// 不接受任何客户端传入的 userId。
  Future<PersonalQuota> fetchMyQuota({
    required String serverUrl,
    required String token,
  }) async {
    final response = await _httpClient.get(
      _uri(normalizeServerUrl(serverUrl), '/api/image/quota'),
      headers: {'Authorization': 'Bearer $token'},
    );
    return PersonalQuota.fromJson(_decodeResponse(response));
  }

  Future<List<BoxUsageRecord>> fetchMyUsage({
    required String serverUrl,
    required String token,
    bool? success,
    int limit = 20,
  }) async {
    final query = <String, String>{'limit': limit.toString()};
    if (success != null) query['success'] = success.toString();
    final uri = _uri(
      normalizeServerUrl(serverUrl),
      '/api/image/usage',
    ).replace(queryParameters: query);
    final response = await _httpClient.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    final decoded = _decodeResponse(response);
    final usage = decoded['usage'];
    if (usage is! List) return const [];
    return usage
        .whereType<Map>()
        .map((item) => BoxUsageRecord.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<void> logout({
    required String serverUrl,
    required String token,
  }) async {
    await _httpClient.post(
      _uri(normalizeServerUrl(serverUrl), '/api/auth/logout'),
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  static String normalizeServerUrl(String serverUrl) {
    final normalizedDefault = BoxAccountDefaults.normalizeServerUrl(serverUrl);
    final trimmed = normalizedDefault.trim();
    if (trimmed.isEmpty) {
      throw const BoxAccountException('请先填写服务器地址。');
    }
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      throw const BoxAccountException('服务器地址需要是 http/https URL。');
    }
    if (parsed.scheme != 'http' && parsed.scheme != 'https') {
      throw const BoxAccountException('服务器地址只支持 http 或 https。');
    }
    return trimmed.replaceAll(RegExp(r'/+$'), '');
  }

  static Uri _uri(String serverUrl, String path) =>
      Uri.parse('$serverUrl$path');

  static Map<String, dynamic> _decodeResponse(http.Response response) {
    final text = utf8.decode(response.bodyBytes);
    final preview = _preview(text);
    dynamic decoded;
    try {
      decoded = text.trim().isEmpty ? <String, dynamic>{} : jsonDecode(text);
    } catch (_) {
      decoded = null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final structured = _extractStructuredError(decoded);
      final serverMessage = structured ?? (preview.isEmpty ? '请求失败' : preview);
      throw BoxAccountException(
        _friendlyError(
          response.statusCode,
          serverMessage,
          structured: structured != null,
          headers: response.headers,
        ),
        statusCode: response.statusCode,
        rawPreview: preview,
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw BoxAccountException(
        '服务器返回格式不是 JSON 对象。',
        statusCode: response.statusCode,
        rawPreview: preview,
      );
    }
    return decoded;
  }

  /// 只返回服务端**结构化**给出的错误文案（error.message / message）。
  /// 返回 null 表示服务端没给结构化文案，调用方才退回 body 预览。
  static String? _extractStructuredError(dynamic decoded) {
    if (decoded is Map) {
      final error = decoded['error'];
      if (error is Map && error['message'] != null) {
        return error['message'].toString();
      }
      if (decoded['message'] != null) return decoded['message'].toString();
    }
    return null;
  }

  static String _friendlyError(
    int statusCode,
    String message, {
    required bool structured,
    Map<String, String> headers = const {},
  }) {
    // 429 是登录节流：服务端已经把「请 N 秒后再试」说清楚了，
    // 再拼一句通用的「请求失败。」会前后矛盾。
    if (statusCode == 429) {
      if (structured) return message;
      final retryAfter = headers['retry-after'] ?? headers['Retry-After'];
      final seconds = int.tryParse(retryAfter?.trim() ?? '');
      return seconds != null ? '操作过于频繁，请 $seconds 秒后再试。' : '操作过于频繁，请稍后再试。';
    }
    final hint = switch (statusCode) {
      401 => '账号或密码错误，或登录已失效。',
      403 => '账号不可用或没有权限。',
      404 => '服务器地址不对，未找到登录接口。',
      408 => '服务器响应超时，请稍后重试。',
      >= 500 => '后端服务异常，请检查服务器日志。',
      _ => '请求失败。',
    };
    return '$message\n$hint';
  }

  static String _preview(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.length <= 360 ? compact : '${compact.substring(0, 360)}...';
  }

  void dispose() {
    _httpClient.close();
  }
}
