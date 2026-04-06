import 'dart:convert';

import 'package:http/http.dart' as http;

/// 视频模块配置中心
class VideoModule {
  static VideoCatalogConfig? _config;
  static String? _resolvedCatalogUrl;

  static bool get isConfigured => _config != null;

  static String get catalogName => _config?.catalogName ?? '影视';

  static List<String> get catalogUrls =>
      List.unmodifiable(_config?.catalogUrls ?? const []);

  static String? get preferredCatalogUrl =>
      catalogUrls.isNotEmpty ? catalogUrls.first : null;

  static void configureLicensedCatalogSource({
    required String catalogName,
    required List<String> catalogUrls,
  }) {
    final normalizedUrls = catalogUrls
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    _config = VideoCatalogConfig(
      catalogName: catalogName.trim().isEmpty ? '影视' : catalogName.trim(),
      catalogUrls: normalizedUrls,
    );
    _resolvedCatalogUrl = null;
  }

  /// 依次尝试 catalogUrls，返回第一个可用 JSON 地址
  /// 如果全部失败，返回 null，让页面使用自己的 fallback
  static Future<String?> resolveWorkingCatalogUrl({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (_resolvedCatalogUrl != null) {
      return _resolvedCatalogUrl;
    }

    for (final candidate in catalogUrls) {
      try {
        final response = await http.get(Uri.parse(candidate)).timeout(timeout);
        if (response.statusCode != 200) {
          continue;
        }

        final body = response.body.trim();
        if (body.isEmpty) {
          continue;
        }

        // 只要能被成功解析成 JSON，就认为这个地址可用
        jsonDecode(body);

        _resolvedCatalogUrl = candidate;
        return candidate;
      } catch (_) {
        // 继续尝试下一个候选地址
      }
    }

    return null;
  }

  static void resetForTest() {
    _config = null;
    _resolvedCatalogUrl = null;
  }
}

class VideoCatalogConfig {
  final String catalogName;
  final List<String> catalogUrls;

  const VideoCatalogConfig({
    required this.catalogName,
    required this.catalogUrls,
  });
}