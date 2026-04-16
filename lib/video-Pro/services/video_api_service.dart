import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../utils/app_logger.dart';
import '../models/video_category.dart';
import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../utils/isolate_parser.dart';

class VideoApiService {
  static const Duration _defaultTimeout = Duration(seconds: 25);

  static const Map<String, String> _defaultHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36',
    'Accept':
        'application/json, text/html, application/xhtml+xml, application/xml;q=0.9, image/avif, image/webp, image/apng, */*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
  };

  static void _log(String message) {
    AppLogger.instance.log(message, tag: 'HTTP');
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
    final mergedHeaders = <String, String>{..._defaultHeaders};
    if (headers != null) mergedHeaders.addAll(headers);

    _log('GET $url');

    try {
      final response = await http
          .get(Uri.parse(url), headers: mergedHeaders)
          .timeout(timeout);

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

  static dynamic _decodeJsonSafely(String body) {
    final cleaned = body.replaceFirst(RegExp(r'^\uFEFF'), '').trim();

    try {
      return jsonDecode(cleaned);
    } catch (_) {
      // 有些接口可能在 JSON 前后带少量文本，尝试截取
    }

    final objStart = cleaned.indexOf('{');
    final objEnd = cleaned.lastIndexOf('}');
    if (objStart >= 0 && objEnd > objStart) {
      final slice = cleaned.substring(objStart, objEnd + 1);
      try {
        return jsonDecode(slice);
      } catch (_) {}
    }

    final arrStart = cleaned.indexOf('[');
    final arrEnd = cleaned.lastIndexOf(']');
    if (arrStart >= 0 && arrEnd > arrStart) {
      final slice = cleaned.substring(arrStart, arrEnd + 1);
      try {
        return jsonDecode(slice);
      } catch (_) {}
    }

    throw Exception('Invalid JSON');
  }

  static Future<dynamic> _getJson(String url) async {
    final body = await _getRawString(url);
    return _decodeJsonSafely(body);
  }

  static String _asString(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    final s = value.toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return fallback;
    return s;
  }

  static bool _asBool(dynamic value, [bool fallback = true]) {
    if (value == null) return fallback;
    if (value is bool) return value;

    final s = value.toString().trim().toLowerCase();
    if (s.isEmpty || s == 'null') return fallback;

    if (['1', 'true', 'yes', 'y', 'on'].contains(s)) return true;
    if (['0', 'false', 'no', 'n', 'off'].contains(s)) return false;

    return fallback;
  }

  static List<Map<String, dynamic>> _toMapList(dynamic value) {
    if (value is List) {
      return value
          .map(IsolateParser.asMap)
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
    }

    if (value is Map) {
      return value.values
          .map(IsolateParser.asMap)
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
    }

    return const <Map<String, dynamic>>[];
  }

  /// 兼容多种 JSON 结构：
  /// 1. 直接是数组
  /// 2. { sources: [...] }
  /// 3. { list: [...] }
  /// 4. { data: [...] }
  /// 5. { items: [...] }
  /// 6. { rows: [...] }
  /// 7. 你现在这种 { api_site: { xxx: {...}, ... } }
  static List<Map<String, dynamic>> _extractSourceItems(dynamic decoded) {
    if (decoded is List) {
      return decoded
          .map(IsolateParser.asMap)
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
    }

    if (decoded is! Map) {
      return const <Map<String, dynamic>>[];
    }

    final map = Map<String, dynamic>.from(decoded);

    for (final key in const [
      'sources',
      'list',
      'data',
      'items',
      'rows',
      'result',
      'class',
    ]) {
      final value = map[key];
      final list = _toMapList(value);
      if (list.isNotEmpty) return list;
    }

    final apiSite = map['api_site'] ?? map['apiSite'];
    if (apiSite is Map) {
      return apiSite.entries.map((entry) {
        final item = IsolateParser.asMap(entry.value) ?? <String, dynamic>{};

        return <String, dynamic>{
          ...item,
          'id': _asString(
            item['id'] ?? item['sourceId'] ?? item['sid'] ?? entry.key,
            entry.key.toString(),
          ),
          'name': _asString(
            item['name'] ?? item['title'] ?? entry.key,
            entry.key.toString(),
          ),
          // 图一里的 api 对应真正接口
          'url': _asString(
            item['url'] ??
                item['api'] ??
                item['apiUrl'] ??
                item['api_url'] ??
                '',
          ),
          // detail 作为备用地址
          'detailUrl': _asString(
            item['detailUrl'] ??
                item['detail'] ??
                item['detail_url'] ??
                item['detailurl'] ??
                '',
          ),
          'isEnabled': _asBool(
            item['isEnabled'] ?? item['enabled'] ?? item['status'],
            true,
          ),
        };
      }).where((e) => _asString(e['url']).isNotEmpty).toList(growable: false);
    }

    return const <Map<String, dynamic>>[];
  }

  static Map<String, dynamic>? _normalizeSourceItem(Map<String, dynamic> raw) {
    final url = _asString(
      raw['url'] ?? raw['api'] ?? raw['apiUrl'] ?? raw['api_url'],
    );
    if (url.isEmpty) return null;

    final detailUrl = _asString(
      raw['detailUrl'] ??
          raw['detail'] ??
          raw['detail_url'] ??
          raw['detailurl'],
      url,
    );

    return <String, dynamic>{
      ...raw,
      'id': _asString(
        raw['id'] ?? raw['sourceId'] ?? raw['sid'] ?? raw['key'] ?? url,
        url,
      ),
      'name': _asString(
        raw['name'] ?? raw['sourceName'] ?? raw['title'],
        '未知源',
      ),
      'url': url,
      'detailUrl': detailUrl,
      'isEnabled': _asBool(
        raw['isEnabled'] ?? raw['enabled'] ?? raw['status'],
        true,
      ),
    };
  }

  static Future<List<VodItem>> _fetchVodListByParams(
    String baseUrl,
    Map<String, String> params,
  ) async {
    final rawBody = await _getRawString(_withQuery(baseUrl, params));
    return await IsolateParser.parseVodList(rawBody);
  }

  static Future<List<VodItem>> _fetchVodListByCandidates(
    String baseUrl,
    List<Map<String, String>> candidates,
  ) async {
    for (final params in candidates) {
      try {
        final items = await _fetchVodListByParams(baseUrl, params);
        if (items.isNotEmpty) return items;
      } catch (e, st) {
        _log('vod list candidate failed: $e');
        _log(st.toString());
      }
    }
    return [];
  }

  // ======================
  // 业务接口调用
  // ======================

  /// 读取“JSON集合.txt”
  /// 兼容你现在的 api_site 结构，也兼容老的数组结构
  static Future<List<VideoSource>> fetchSources(String configUrl) async {
    final url = configUrl.trim();
    if (url.isEmpty) return [];

    try {
      final decoded = await _getJson(url);
      final rawItems = _extractSourceItems(decoded);

      return rawItems
          .map(_normalizeSourceItem)
          .whereType<Map<String, dynamic>>()
          .map(VideoSource.fromJson)
          .toList(growable: false);
    } catch (e, st) {
      _log('fetchSources failed: $e');
      _log(st.toString());
      return [];
    }
  }

  /// 分类：优先 ac=class，部分源可能不返回分类，返回空数组属正常
  static Future<List<VideoCategory>> fetchCategories(String baseUrl) async {
    final url = baseUrl.trim();
    if (url.isEmpty) return [];

    try {
      final candidates = <Map<String, String>>[
        {'ac': 'class'},
        {'ac': 'list'},
      ];

      for (final params in candidates) {
        try {
          final rawBody = await _getRawString(_withQuery(url, params));
          final items = await IsolateParser.parseCategoryList(rawBody);
          if (items.isNotEmpty) return items;
        } catch (e, st) {
          _log('fetchCategories candidate failed: $e');
          _log(st.toString());
        }
      }

      return [];
    } catch (e, st) {
      _log('fetchCategories failed: $e');
      _log(st.toString());
      return [];
    }
  }

  /// 拉视频列表
  /// typeId = null 表示“全部”
  static Future<List<VodItem>> fetchVideos(
    String baseUrl,
    int? typeId,
    int page,
  ) async {
    final url = baseUrl.trim();
    if (url.isEmpty) return [];

    final candidates = <Map<String, String>>[];

    if (typeId != null && typeId > 0) {
      candidates.addAll([
        {'ac': 'list', 't': '$typeId', 'pg': '$page'},
        {'ac': 'videolist', 't': '$typeId', 'pg': '$page'},
        {'ac': 'list', 'pg': '$page'},
        {'ac': 'videolist', 'pg': '$page'},
      ]);
    } else {
      candidates.addAll([
        {'ac': 'list', 'pg': '$page'},
        {'ac': 'videolist', 'pg': '$page'},
      ]);
    }

    try {
      return await _fetchVodListByCandidates(url, candidates);
    } catch (e, st) {
      _log('fetchVideos failed: $e');
      _log(st.toString());
      return [];
    }
  }

  /// 兼容旧调用
  static Future<List<VodItem>> fetchVideoList({
    required String baseUrl,
    int page = 1,
    int? typeId,
  }) {
    return fetchVideos(baseUrl, typeId, page);
  }

  /// 搜索视频
  static Future<List<VodItem>> searchVideo(
    String baseUrl,
    String keyword,
  ) async {
    final url = baseUrl.trim();
    final query = keyword.trim();
    if (url.isEmpty || query.isEmpty) return [];

    final candidates = <Map<String, String>>[
      {'ac': 'list', 'wd': query},
      {'ac': 'videolist', 'wd': query},
      {'ac': 'search', 'wd': query},
      {'wd': query},
    ];

    for (final params in candidates) {
      try {
        final rawBody = await _getRawString(_withQuery(url, params));
        final items = await IsolateParser.parseVodList(rawBody);
        if (items.isNotEmpty) return items;
      } catch (_) {
        continue;
      }
    }

    return [];
  }

  static Future<VodItem?> fetchDetail(String baseUrl, int vodId) async {
    final url = baseUrl.trim();
    if (url.isEmpty || vodId <= 0) return null;

    final candidates = <Map<String, String>>[
      {'ac': 'detail', 'ids': '$vodId'},
      {'ac': 'detail', 'id': '$vodId'},
      {'ids': '$vodId'},
    ];

    for (final params in candidates) {
      try {
        final decoded = await _getJson(_withQuery(url, params));

        final list = _toMapList(decoded);
        if (list.isNotEmpty) {
          return VodItem.fromJson(list.first);
        }

        final map = IsolateParser.asMap(decoded);
        if (map != null &&
            (map.containsKey('vod_id') ||
                map.containsKey('vodId') ||
                map.containsKey('vod_name'))) {
          return VodItem.fromJson(map);
        }
      } catch (e, st) {
        _log('fetchDetail candidate failed: $e');
        _log(st.toString());
      }
    }

    return null;
  }
}