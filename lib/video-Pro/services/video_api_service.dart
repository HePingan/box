import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../utils/proxy_utils.dart'; // 具体路径根据你放哪而定
import '../models/video_category.dart';
import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../../utils/app_logger.dart';
import '../utils/isolate_parser.dart'; 

class VideoApiService {
  static const Duration _defaultTimeout = Duration(seconds: 25);

  static const Map<String, String> _defaultHeaders = {
    "User-Agent":
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36",
      "Accept":
        "application/json, text/html, application/xhtml+xml, application/xml;q=0.9, image/avif, image/webp, image/apng, */*;q=0.8",
      "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
  };

  static void _log(String message) {
    AppLogger.instance.log(message, tag: 'HTTP');
  }

  static Map<String, String> _redactHeaders(Map<String, String> headers) {
    final out = <String, String>{};
    headers.forEach((k, v) {
      if (k.toLowerCase() == 'cookie' || k.toLowerCase() == 'authorization') {
        out[k] = '<redacted>';
      } else {
        out[k] = v;
      }
    });
    return out;
  }

  static String _withQuery(String baseUrl, Map<String, String> params) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty || params.isEmpty) return trimmed;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) {
      final separator = trimmed.contains('?') ? '&' : '?';
      return '$trimmed$separator${params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
    }
    final merged = Map<String, String>.from(uri.queryParameters)..addAll(params);
    return uri.replace(queryParameters: merged).toString();
  }
static Future<String> _getRawString(
    String url, {
    Duration timeout = _defaultTimeout,
    Map<String, String>? headers,
  }) async {
    final safeUrl = wrapWithProxy(url);
    final mergedHeaders = <String, String>{..._defaultHeaders};
    if (headers != null) mergedHeaders.addAll(headers);

    _log('GET $safeUrl');
    try {
      // 🌟 恢复纯净的直接请求，不要再做任何 IP 替换了！
      final response = await http.get(Uri.parse(safeUrl), headers: mergedHeaders).timeout(timeout);
      final body = utf8.decode(response.bodyBytes, allowMalformed: true).trim();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }
      if (body.isEmpty) throw Exception('Empty body');

      return body;
    } catch (e) {
      _log('GET failed url=$url error=$e');
      rethrow;
    }
  }
  static Future<dynamic> _getJson(String url) async {
    final body = await _getRawString(url);
    try {
      return jsonDecode(body); 
    } catch (_) {
      throw Exception('Invalid JSON');
    }
  }

  // ====================== 业务接口调用优化 ======================

  static Future<List<VideoSource>> fetchSources(String configUrl) async {
    final url = configUrl.trim();
    if (url.isEmpty) return [];
    try {
      final decoded = await _getJson(url);
      final list = IsolateParser.extractList(decoded); 
      return list.map(IsolateParser.asMap).whereType<Map<String, dynamic>>().map(VideoSource.fromJson).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<VideoCategory>> fetchCategories(String baseUrl) async {
    final url = baseUrl.trim();
    if (url.isEmpty) return [];
    try {
      // 类别只需要名字，用 list 足矣
      final rawBody = await _getRawString(_withQuery(url, {'ac': 'list'}));
      return await IsolateParser.parseCategoryList(rawBody);
    } catch (_) {
      return [];
    }
  }

  // 🏆 补充并修复了这个核心方法：加了 videolist 请求，保证能强制要到海报图！
  static Future<List<VodItem>> fetchVideos(String baseUrl, int? typeId, int page) async {
    final url = baseUrl.trim();
    if (url.isEmpty) return [];

    // 💥 改这里：ac=videolist 才能拉到详情，才会有海报 vod_pic
    final params = <String, String>{'ac': 'videolist', 'pg': '$page'};
    if (typeId != null) params['t'] = '$typeId';

    try {
      final rawBody = await _getRawString(_withQuery(url, params));
      return await IsolateParser.parseVodList(rawBody);
    } catch (_) {
      return [];
    }
  }

  // 兼容老版本的调用方式
  static Future<List<VodItem>> fetchVideoList({required String baseUrl, int page = 1, int? typeId}) {
      return fetchVideos(baseUrl, typeId, page);
  }

  // 🏆 修复了搜索方法：搜索也必须要完整的海报图！
  static Future<List<VodItem>> searchVideo(String baseUrl, String keyword) async {
    final url = baseUrl.trim();
    final query = keyword.trim();
    if (url.isEmpty || query.isEmpty) return [];

    try {
      // 💥 改这里：全网搜索也用 ac=videolist
      final rawBody = await _getRawString(_withQuery(url, {'ac': 'list', 'wd': query}));
      return await IsolateParser.parseVodList(rawBody);
    } catch (_) {
      return [];
    }
  }

  static Future<VodItem?> fetchDetail(String baseUrl, int vodId) async {
    final url = baseUrl.trim();
    if (url.isEmpty || vodId <= 0) return null;

    try {
      final decoded = await _getJson(_withQuery(url, {'ac': 'detail', 'ids': '$vodId'})); 
      final list = IsolateParser.extractList(decoded)
          .map(IsolateParser.asMap)
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);

      if (list.isNotEmpty) return VodItem.fromJson(list.first);

      final map = IsolateParser.asMap(decoded);
      if (map != null && (map.containsKey('vod_id') || map.containsKey('vodId') || map.containsKey('vod_name'))) {
        return VodItem.fromJson(map);
      }
    } catch (_) {}
    return null;
  }
}