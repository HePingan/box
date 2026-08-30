import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_models.dart';
import 'update_response_parser.dart';
import 'update_security.dart';
import 'update_check_outcome.dart';

class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const String _cacheKey = 'update_manifest_cache_v1';
  static const String _cacheTimeKey = 'update_manifest_cache_time_v1';

  /// Validate that the update check URL is a well-formed HTTPS URL.
  /// Returns null if the URL is invalid or not HTTPS, preventing
  /// potential SSRF / insecure redirect attacks.
  static String? _validateUpdateUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    if (uri.scheme != 'https') return null;
    return trimmed;
  }

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
    UpdateManifestSecurityConfig security =
        const UpdateManifestSecurityConfig(),
  }) async {
    final validatedUrl = _validateUpdateUrl(checkUrl);
    if (validatedUrl == null) {
      return await loadCachedManifest();
    }
    try {
      final res = await _dio.get(
        validatedUrl,
        queryParameters: {
          'app_id': appId,
          'platform': platform,
          'channel': channel,
          'version_code': versionCode,
          'package_name': packageName,
          if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
          if (userId != null && userId.isNotEmpty) 'user_id': userId,
          'ts': DateTime.now().millisecondsSinceEpoch,
        },
      );

      final map = extractUpdateDataMap(res.data);
      final manifest = UpdateManifest.fromJson(map);
      validateUpdateManifestSecurity(
        manifest: manifest,
        rawManifestJson: map,
        security: security,
      );

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

  /// 带诊断信息的检查，供「手动检查更新」使用（A4）。
  ///
  /// 与 [checkUpdate] 的区别：不吞异常、不做缓存兜底，如实告诉调用方失败在哪一步。
  /// 启动流程仍然走 [checkUpdate]（要缓存兜底、要静默放行），这里只服务于用户
  /// 主动点击的场景——出问题时需要看到真实原因，而不是一句「暂无更新」。
  Future<UpdateCheckOutcome> checkUpdateDiagnostic({
    required String checkUrl,
    required String appId,
    required String platform,
    required String channel,
    required int versionCode,
    required String packageName,
    String? deviceId,
    String? userId,
    UpdateManifestSecurityConfig security =
        const UpdateManifestSecurityConfig(),
  }) async {
    final validatedUrl = _validateUpdateUrl(checkUrl);
    if (validatedUrl == null) {
      return UpdateCheckOutcome.failure(
        UpdateCheckStatus.notConfigured,
        detail: checkUrl.trim().isEmpty ? '地址为空' : '必须是 https 地址',
      );
    }

    Response<dynamic> res;
    try {
      res = await _dio.get(
        validatedUrl,
        queryParameters: {
          'app_id': appId,
          'platform': platform,
          'channel': channel,
          'version_code': versionCode,
          'package_name': packageName,
          if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
          if (userId != null && userId.isNotEmpty) 'user_id': userId,
          'ts': DateTime.now().millisecondsSinceEpoch,
        },
      );
    } on DioException catch (e) {
      return UpdateCheckOutcome.failure(
        UpdateCheckStatus.networkError,
        detail: e.message ?? e.type.name,
      );
    } catch (e) {
      return UpdateCheckOutcome.failure(
        UpdateCheckStatus.networkError,
        detail: e.toString(),
      );
    }

    Map<String, dynamic> map;
    UpdateManifest manifest;
    try {
      map = extractUpdateDataMap(res.data);
      manifest = UpdateManifest.fromJson(map);
    } catch (e) {
      return UpdateCheckOutcome.failure(
        UpdateCheckStatus.badResponse,
        detail: e.toString(),
      );
    }

    try {
      validateUpdateManifestSecurity(
        manifest: manifest,
        rawManifestJson: map,
        security: security,
      );
    } catch (e) {
      return UpdateCheckOutcome.failure(
        UpdateCheckStatus.signatureRejected,
        detail: e.toString().replaceFirst('Exception: ', ''),
      );
    }

    await _saveCache(manifest);
    return UpdateCheckOutcome.fromManifest(
      manifest: manifest,
      currentVersionCode: versionCode,
    );
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
