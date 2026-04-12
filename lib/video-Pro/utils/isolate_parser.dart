import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../models/video_category.dart';
import '../models/vod_item.dart';

/// 异步数据解析器（运行在独立的后台线程 Isolate 中）
class IsolateParser {
  
  /// 开启后台线程，解析视频列表数据
  static Future<List<VodItem>> parseVodList(String jsonString) async {
    if (jsonString.trim().isEmpty) return <VodItem>[];
    // compute 会开辟一个新的 Isolate 并在后台执行 _parseVodListTask
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
      final decoded = jsonDecode(jsonString); // 耗时的 JSON 转换放到后台
      final list = extractList(decoded);     // 抓取数组
      return list
          .map(asMap)
          .whereType<Map<String, dynamic>>()
          .map((e) => VodItem.fromJson(e))    // 耗时的对象映射放到后台
          .toList(growable: false);
    } catch (e) {
      debugPrint('Isolate 视频解析失败: $e');
      return <VodItem>[];
    }
  }

  static List<VideoCategory> _parseCategoryListTask(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString);

      // 兼容某些影视源特殊的分类结构
      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        final classList = map['class'];
        if (classList is List) {
          return classList
              .map(asMap)
              .whereType<Map<String, dynamic>>()
              .map((e) => VideoCategory.fromJson(e))
              .toList(growable: false);
        }
      }

      final list = extractList(decoded);
      return list
          .map(asMap)
          .whereType<Map<String, dynamic>>()
          .map((e) => VideoCategory.fromJson(e))
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
      // 兼容所有常见影视 CMS 的数组键名
      const keys = ['list', 'data', 'results', 'sources', 'items', 'rows', 'class'];
      
      for (final key in keys) {
        final value = map[key];
        if (value is List) return value;

        if (value is Map) {
          final nested = asMap(value);
          if (nested != null) {
            for (final nestedKey in const ['list', 'data', 'items', 'rows']) {
              final nestedValue = nested[nestedKey];
              if (nestedValue is List) return nestedValue;
            }
          }
        }
      }
    }
    return const [];
  }
}