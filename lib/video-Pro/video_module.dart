import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models/video_source.dart';
import '../utils/app_logger.dart';

/// 单个视频源的可见性记录
class SourceVisibilityRecord {
  final String key;
  final bool manualHidden;
  final bool autoHidden;
  final int failCount;
  final DateTime? lastCheckedAt;
  final String? lastReason;
  final bool? lastPlayable;

  const SourceVisibilityRecord({
    required this.key,
    this.manualHidden = false,
    this.autoHidden = false,
    this.failCount = 0,
    this.lastCheckedAt,
    this.lastReason,
    this.lastPlayable,
  });

  bool get isHidden => manualHidden || autoHidden;
  bool get isVisible => !isHidden;

  SourceVisibilityRecord copyWith({
    bool? manualHidden,
    bool? autoHidden,
    int? failCount,
    DateTime? lastCheckedAt,
    String? lastReason,
    bool? lastPlayable,
  }) {
    return SourceVisibilityRecord(
      key: key,
      manualHidden: manualHidden ?? this.manualHidden,
      autoHidden: autoHidden ?? this.autoHidden,
      failCount: failCount ?? this.failCount,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      lastReason: lastReason ?? this.lastReason,
      lastPlayable: lastPlayable ?? this.lastPlayable,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'manualHidden': manualHidden,
        'autoHidden': autoHidden,
        'failCount': failCount,
        'lastCheckedAt': lastCheckedAt?.toIso8601String(),
        'lastReason': lastReason,
        'lastPlayable': lastPlayable,
      };

  factory SourceVisibilityRecord.fromJson(Map<String, dynamic> json) {
    final rawFailCount = json['failCount'];
    final failCount = rawFailCount is num
        ? rawFailCount.toInt()
        : int.tryParse(rawFailCount?.toString() ?? '') ?? 0;

    return SourceVisibilityRecord(
      key: json['key']?.toString() ?? '',
      manualHidden: json['manualHidden'] == true,
      autoHidden: json['autoHidden'] == true,
      failCount: failCount,
      lastCheckedAt: json['lastCheckedAt'] == null
          ? null
          : DateTime.tryParse(json['lastCheckedAt'].toString()),
      lastReason: json['lastReason']?.toString(),
      lastPlayable: json['lastPlayable'] is bool ? json['lastPlayable'] as bool : null,
    );
  }
}

/// 视频模块配置中心 + 源可见性管理
class VideoModule {
  static VideoCatalogConfig? _config;
  static String? _resolvedCatalogUrl;

  /// =============== 源可见性本地缓存 ===============
  static const String _visibilityPrefsKey = 'video_pro_source_visibility_v1';
  static bool _visibilityLoaded = false;
  static Future<void>? _visibilityLoadFuture;
  static Map<String, SourceVisibilityRecord> _visibilityCache = {};

  static bool get isConfigured => _config != null;

  static String get catalogName => _config?.catalogName ?? '影视';

  static List<String> get catalogUrls =>
      List.unmodifiable(_config?.catalogUrls ?? const []);

  static String? get preferredCatalogUrl =>
      catalogUrls.isNotEmpty ? catalogUrls.first : null;

  /// 源唯一 key：优先 id，没有就用 url，再没有就用 detailUrl / name
  static String sourceKeyOf(VideoSource source) {
    final dynamic rawId = source.id;
    final idText = rawId == null ? '' : rawId.toString().trim();
    if (idText.isNotEmpty && idText != 'null') return idText;

    final url = source.url.trim();
    if (url.isNotEmpty) return url;

    final detailUrl = source.detailUrl.trim();
    if (detailUrl.isNotEmpty) return detailUrl;

    final name = source.name.trim();
    if (name.isNotEmpty) return name;

    return 'unknown_source';
  }

  static Future<void> ensureVisibilityLoaded() async {
    if (_visibilityLoaded) return;

    _visibilityLoadFuture ??= _loadVisibilityFromPrefs();
    await _visibilityLoadFuture;
  }

  static Future<void> _loadVisibilityFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_visibilityPrefsKey);

      if (raw == null || raw.trim().isEmpty) {
        _visibilityCache = {};
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final next = <String, SourceVisibilityRecord>{};
        for (final entry in decoded.entries) {
          final key = entry.key.toString();
          final value = entry.value;
          if (value is Map) {
            next[key] = SourceVisibilityRecord.fromJson(
              Map<String, dynamic>.from(value),
            );
          }
        }
        _visibilityCache = next;
      } else {
        _visibilityCache = {};
      }
    } catch (e, st) {
      AppLogger.instance.log(
        'load visibility cache failed: $e',
        tag: 'VISIBILITY',
      );
      AppLogger.instance.log(st.toString(), tag: 'VISIBILITY');
      _visibilityCache = {};
    } finally {
      _visibilityLoaded = true;
      _visibilityLoadFuture = null;
    }
  }

  static Future<void> _persistVisibilityCache() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = _visibilityCache.map(
      (key, value) => MapEntry(key, value.toJson()),
    );
    await prefs.setString(_visibilityPrefsKey, jsonEncode(payload));
  }

  static SourceVisibilityRecord getVisibilityRecord(VideoSource source) {
    final key = sourceKeyOf(source);
    return _visibilityCache[key] ??
        SourceVisibilityRecord(
          key: key,
        );
  }

  static bool isSourceManuallyHidden(VideoSource source) {
    return getVisibilityRecord(source).manualHidden;
  }

  static bool isSourceAutoHidden(VideoSource source) {
    return getVisibilityRecord(source).autoHidden;
  }

  static bool isSourceHidden(VideoSource source) {
    return getVisibilityRecord(source).isHidden;
  }

  static bool isSourceVisible(VideoSource source) {
    return !isSourceHidden(source);
  }

  static List<VideoSource> visibleSourcesOf(
    List<VideoSource> sources, {
    bool includeHidden = false,
  }) {
    if (includeHidden) {
      return sources
          .where((s) => s.isEnabled == true && s.url.trim().isNotEmpty)
          .toList(growable: false);
    }

    return sources
        .where((s) =>
            s.isEnabled == true &&
            s.url.trim().isNotEmpty &&
            isSourceVisible(s))
        .toList(growable: false);
  }

  static Future<void> setSourceManualHidden(
    VideoSource source,
    bool hidden, {
    String? reason,
  }) async {
    await ensureVisibilityLoaded();

    final key = sourceKeyOf(source);
    final current = _visibilityCache[key] ??
        SourceVisibilityRecord(
          key: key,
        );

    _visibilityCache[key] = current.copyWith(
      manualHidden: hidden,
      lastReason: reason ?? current.lastReason,
      lastCheckedAt: DateTime.now(),
    );

    await _persistVisibilityCache();

    AppLogger.instance.log(
      'manualHidden=$hidden key=$key name=${source.name}',
      tag: 'VISIBILITY',
    );
  }

  static Future<void> setSourceAutoHidden(
    VideoSource source,
    bool hidden, {
    String? reason,
    int? failCount,
    bool? lastPlayable,
  }) async {
    await ensureVisibilityLoaded();

    final key = sourceKeyOf(source);
    final current = _visibilityCache[key] ??
        SourceVisibilityRecord(
          key: key,
        );

    _visibilityCache[key] = current.copyWith(
      autoHidden: hidden,
      failCount: failCount ?? current.failCount,
      lastReason: reason ?? current.lastReason,
      lastPlayable: lastPlayable ?? current.lastPlayable,
      lastCheckedAt: DateTime.now(),
    );

    await _persistVisibilityCache();

    AppLogger.instance.log(
      'autoHidden=$hidden key=$key name=${source.name}',
      tag: 'VISIBILITY',
    );
  }

  static Future<void> markSourceSuccess(VideoSource source) async {
    await ensureVisibilityLoaded();

    final key = sourceKeyOf(source);
    final current = _visibilityCache[key] ??
        SourceVisibilityRecord(
          key: key,
        );

    _visibilityCache[key] = current.copyWith(
      autoHidden: false,
      failCount: 0,
      lastPlayable: true,
      lastReason: 'ok',
      lastCheckedAt: DateTime.now(),
    );

    await _persistVisibilityCache();

    AppLogger.instance.log(
      'markSourceSuccess key=$key name=${source.name}',
      tag: 'VISIBILITY',
    );
  }

  static Future<void> markSourceFailure(
    VideoSource source, {
    required String reason,
    required bool autoHide,
  }) async {
    await ensureVisibilityLoaded();

    final key = sourceKeyOf(source);
    final current = _visibilityCache[key] ??
        SourceVisibilityRecord(
          key: key,
        );

    _visibilityCache[key] = current.copyWith(
      autoHidden: autoHide,
      failCount: current.failCount + 1,
      lastPlayable: false,
      lastReason: reason,
      lastCheckedAt: DateTime.now(),
    );

    await _persistVisibilityCache();

    AppLogger.instance.log(
      'markSourceFailure autoHide=$autoHide key=$key name=${source.name} reason=$reason',
      tag: 'VISIBILITY',
    );
  }

  /// 依次尝试 catalogUrls，返回第一个可用 JSON 地址
  /// 如果全部失败，返回 null，让页面使用自己的 fallback
  static Future<String?> resolveWorkingCatalogUrl({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    const tag = 'CATALOG';

    if (_resolvedCatalogUrl != null && _resolvedCatalogUrl!.trim().isNotEmpty) {
      AppLogger.instance.log(
        'resolveWorkingCatalogUrl cache hit url=$_resolvedCatalogUrl',
        tag: tag,
      );
      return _resolvedCatalogUrl;
    }

    if (catalogUrls.isEmpty) {
      AppLogger.instance.log(
        'resolveWorkingCatalogUrl skipped: catalogUrls is empty',
        tag: tag,
      );
      return null;
    }

    AppLogger.instance.log(
      'resolveWorkingCatalogUrl start candidateCount=${catalogUrls.length}',
      tag: tag,
    );

    for (final candidate in catalogUrls) {
      final url = candidate.trim();
      if (url.isEmpty) continue;

      AppLogger.instance.log('probe catalog url=$url', tag: tag);

      try {
        final response = await http.get(Uri.parse(url)).timeout(timeout);
        final body = utf8.decode(
          response.bodyBytes,
          allowMalformed: true,
        ).trim();

        AppLogger.instance.log(
          'probe status=${response.statusCode} '
          'contentType=${response.headers['content-type']} '
          'bodyLength=${body.length}',
          tag: tag,
        );

        if (body.isNotEmpty) {
          final preview = body.length > 500 ? body.substring(0, 500) : body;
          AppLogger.instance.log(
            'probe preview:\n$preview',
            tag: tag,
          );
        }

        if (response.statusCode != 200) {
          AppLogger.instance.log(
            'probe failed: non-200 status=${response.statusCode} url=$url',
            tag: tag,
          );
          continue;
        }

        if (body.isEmpty) {
          AppLogger.instance.log(
            'probe failed: empty body url=$url',
            tag: tag,
          );
          continue;
        }

        try {
          final decoded = jsonDecode(body);

          // 只要能被成功解析成 JSON，就认为这个地址可用
          // 这里兼容 JSON object / array 两种最常见格式
          if (decoded is Map || decoded is List) {
            _resolvedCatalogUrl = url;
            AppLogger.instance.log('probe success url=$url', tag: tag);
            return url;
          } else {
            AppLogger.instance.log(
              'probe failed: decoded json but unexpected type=${decoded.runtimeType} url=$url',
              tag: tag,
            );
          }
        } catch (e) {
          AppLogger.instance.log(
            'probe failed: invalid json url=$url error=$e',
            tag: tag,
          );
        }
      } catch (e, st) {
        AppLogger.instance.log(
          'probe exception url=$url error=$e',
          tag: tag,
        );
        AppLogger.instance.log(st.toString(), tag: tag);
      }
    }

    AppLogger.instance.log(
      'resolveWorkingCatalogUrl exhausted all candidates, return null',
      tag: tag,
    );
    return null;
  }

  static void resetForTest() {
    _config = null;
    _resolvedCatalogUrl = null;
    _visibilityCache = {};
    _visibilityLoaded = false;
    _visibilityLoadFuture = null;
  }

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

    AppLogger.instance.log(
      'configureLicensedCatalogSource catalogName=${_config!.catalogName} '
      'candidateCount=${_config!.catalogUrls.length}',
      tag: 'CATALOG',
    );
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