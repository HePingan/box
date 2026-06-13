import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/admin_models.dart';
import 'account_client.dart';

class BoxAdminClient {
  BoxAdminClient({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Future<List<BoxAdminUserQuota>> fetchUsers({
    required String serverUrl,
    required String token,
  }) async {
    final response = await _httpClient.get(
      _uri(serverUrl, '/admin/image/users'),
      headers: _headers(token),
    );
    final decoded = _decodeResponse(response);
    return _parseUsers(decoded);
  }

  Future<BoxAdminUserQuota> updateQuota({
    required String serverUrl,
    required String token,
    required BoxAdminUserQuota user,
    required int dailyLimit,
    required int remaining,
  }) async {
    final response = await _httpClient.post(
      _uri(
        serverUrl,
        '/admin/image/users/${Uri.encodeComponent(user.id)}/quota',
      ),
      headers: _headers(token, json: true),
      body: jsonEncode({'dailyLimit': dailyLimit, 'remaining': remaining}),
    );
    final quota = _decodeResponse(response);
    return user.copyWith(
      dailyLimit: _asInt(quota['dailyLimit'], dailyLimit),
      remaining: _asInt(quota['remaining'], remaining),
      usedToday: _asInt(quota['usedToday'], user.usedToday),
      totalLimit: _asInt(quota['totalLimit'], user.totalLimit),
      status: quota['status']?.toString() ?? user.status,
    );
  }

  Future<BoxAdminUserQuota> createAccount({
    required String serverUrl,
    required String token,
    required String username,
    required String password,
    required String role,
    required int dailyLimit,
    required int remaining,
  }) async {
    final response = await _httpClient.post(
      _uri(serverUrl, '/admin/accounts'),
      headers: _headers(token, json: true),
      body: jsonEncode({
        'username': username,
        'password': password,
        'role': role,
        'dailyLimit': dailyLimit,
        'remaining': remaining,
      }),
    );
    return _parseUserWithQuota(_decodeResponse(response));
  }

  Future<BoxAdminUserQuota> updateAccount({
    required String serverUrl,
    required String token,
    required BoxAdminUserQuota user,
    String? role,
    String? status,
    String? password,
  }) async {
    final body = <String, dynamic>{};
    if (role != null) body['role'] = role;
    if (status != null) body['status'] = status;
    if (password != null && password.isNotEmpty) body['password'] = password;
    final response = await _httpClient.patch(
      _uri(serverUrl, '/admin/accounts/${Uri.encodeComponent(user.id)}'),
      headers: _headers(token, json: true),
      body: jsonEncode(body),
    );
    final decoded = _decodeResponse(response);
    return user.copyWith(
      username: decoded['username']?.toString() ?? user.username,
      role: decoded['role']?.toString() ?? user.role,
      status: decoded['status']?.toString() ?? user.status,
    );
  }

  static BoxAdminUserQuota _parseUserWithQuota(Map<String, dynamic> decoded) {
    final user = decoded['user'];
    final quota = decoded['quota'];
    if (user is Map) {
      return BoxAdminUserQuota.fromAdminMaps(
        id: user['id']?.toString() ?? '',
        account: Map<String, dynamic>.from(user),
        quota: quota is Map ? Map<String, dynamic>.from(quota) : const {},
      );
    }
    return BoxAdminUserQuota.fromFlatJson(decoded);
  }

  static Uri _uri(String serverUrl, String path) =>
      Uri.parse('${BoxAccountClient.normalizeServerUrl(serverUrl)}$path');

  static Map<String, String> _headers(String token, {bool json = false}) => {
    if (json) 'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  static List<BoxAdminUserQuota> _parseUsers(Map<String, dynamic> decoded) {
    final flatUsers = decoded['users'];
    if (flatUsers is List) {
      return flatUsers
          .whereType<Map>()
          .map(
            (item) =>
                BoxAdminUserQuota.fromFlatJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    }

    final accounts = decoded['accounts'];
    final quotas = decoded['quotas'];
    if (accounts is Map) {
      final result = <BoxAdminUserQuota>[];
      accounts.forEach((key, accountValue) {
        if (accountValue is! Map) return;
        final quotaValue = quotas is Map ? quotas[key] : null;
        result.add(
          BoxAdminUserQuota.fromAdminMaps(
            id: key.toString(),
            account: Map<String, dynamic>.from(accountValue),
            quota: quotaValue is Map
                ? Map<String, dynamic>.from(quotaValue)
                : const {},
          ),
        );
      });
      result.sort((a, b) => a.username.compareTo(b.username));
      return result;
    }

    throw const BoxAdminException('管理接口返回格式不完整。');
  }

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
      final serverMessage = _extractError(decoded, preview);
      throw BoxAdminException(
        _friendlyError(response.statusCode, serverMessage),
        statusCode: response.statusCode,
        rawPreview: preview,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw BoxAdminException(
        '管理接口返回格式不是 JSON 对象。',
        statusCode: response.statusCode,
        rawPreview: preview,
      );
    }
    return decoded;
  }

  static String _extractError(dynamic decoded, String preview) {
    if (decoded is Map) {
      final error = decoded['error'];
      if (error is Map && error['message'] != null) {
        return error['message'].toString();
      }
      if (decoded['message'] != null) return decoded['message'].toString();
    }
    return preview.isEmpty ? '请求失败' : preview;
  }

  static String _friendlyError(int statusCode, String message) {
    final hint = switch (statusCode) {
      401 => '登录已失效，请重新登录。',
      403 => '需要管理员权限。',
      404 => '用户不存在，或服务器地址不正确。',
      408 => '服务器响应超时，请稍后重试。',
      >= 500 => '后端服务异常，请检查服务器日志。',
      _ => '请求失败。',
    };
    return '$message\n$hint';
  }

  static int _asInt(Object? value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static String _preview(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.length <= 360 ? compact : '${compact.substring(0, 360)}...';
  }
}

class BoxAdminException implements Exception {
  const BoxAdminException(this.message, {this.statusCode, this.rawPreview});

  final String message;
  final int? statusCode;
  final String? rawPreview;

  @override
  String toString() => message;
}
