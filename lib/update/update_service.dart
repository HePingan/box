import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_models.dart';

class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const String _cacheKey = 'update_manifest_cache_v1';
  static const String _cacheTimeKey = 'update_manifest_cache_time_v1';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 8),
    ),
  );

  Future<UpdateManifest?> checkUpdate({
    required String checkUrl,
    required String appId,
    required String platform,
    required String channel,
    required int versionCode,
    required String packageName,
    String? deviceId,
    String? userId,
  }) async {
    try {
      final res = await _dio.get(
        checkUrl,
        queryParameters: {
          'app_id': appId,
          'platform': platform,
          'channel': channel,
          'version_code': versionCode,
          'package_name': packageName,
          if (deviceId != null) 'device_id': deviceId,
          if (userId != null) 'user_id': userId,
          'ts': DateTime.now().millisecondsSinceEpoch,
        },
      );

      final map = _extractDataMap(res.data);
      final manifest = UpdateManifest.fromJson(map);

      // 服务端返回的如果是“旧版本/同版本”，依然可以缓存，
      // 但真正是否弹窗，由上层 bootstrap 兜底判断。
      await _saveCache(manifest);
      return manifest;
    } catch (_) {
      // 网络失败时使用缓存兜底，但必须保证缓存确实比当前版本新，
      // 否则宁可当作没有更新，也不要拿旧缓存去误弹窗。
      final cached = await loadCachedManifest();
      if (cached == null) return null;

      if (cached.latestVersionCode <= versionCode) {
        return null;
      }

      return cached;
    }
  }

  Map<String, dynamic> _extractDataMap(dynamic data) {
    if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) {
        return _normalizeResponse(decoded);
      }
      throw Exception('接口返回不是 Map');
    }

    if (data is Map) {
      return _normalizeResponse(Map<String, dynamic>.from(data));
    }

    throw Exception('不支持的返回类型：${data.runtimeType}');
  }

  Map<String, dynamic> _normalizeResponse(Map<String, dynamic> raw) {
    // 兼容 {code:0, message:"ok", data:{...}}
    if (raw['data'] is Map<String, dynamic>) {
      return Map<String, dynamic>.from(raw['data'] as Map);
    }
    return raw;
  }

  Future<void> _saveCache(UpdateManifest manifest) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(manifest.toJson()));
    await prefs.setInt(_cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<UpdateManifest?> loadCachedManifest() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_cacheKey);
    if (jsonStr == null || jsonStr.isEmpty) return null;

    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        return UpdateManifest.fromJson(decoded);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<int?> getCacheTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_cacheTimeKey);
  }
}