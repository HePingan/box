import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/video_category.dart';
import '../models/vod_item.dart';

/// 异步数据解析器（运行在独立的后台线程 Isolate 中）
class IsolateParser {
  /// 开启后台线程，解析视频列表数据
  static Future<List<VodItem>> parseVodList(String jsonString) async {
    if (jsonString.trim().isEmpty) return <VodItem>[];
    return compute(_parseVodListTask, jsonString);
  }

  /// 开启后台线程，解析分类列表数据
  static Future<List<VideoCategory>> parseCategoryList(String jsonString) async {
    if (jsonString.trim().isEmpty) return <VideoCategory>[];
    return compute(_parseCategoryListTask, jsonString);
  }

  // ===========================================================================
  // 下方是纯净的后台线程任务方法（不能调用跨线程对象）
  // ===========================================================================

  static List<VodItem> _parseVodListTask(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString);
      final list = extractList(decoded);

      return list
          .map(asMap)
          .whereType<Map<String, dynamic>>()
          .map(_normalizeVodItem)
          .map((e) => VodItem.fromJson(e))
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

  // --- 公共健壮性提取方法 ---

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

  static bool _asBool(dynamic value, [bool fallback = true]) {
    if (value == null) return fallback;
    if (value is bool) return value;
    final s = value.toString().trim().toLowerCase();
    if (s.isEmpty) return fallback;
    return s == '1' || s == 'true' || s == 'yes' || s == 'on';
  }

  static Map<String, dynamic> _normalizeVodItem(Map<String, dynamic> raw) {
    final vodId = _asInt(raw['vod_id'] ?? raw['vodId'] ?? raw['id']);
    final vodName = _asString(raw['vod_name'] ?? raw['vodName'] ?? raw['name']);
    final typeId = _asInt(raw['type_id'] ?? raw['typeId']);
    final typeName = _asString(raw['type_name'] ?? raw['typeName']);
    final vodPic = _asString(
      raw['vod_pic'] ?? raw['vodPic'] ?? raw['pic'] ?? raw['poster'] ?? raw['cover'],
    );
    final vodRemarks = _asString(
      raw['vod_remarks'] ?? raw['vodRemarks'] ?? raw['remarks'] ?? raw['remark'],
    );
    final vodPlayFrom = _asString(
      raw['vod_play_from'] ?? raw['vodPlayFrom'] ?? raw['play_from'],
    );
    final vodPlayUrl = _asString(
      raw['vod_play_url'] ?? raw['vodPlayUrl'] ?? raw['play_url'],
    );
    final vodTime = _asString(raw['vod_time'] ?? raw['vodTime']);
    final vodContent = _asString(raw['vod_content'] ?? raw['vodContent']);

    // 同时保留驼峰和下划线，兼容不同的 model 实现
    return <String, dynamic>{
      ...raw,
      'vod_id': vodId,
      'vodId': vodId,
      'vod_name': vodName,
      'vodName': vodName,
      'type_id': typeId,
      'typeId': typeId,
      'type_name': typeName,
      'typeName': typeName,
      'vod_pic': vodPic,
      'vodPic': vodPic,
      'vod_remarks': vodRemarks,
      'vodRemarks': vodRemarks,
      'vod_play_from': vodPlayFrom,
      'vodPlayFrom': vodPlayFrom,
      'vod_play_url': vodPlayUrl,
      'vodPlayUrl': vodPlayUrl,
      'vod_time': vodTime,
      'vodTime': vodTime,
      'vod_content': vodContent,
      'vodContent': vodContent,
    };
  }

  static Map<String, dynamic> _normalizeCategoryItem(Map<String, dynamic> raw) {
    final typeId = _asInt(raw['type_id'] ?? raw['typeId'] ?? raw['id']);
    final typeName = _asString(raw['type_name'] ?? raw['typeName'] ?? raw['name']);

    return <String, dynamic>{
      ...raw,
      'type_id': typeId,
      'typeId': typeId,
      'type_name': typeName,
      'typeName': typeName,
    };
  }
}