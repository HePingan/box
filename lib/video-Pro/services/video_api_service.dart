import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/video_category.dart';
import '../models/video_source.dart';
import '../models/vod_item.dart';

class VideoApiService {
  static const Duration _defaultTimeout = Duration(seconds: 10);

  static const Map<String, String> _defaultHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
  };

  static String _withQuery(String baseUrl, Map<String, String> params) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) return trimmed;
    if (params.isEmpty) return trimmed;

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) {
      final separator = trimmed.contains('?') ? '&' : '?';
      return '$trimmed$separator${params.entries.map((e) => '${e.key}=${e.value}').join('&')}';
    }

    final merged = Map<String, String>.from(uri.queryParameters);
    merged.addAll(params);
    return uri.replace(queryParameters: merged).toString();
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static List<dynamic> _extractList(dynamic decoded) {
    if (decoded is List) return decoded;

    if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);

      for (final key in const [
        'list',
        'data',
        'results',
        'sources',
        'items',
        'rows',
        'class',
      ]) {
        final value = map[key];
        if (value is List) return value;
        if (value is Map) {
          final nested = _asMap(value);
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

  static Future<dynamic> _getJson(
    String url, {
    Duration timeout = _defaultTimeout,
  }) async {
    final response = await http
        .get(Uri.parse(url), headers: _defaultHeaders)
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final body = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    if (body.isEmpty) {
      throw Exception('Empty body');
    }

    return jsonDecode(body);
  }

  static Future<List<VideoSource>> fetchSources(String configUrl) async {
    final url = configUrl.trim();
    if (url.isEmpty) return [];

    try {
      final decoded = await _getJson(url);
      final list = _extractList(decoded);

      return list
          .map(_asMap)
          .whereType<Map<String, dynamic>>()
          .map(VideoSource.fromJson)
          .toList(growable: false);
    } catch (e) {
      debugPrint('加载源配置失败: $e');
      return [];
    }
  }

  static Future<List<VideoCategory>> fetchCategories(String baseUrl) async {
    final url = baseUrl.trim();
    if (url.isEmpty) return [];

    final requestUrl = _withQuery(url, {
      'ac': 'list',
    });

    try {
      final decoded = await _getJson(requestUrl);

      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        final classList = map['class'];
        if (classList is List) {
          return classList
              .map(_asMap)
              .whereType<Map<String, dynamic>>()
              .map(VideoCategory.fromJson)
              .toList(growable: false);
        }
      }

      final list = _extractList(decoded);
      return list
          .map(_asMap)
          .whereType<Map<String, dynamic>>()
          .map(VideoCategory.fromJson)
          .toList(growable: false);
    } catch (e) {
      debugPrint('获取分类列表失败: $e');
      return [];
    }
  }

  static Future<List<VodItem>> fetchVideoList({
    required String baseUrl,
    int page = 1,
    int? typeId,
  }) async {
    final url = baseUrl.trim();
    if (url.isEmpty) return [];

    final params = <String, String>{
      'ac': 'list',
      'pg': '$page',
    };
    if (typeId != null) {
      params['t'] = '$typeId';
    }

    final requestUrl = _withQuery(url, params);

    try {
      final decoded = await _getJson(requestUrl);
      final list = _extractList(decoded);

      return list
          .map(_asMap)
          .whereType<Map<String, dynamic>>()
          .map(VodItem.fromJson)
          .toList(growable: false);
    } catch (e) {
      debugPrint('获取视频列表失败: $e');
      return [];
    }
  }

  static Future<List<VodItem>> searchVideo(
    String baseUrl,
    String keyword,
  ) async {
    final url = baseUrl.trim();
    final query = keyword.trim();
    if (url.isEmpty || query.isEmpty) return [];

    final requestUrl = _withQuery(url, {
      'ac': 'list',
      'wd': query,
    });

    try {
      final decoded = await _getJson(requestUrl);
      final list = _extractList(decoded);

      return list
          .map(_asMap)
          .whereType<Map<String, dynamic>>()
          .map(VodItem.fromJson)
          .toList(growable: false);
    } catch (e) {
      debugPrint('搜索失败: $e');
      return [];
    }
  }

  static Future<VodItem?> fetchDetail(String baseUrl, int vodId) async {
    final url = baseUrl.trim();
    if (url.isEmpty || vodId <= 0) return null;

    final requestUrl = _withQuery(url, {
      'ac': 'detail',
      'ids': '$vodId',
    });

    try {
      final decoded = await _getJson(requestUrl);

      final list = _extractList(decoded)
          .map(_asMap)
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);

      if (list.isNotEmpty) {
        return VodItem.fromJson(list.first);
      }

      final map = _asMap(decoded);
      if (map != null) {
        final hasVodFields = map.containsKey('vod_id') ||
            map.containsKey('vodId') ||
            map.containsKey('vod_name') ||
            map.containsKey('vodName');

        if (hasVodFields) {
          return VodItem.fromJson(map);
        }
      }

      if (decoded is List &&
          decoded.isNotEmpty &&
          decoded.first is Map) {
        return VodItem.fromJson(
          Map<String, dynamic>.from(decoded.first as Map),
        );
      }
    } catch (e) {
      debugPrint('获取详情失败: $e');
    }

    return null;
  }
}