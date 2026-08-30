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

  /// 检查更新。启动流程与「手动检查更新」都走这里。
  ///
  /// 曾经还有一个静默版 `checkUpdate`（吞异常 + 网络失败回落缓存），在两个入口
  /// 都改用本方法后已无任何调用方，遂删除，避免留着一段不生效的兜底逻辑误导人。
  ///
  /// 现状说明：成功路径会写缓存（[_saveCache]），但**没有**任何读缓存的降级路径——
  /// 网络不通时本方法如实返回 [UpdateCheckStatus.networkError]，不会拿旧清单
  /// 冒充"有新版本"。若将来要做离线提示，应在 bootstrap 层显式读
  /// [loadCachedManifest] 并明确告知用户数据来自缓存，而不是藏在这里。
  ///
  /// 出问题时调用方需要看到真实原因，而不是一句「暂无更新」。
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

}
