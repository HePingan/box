// 文件位置：lib/services/video_api_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../models/video_category.dart';

class VideoApiService {
  // 🔥 终极伪装面具：伪装成一台正常的 Windows 电脑上的 Chrome 浏览器
  static const Map<String, String> _defaultHeaders = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
  };

  // 智能拼接 URL 参数
  static String _withQuery(String baseUrl, List<String> params) {
    if (params.isEmpty) return baseUrl;
    final separator = baseUrl.contains('?') ? '&' : '?';
    return '$baseUrl$separator${params.join('&')}';
  }

  // 极佳的容错泛型列表提取
  static List<dynamic> _extractList(dynamic decoded) {
    if (decoded is List) return decoded;

    if (decoded is Map<String, dynamic>) {
      for (final key in const[
        'list',
        'data',
        'results',
        'sources',
        'items',
        'rows',
      ]) {
        final value = decoded[key];
        if (value is List) return value;
        if (value is Map && value['list'] is List) {
          return value['list'] as List;
        }
      }
    }
    return const[];
  }

  // 1. 获取源配置
  static Future<List<VideoSource>> fetchSources(String configUrl) async {
    if (configUrl.trim().isEmpty) return[];

    try {
      // 🛡️ 注入伪装请求头
      final response = await http.get(Uri.parse(configUrl), headers: _defaultHeaders);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final list = _extractList(decoded);
        return list
            .whereType<Map<String, dynamic>>()
            .map(VideoSource.fromJson)
            .toList();
      }
    } catch (e) {
      debugPrint('加载源配置失败: $e');
    }
    return[];
  }

  // 2. 获取分类列表 (加入容错)
  static Future<List<VideoCategory>> fetchCategories(String baseUrl) async {
    if (baseUrl.trim().isEmpty) return[];
    
    // ac=list 默认附带 class 节点
    final url = _withQuery(baseUrl, ['ac=list']);
    try {
      // 🛡️ 注入伪装请求头
      final response = await http.get(Uri.parse(url), headers: _defaultHeaders);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        // 苹果CMS的分类通常固定在 "class" 字段下
        if (decoded is Map<String, dynamic> && decoded['class'] is List) {
          return (decoded['class'] as List)
              .whereType<Map<String, dynamic>>()
              .map(VideoCategory.fromJson)
              .toList();
        }
      }
    } catch (e) {
      debugPrint('获取分类列表失败: $e');
    }
    return[];
  }

  // 3. 获取视频列表
  static Future<List<VodItem>> fetchVideoList({
    required String baseUrl,
    int page = 1,
    int? typeId,
  }) async {
    final params = <String>['ac=list', 'pg=$page'];
    if (typeId != null) {
      params.add('t=$typeId');
    }
    final url = _withQuery(baseUrl, params);

    try {
      // 🛡️ 注入伪装请求头
      final response = await http.get(Uri.parse(url), headers: _defaultHeaders);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final list = _extractList(decoded);
        return list
            .whereType<Map<String, dynamic>>()
            .map(VodItem.fromJson)
            .toList();
      }
    } catch (e) {
      debugPrint('获取视频列表失败: $e');
    }
    return[];
  }

  // 4. 搜索视频
  static Future<List<VodItem>> searchVideo(
    String baseUrl,
    String keyword,
  ) async {
    final query = keyword.trim();
    if (query.isEmpty) return [];

    final url = _withQuery(baseUrl,[
      'ac=list',
      'wd=${Uri.encodeQueryComponent(query)}',
    ]);

    try {
      // 🛡️ 注入伪装请求头
      final response = await http.get(Uri.parse(url), headers: _defaultHeaders);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final list = _extractList(decoded);
        return list
            .whereType<Map<String, dynamic>>()
            .map(VodItem.fromJson)
            .toList();
      }
    } catch (e) {
      debugPrint('搜索失败: $e');
    }
    return[];
  }

  // 5. 获取详情
  static Future<VodItem?> fetchDetail(String baseUrl, int vodId) async {
    if (baseUrl.trim().isEmpty) return null;

    final url = _withQuery(baseUrl,['ac=detail', 'ids=$vodId']);

    try {
      // 🛡️ 注入伪装请求头
      final response = await http.get(Uri.parse(url), headers: _defaultHeaders);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);

        if (decoded is Map<String, dynamic>) {
          final list = _extractList(decoded).whereType<Map<String, dynamic>>().toList();
          if (list.isNotEmpty) {
            return VodItem.fromJson(list.first);
          }

          if (decoded.containsKey('vod_id') ||
              decoded.containsKey('vodId') ||
              decoded.containsKey('vod_name') ||
              decoded.containsKey('vodName')) {
            return VodItem.fromJson(decoded);
          }
        }

        if (decoded is List &&
            decoded.isNotEmpty &&
            decoded.first is Map<String, dynamic>) {
          return VodItem.fromJson(decoded.first as Map<String, dynamic>);
        }
      }
    } catch (e) {
      debugPrint('获取详情失败: $e');
    }
    return null;
  }
}