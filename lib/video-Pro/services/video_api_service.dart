import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/video_source.dart';
import '../models/vod_item.dart';
import 'package:flutter/foundation.dart';
class VideoApiService {
  static String _withQuery(String baseUrl, List<String> params) {
    if (params.isEmpty) return baseUrl;
    final separator = baseUrl.contains('?') ? '&' : '?';
    return '$baseUrl$separator${params.join('&')}';
  }

  static List<dynamic> _extractList(dynamic decoded) {
    if (decoded is List) return decoded;

    if (decoded is Map<String, dynamic>) {
      for (final key in const [
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

    return const [];
  }

  static Future<List<VideoSource>> fetchSources(String configUrl) async {
    if (configUrl.trim().isEmpty) return [];

    try {
      final response = await http.get(Uri.parse(configUrl));
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
    return [];
  }

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
      final response = await http.get(Uri.parse(url));
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
    return [];
  }

  static Future<List<VodItem>> searchVideo(
    String baseUrl,
    String keyword,
  ) async {
    final query = keyword.trim();
    if (query.isEmpty) return [];

    final url = _withQuery(baseUrl, [
      'ac=list',
      'wd=${Uri.encodeQueryComponent(query)}',
    ]);

    try {
      final response = await http.get(Uri.parse(url));
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
    return [];
  }

  static Future<VodItem?> fetchDetail(String baseUrl, int vodId) async {
    if (baseUrl.trim().isEmpty) return null;

    final url = _withQuery(baseUrl, ['ac=detail', 'ids=$vodId']);

    try {
      final response = await http.get(Uri.parse(url));
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