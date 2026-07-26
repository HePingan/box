import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/video_category.dart';
import '../models/vod_item.dart';

/// 异步数据解析器
///
/// 大 payload 丢到后台 Isolate（`compute`）避免卡 UI 线程；小 payload 直接在
/// 主线程解析——spawn 一个 isolate 有固定开销（序列化 + 线程创建约数毫秒），
/// 对几 KB 的小数据反而更慢，聚合搜索里 N 个源就是 N 次无谓的 isolate 创建。
class IsolateParser {
  /// 低于此字节数在主线程解析，高于则丢后台 isolate。
  /// 32KB 约对应几十条 VodItem，超过才值得 isolate 的固定开销。
  static const int _isolateThresholdBytes = 32 * 1024;

  /// 开启后台线程，解析视频列表数据
  static Future<List<VodItem>> parseVodList(
    String jsonString, {
    String? baseUrl,
  }) async {
    if (jsonString.trim().isEmpty) return <VodItem>[];

    final payload = <String, String?>{
      'jsonString': jsonString,
      'baseUrl': baseUrl,
    };

    // 小数据主线程直接解析，省掉 isolate 固定开销。
    if (jsonString.length < _isolateThresholdBytes) {
      return _parseVodListTask(payload);
    }
    return compute(_parseVodListTask, payload);
  }

  /// 开启后台线程，解析分类列表数据
  static Future<List<VideoCategory>> parseCategoryList(
    String jsonString,
  ) async {
    if (jsonString.trim().isEmpty) return <VideoCategory>[];

    // 分类数据通常很小（几十条以内），几乎总是走主线程。
    if (jsonString.length < _isolateThresholdBytes) {
      return _parseCategoryListTask(jsonString);
    }
    return compute(_parseCategoryListTask, jsonString);
  }

  // ===========================================================================
  // 下方是纯净的后台线程任务方法（不能调用跨线程对象）
  // ===========================================================================

  static List<VodItem> _parseVodListTask(Map<String, String?> payload) {
    try {
      final jsonString = payload['jsonString'] ?? '';
      final baseUrl = payload['baseUrl'];

      final decoded = jsonDecode(jsonString);
      final list = extractList(decoded);

      return list
          .map(asMap)
          .whereType<Map<String, dynamic>>()
          .map((e) => _normalizeVodItem(e, baseUrl: baseUrl))
          .map((e) => VodItem.fromJson(e, baseUrl: baseUrl))
          .where((item) => item.vodName.trim().isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      debugPrint('Isolate 视频解析失败: $e');
      return <VodItem>[];
    }
  }

  static List<VideoCategory> _parseCategoryListTask(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString);

      final list = extractList(decoded);
      return list
          .map(asMap)
          .whereType<Map<String, dynamic>>()
          .map(_normalizeCategoryItem)
          .map((e) => VideoCategory.fromJson(e))
          .where((item) => item.typeName.trim().isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      debugPrint('Isolate 分类解析失败: $e');
      return <VideoCategory>[];
    }
  }

  // ===========================================================================
  // 公共健壮性提取方法
  // ===========================================================================

  static Map<String, dynamic>? asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static List<dynamic> extractList(dynamic decoded) {
    if (decoded is List) return decoded;

    if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);

      // 常见影视 CMS 的数组键名
      const keys = [
        'list',
        'data',
        'results',
        'result',
        'sources',
        'items',
        'rows',
        'class',
      ];

      for (final key in keys) {
        final value = map[key];

        if (value is List) return value;

        if (value is Map) {
          final nested = asMap(value);
          if (nested != null) {
            for (final nestedKey in const [
              'list',
              'data',
              'results',
              'items',
              'rows',
              'class',
            ]) {
              final nestedValue = nested[nestedKey];
              if (nestedValue is List) return nestedValue;
            }
          }
        }
      }
    }

    return const [];
  }

  // ===========================================================================
  // 归一化处理
  // ===========================================================================

  static String _asString(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    final s = value.toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return fallback;
    return s;
  }

  static int _asInt(dynamic value, [int fallback = 0]) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString().trim()) ?? fallback;
  }

  static Map<String, dynamic> _normalizeVodItem(
    Map<String, dynamic> raw, {
    String? baseUrl,
  }) {
    final vodId = _asInt(raw['vod_id'] ?? raw['vodId'] ?? raw['id']);
    final vodName = _asString(
      raw['vod_name'] ?? raw['vodName'] ?? raw['name'] ?? raw['title'],
    );
    final typeId = _asInt(raw['type_id'] ?? raw['typeId']);
    final typeName = _asString(raw['type_name'] ?? raw['typeName']);

    final vodPicRaw = _asString(
      raw['vod_pic'] ??
          raw['vodPic'] ??
          raw['pic'] ??
          raw['poster'] ??
          raw['cover'] ??
          raw['image'] ??
          raw['img'] ??
          raw['thumb'] ??
          raw['posterUrl'] ??
          raw['coverUrl'] ??
          raw['imageUrl'],
    );

    final vodPic = _resolveMediaUrl(vodPicRaw, baseUrl);

    final vodRemarks = _asString(
      raw['vod_remarks'] ??
          raw['vodRemarks'] ??
          raw['remarks'] ??
          raw['remark'],
    );
    final vodPlayFrom = _asString(
      raw['vod_play_from'] ?? raw['vodPlayFrom'] ?? raw['play_from'],
    );
    final vodPlayUrl = _asString(
      raw['vod_play_url'] ?? raw['vodPlayUrl'] ?? raw['play_url'],
    );
    final vodTime = _asString(raw['vod_time'] ?? raw['vodTime']);
    final vodContent = _asString(raw['vod_content'] ?? raw['vodContent']);

    // 只写规范下划线键（VodItem.fromJson 按别名列表回退时优先命中这些），
    // 保留 ...raw 透传 year/area/lang/director/actor 等 normalize 未显式处理的
    // 字段。以前给同一个值塞 10 个驼峰/别名副本，列表几百条时内存翻数倍且全是
    // fromJson 用不到的冗余键，这里一并去掉。
    return <String, dynamic>{
      ...raw,
      'vod_id': vodId,
      'type_id': typeId,
      'type_name': typeName,
      'vod_name': vodName,
      'vod_pic': vodPic,
      'vod_remarks': vodRemarks,
      'vod_play_from': vodPlayFrom,
      'vod_play_url': vodPlayUrl,
      'vod_time': vodTime,
      'vod_content': vodContent,
    };
  }

  static Map<String, dynamic> _normalizeCategoryItem(Map<String, dynamic> raw) {
    final typeId = _asInt(raw['type_id'] ?? raw['typeId'] ?? raw['id']);
    final typeName = _asString(
      raw['type_name'] ?? raw['typeName'] ?? raw['name'],
    );
    final pid = _asInt(raw['type_pid'] ?? raw['typePid'] ?? raw['pid']);

    return <String, dynamic>{
      ...raw,
      'type_id': typeId,
      'typeId': typeId,
      'type_name': typeName,
      'typeName': typeName,
      'type_pid': pid,
    };
  }

  static String? _resolveMediaUrl(String? rawUrl, String? baseUrl) {
    final value = rawUrl?.trim() ?? '';
    if (value.isEmpty || value.toLowerCase() == 'null') return null;

    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }

    if (value.startsWith('//')) {
      return 'https:$value';
    }

    final origin = _originBase(baseUrl);
    if (origin == null) return value;

    final path = value.startsWith('/') ? value.substring(1) : value;
    return origin.resolve(path).toString();
  }

  static Uri? _originBase(String? baseUrl) {
    final text = baseUrl?.trim() ?? '';
    if (text.isEmpty) return null;

    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;

    final origin = uri.hasPort
        ? '${uri.scheme}://${uri.host}:${uri.port}/'
        : '${uri.scheme}://${uri.host}/';

    return Uri.tryParse(origin);
  }
}
