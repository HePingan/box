import 'dart:convert';

import 'package:flutter/foundation.dart';
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

  /// 是否强制把 VOD 源走代理
  /// 你现在这个场景建议保持 true
  static bool enableVodProxy = true;

  /// 是否把封面也通过代理加载
  /// 如果你只是拿数据，可以先 false
  static bool enableVodMediaProxy = false;

  /// 你的可访问代理前缀
  static const String _vodProxyPrefix =
      'https://proxy.shuabu.eu.org/?url=';

  static void _log(String message) {
    if (kDebugMode) {
      AppLogger.instance.log(message, tag: 'VIDEO_API');
    }
  }

  static String _preview(String text, {int max = 1000}) {
    final value = text.trim();
    if (value.length <= max) return value;
    return '${value.substring(0, max)}...<truncated>';
  }

  static String _paramsText(Map<String, String> params) {
    if (params.isEmpty) return '{}';
    return params.entries.map((e) => '${e.key}=${e.value}').join('&');
  }

  static String _sampleVodItems(List<VodItem> items, {int limit = 3}) {
    if (items.isEmpty) return '[]';
    return items.take(limit).map((e) {
      return jsonEncode({
        'vod_id': e.vodId,
        'vod_name': e.vodName,
        'vod_pic': e.vodPic,
        'type_id': e.typeId,
        'type_name': e.typeName,
      });
    }).join(' | ');
  }

  static String _sampleMapItems(List<Map<String, dynamic>> items,
      {int limit = 2}) {
    if (items.isEmpty) return '[]';
    return items
        .take(limit)
        .map((e) => _preview(jsonEncode(e), max: 500))
        .join(' | ');
  }

  static bool _isProxyUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    return uri != null && uri.host == 'proxy.shuabu.eu.org';
  }

  static String _wrapWithProxy(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return trimmed;
    if (trimmed.startsWith(_vodProxyPrefix)) return trimmed;
    if (_isProxyUrl(trimmed)) return trimmed;
    return '$_vodProxyPrefix${Uri.encodeComponent(trimmed)}';
  }

  /// 先补成标准 VOD 接口，再按需包代理
  static String _buildVodBaseUrl(String baseUrl) {
    final normalized = _normalizeProvideVodEndpoint(baseUrl.trim());
    if (normalized.isEmpty) return normalized;
    if (!enableVodProxy) return normalized;
    return _wrapWithProxy(normalized);
  }

  /// 智能拼接 query：
  /// - 普通 URL：直接追加参数
  /// - 带 ?url=xxx 的嵌套代理/转发 URL：把参数追加到真正的内层目标地址
  static String _withQuery(String baseUrl, Map<String, String> params) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty || params.isEmpty) return trimmed;

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) {
      final separator = trimmed.contains('?') ? '&' : '?';
      return '$trimmed$separator${params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
    }

    final query = Map<String, String>.from(uri.queryParameters);
    final nestedTarget = query['url'];

    if (nestedTarget != null && nestedTarget.trim().isNotEmpty) {
      query['url'] = _withQuery(nestedTarget, params);
      return uri.replace(queryParameters: query).toString();
    }

    query.addAll(params);
    return uri.replace(queryParameters: query).toString();
  }

  /// 递归展开嵌套 url，用于推断真实目标站点
  static String _unwrapTargetUrl(String url, {int maxDepth = 3}) {
    var current = url.trim();
    if (current.isEmpty) return current;

    for (var i = 0; i < maxDepth; i++) {
      final uri = Uri.tryParse(current);
      if (uri == null || !uri.hasScheme) break;

      final nested = uri.queryParameters['url'];
      if (nested == null || nested.trim().isEmpty) break;

      current = nested.trim();
    }

    return current;
  }

  static Map<String, String> _headersForUrl(String url) {
    final headers = <String, String>{..._defaultHeaders};

    // 走代理时，不要强行带原站 Origin / Referer
    if (_isProxyUrl(url)) {
      return headers;
    }

    final target = _unwrapTargetUrl(url);
    final uri = Uri.tryParse(target);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      final origin = uri.hasPort
          ? '${uri.scheme}://${uri.host}:${uri.port}'
          : '${uri.scheme}://${uri.host}';
      headers['Origin'] = origin;
      headers['Referer'] = '$origin/';
    }

    return headers;
  }

  /// 把裸域名自动补成标准 VOD 接口：
  /// https://example.com  -> https://example.com/api.php/provide/vod
  static String _normalizeProvideVodEndpoint(String baseUrl) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) return trimmed;

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return trimmed;

    // 已经是标准接口就不动
    if (uri.path.contains('/api.php/provide/vod')) {
      return trimmed;
    }

    // 只对“纯根域名”自动补接口，避免破坏代理类 URL
    if ((uri.path.isEmpty || uri.path == '/') && uri.queryParameters.isEmpty) {
      return uri.replace(path: '/api.php/provide/vod').toString();
    }

    return trimmed;
  }

  static Future<String> _getRawString(
    String url, {
    Duration timeout = _defaultTimeout,
    Map<String, String>? headers,
  }) async {
    final mergedHeaders = <String, String>{
      ..._headersForUrl(url),
      if (headers != null) ...headers,
    };

    _log('[GET] url=$url');

    try {
      final response = await http
          .get(Uri.parse(url), headers: mergedHeaders)
          .timeout(timeout);

      final body = utf8.decode(response.bodyBytes, allowMalformed: true).trim();

      _log(
        '[GET] status=${response.statusCode} '
        'contentType=${response.headers['content-type'] ?? '-'} '
        'bytes=${response.bodyBytes.length} '
        'bodyLen=${body.length}',
      );

      if (body.isNotEmpty) {
        _log('[GET] preview=${_preview(body)}');
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }
      if (body.isEmpty) throw Exception('Empty body');

      return body;
    } catch (e) {
      _log('[GET] failed url=$url error=$e');
      rethrow;
    }
  }

  static dynamic _decodeJsonSafely(String body) {
    final cleaned = body.replaceFirst(RegExp(r'^\uFEFF'), '').trim();

    try {
      return jsonDecode(cleaned);
    } catch (_) {
      // 有些接口前后可能带少量文本，继续尝试截取 JSON 片段
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

  static bool _looksLikeVodItems(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return false;

    for (final item in items.take(3)) {
      if (item.containsKey('vod_id') ||
          item.containsKey('vodId') ||
          item.containsKey('vod_name') ||
          item.containsKey('vodName') ||
          item.containsKey('vod_play_from') ||
          item.containsKey('vodPlayFrom') ||
          item.containsKey('vod_play_url') ||
          item.containsKey('vodPlayUrl')) {
        return true;
      }
    }

    return false;
  }

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
          'url': _asString(
            item['url'] ??
                item['api'] ??
                item['apiUrl'] ??
                item['api_url'] ??
                '',
          ),
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

  /// 分类优先只取 class / classes / categories / type 系列，
  /// 避免把“视频列表”误解析成“分类列表”
  static List<Map<String, dynamic>> _extractCategoryItemsStrict(
    dynamic decoded,
  ) {
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
      'class',
      'classes',
      'categories',
      'category',
      'types',
    ]) {
      final value = map[key];
      final list = _toMapList(value);
      if (list.isNotEmpty) return list;
    }

    final data = map['data'];
    if (data is Map) {
      final nested = Map<String, dynamic>.from(data);
      for (final key in const [
        'class',
        'classes',
        'categories',
        'category',
        'types',
      ]) {
        final value = nested[key];
        final list = _toMapList(value);
        if (list.isNotEmpty) return list;
      }
    }

    return const <Map<String, dynamic>>[];
  }

  /// 更宽松的分类提取：在“明确非视频列表”的情况下，允许 list / items / rows 兜底
  static List<Map<String, dynamic>> _extractCategoryItemsBroad(
    dynamic decoded,
  ) {
    final strict = _extractCategoryItemsStrict(decoded);
    if (strict.isNotEmpty) return strict;

    if (decoded is! Map) return const <Map<String, dynamic>>[];

    final map = Map<String, dynamic>.from(decoded);

    for (final key in const [
      'list',
      'data',
      'items',
      'rows',
      'result',
      'sources',
    ]) {
      final value = map[key];
      final list = _toMapList(value);
      if (list.isNotEmpty) return list;

      if (value is Map) {
        final nested = Map<String, dynamic>.from(value);
        for (final nestedKey in const [
          'list',
          'data',
          'items',
          'rows',
          'result',
          'class',
          'classes',
          'categories',
          'category',
          'types',
        ]) {
          final nestedValue = nested[nestedKey];
          final nestedList = _toMapList(nestedValue);
          if (nestedList.isNotEmpty) return nestedList;
        }
      }
    }

    return const <Map<String, dynamic>>[];
  }

  static Map<String, dynamic> _normalizeCategoryItem(Map<String, dynamic> raw) {
    final typeId = int.tryParse(
          _asString(raw['type_id'] ?? raw['typeId'] ?? raw['id']),
        ) ??
        0;
    final typeName = _asString(
      raw['type_name'] ?? raw['typeName'] ?? raw['name'] ?? raw['title'],
    );

    return <String, dynamic>{
      ...raw,
      'type_id': typeId,
      'typeId': typeId,
      'type_name': typeName,
      'typeName': typeName,
      'id': typeId == 0 ? _asString(raw['id'] ?? raw['type'] ?? '') : typeId,
      'name': typeName,
      'title': typeName,
    };
  }

  /// 取“原站”的 origin，而不是代理域名
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

  /// 用于封面 / 海报 / 图片
  /// 说明：
  /// - 代理请求时，图片相对路径仍然应当按原站补全
  /// - 如果 enableVodMediaProxy = true，可再把图片包一层代理
  static String? _resolveMediaUrl(String? rawUrl, String? baseUrl) {
    final value = rawUrl?.trim() ?? '';
    if (value.isEmpty || value.toLowerCase() == 'null') return null;

    // 已经是绝对地址
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return enableVodMediaProxy ? _wrapWithProxy(value) : value;
    }

    // 协议相对地址
    if (value.startsWith('//')) {
      final absolute = 'https:$value';
      return enableVodMediaProxy ? _wrapWithProxy(absolute) : absolute;
    }

    final origin = _originBase(_unwrapTargetUrl(baseUrl ?? ''));
    if (origin == null) return value;

    final path = value.startsWith('/') ? value.substring(1) : value;
    final resolved = origin.resolve(path).toString();

    if (!enableVodMediaProxy) return resolved;
    return _wrapWithProxy(resolved);
  }

  static VodItem _patchVodItemMedia(VodItem item, String? baseUrl) {
    final resolved = _resolveMediaUrl(item.vodPic, baseUrl);
    if (resolved == null || resolved == item.vodPic) return item;
    return item.copyWith(vodPic: resolved);
  }

  static List<VodItem> _patchVodItemsMedia(
    List<VodItem> items,
    String? baseUrl,
  ) {
    if (items.isEmpty) return items;
    return items.map((e) => _patchVodItemMedia(e, baseUrl)).toList(growable: false);
  }

  static Future<List<VodItem>> _fetchVodListByParams(
    String baseUrl,
    Map<String, String> params,
  ) async {
    final apiBase = _buildVodBaseUrl(baseUrl);
    final requestUrl = _withQuery(apiBase, params);

    _log(
      '[fetchVodList] request apiBase=$apiBase '
      'requestUrl=$requestUrl '
      'params=${_paramsText(params)}',
    );

    final rawBody = await _getRawString(requestUrl);
    _log('[fetchVodList] raw preview=${_preview(rawBody)}');

    final items = await IsolateParser.parseVodList(rawBody);

    _log(
      '[fetchVodList] parsed count=${items.length} '
      'sample=${_sampleVodItems(items)}',
    );

    if (items.isNotEmpty) {
      _log(
        '[fetchVodList] firstRawVod=${_preview(jsonEncode(items.first.toJson()), max: 900)}',
      );
    }

    final patched = _patchVodItemsMedia(items, apiBase);

    _log(
      '[fetchVodList] patched count=${patched.length} '
      'sample=${_sampleVodItems(patched)}',
    );

    return patched;
  }

  static Future<List<VodItem>> _fetchVodListByCandidates(
    String baseUrl,
    List<Map<String, String>> candidates,
  ) async {
    for (final params in candidates) {
      try {
        final items = await _fetchVodListByParams(baseUrl, params);
        if (items.isNotEmpty) {
          _log(
            '[fetchVodListByCandidates] success '
            'params=${_paramsText(params)} '
            'count=${items.length}',
          );
          return items;
        }

        _log(
          '[fetchVodListByCandidates] empty '
          'params=${_paramsText(params)}',
        );
      } catch (e, st) {
        _log(
          '[fetchVodListByCandidates] failed '
          'params=${_paramsText(params)} error=$e',
        );
        _log(st.toString());
      }
    }

    _log('[fetchVodListByCandidates] all empty');
    return [];
  }

  // ======================
  // XML 兜底解析
  // ======================

  static String _unescapeXml(String input) {
    return input
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .trim();
  }

  static String? _extractXmlTagValue(String body, String tag) {
    final match = RegExp(
      '<$tag\\b[^>]*>([\\s\\S]*?)</$tag>',
      caseSensitive: false,
    ).firstMatch(body);

    if (match == null) return null;

    var value = match.group(1) ?? '';
    value = value.trim();

    if (value.startsWith('<![CDATA[') && value.endsWith(']]>')) {
      value = value.substring(9, value.length - 3);
    }

    return _unescapeXml(value);
  }

  static Map<String, dynamic>? _parseVodXmlDetail(String body) {
    final text = body.replaceFirst(RegExp(r'^\uFEFF'), '').trim();
    if (text.isEmpty || !text.startsWith('<')) return null;

    final candidates = <String>[];

    final videoMatch = RegExp(
      r'<video[^>]*>([\s\S]*?)</video>',
      caseSensitive: false,
    ).firstMatch(text);
    if (videoMatch != null) candidates.add(videoMatch.group(1) ?? '');

    final itemMatch = RegExp(
      r'<item[^>]*>([\s\S]*?)</item>',
      caseSensitive: false,
    ).firstMatch(text);
    if (itemMatch != null) candidates.add(itemMatch.group(1) ?? '');

    candidates.add(text);

    const fields = [
      'vod_id',
      'type_id',
      'type_name',
      'vod_name',
      'vod_pic',
      'vod_remarks',
      'vod_year',
      'vod_content',
      'vod_actor',
      'vod_director',
      'vod_play_from',
      'vod_play_url',
      'vod_lang',
      'vod_area',
      'vod_time',
      'vod_score',
    ];

    for (final candidate in candidates) {
      final map = <String, dynamic>{};

      for (final field in fields) {
        final value = _extractXmlTagValue(candidate, field);
        if (value != null && value.isNotEmpty) {
          map[field] = value;
        }
      }

      if (map.isNotEmpty) return map;
    }

    return null;
  }

  // ======================
  // 业务接口调用
  // ======================

  /// 读取“JSON集合.txt”
  /// 兼容你现在的 api_site 结构，也兼容老的数组结构
  static Future<List<VideoSource>> fetchSources(String configUrl) async {
    final url = configUrl.trim();
    if (url.isEmpty) {
      _log('[fetchSources] skip empty configUrl');
      return [];
    }

    _log('[fetchSources] start configUrl=$url');

    try {
      final decoded = await _getJson(url);
      _log('[fetchSources] decodedType=${decoded.runtimeType}');

      final rawItems = _extractSourceItems(decoded);
      _log(
        '[fetchSources] rawItems=${rawItems.length} '
        'sampleKeys=${rawItems.isNotEmpty ? rawItems.first.keys.take(12).join(" | ") : "-"}',
      );
      if (rawItems.isNotEmpty) {
        _log('[fetchSources] firstRaw=${_preview(jsonEncode(rawItems.first), max: 800)}');
      }

      final sources = rawItems
          .map(_normalizeSourceItem)
          .whereType<Map<String, dynamic>>()
          .map(VideoSource.fromJson)
          .toList(growable: false);

      _log(
        '[fetchSources] parsedSources=${sources.length} '
        'sample=${sources.take(5).map((e) => e.name).join(" | ")}',
      );

      return sources;
    } catch (e, st) {
      _log('[fetchSources] failed: $e');
      _log(st.toString());
      return [];
    }
  }

  /// 分类：
  /// 1. 优先尝试根接口
  /// 2. 再尝试 ac=class
  /// 3. 再尝试 ac=list
  ///
  /// 注意：根接口只接受“明确是分类”的结构，避免把视频列表误判成分类
  static Future<List<VideoCategory>> fetchCategories(String baseUrl) async {
    final url = _buildVodBaseUrl(baseUrl);
    if (url.isEmpty) {
      _log('[fetchCategories] skip empty baseUrl');
      return [];
    }

    _log(
      '[fetchCategories] start baseUrl=$baseUrl '
      'builtUrl=$url '
      'enableVodProxy=$enableVodProxy',
    );

    try {
      final candidates = <Map<String, String>>[
        const <String, String>{}, // 先试根接口
        {'ac': 'class'},
        {'ac': 'list'},
      ];

      for (final params in candidates) {
        try {
          final requestUrl = params.isEmpty ? url : _withQuery(url, params);
          _log(
            '[fetchCategories] try requestUrl=$requestUrl '
            'params=${_paramsText(params)}',
          );

          final rawBody = await _getRawString(requestUrl);

          dynamic decoded;
          try {
            decoded = _decodeJsonSafely(rawBody);
            _log('[fetchCategories] decodedType=${decoded.runtimeType}');
          } catch (_) {
            decoded = null;
            _log('[fetchCategories] decode json failed, will try fallback parser');
          }

          final rawItems = decoded == null
              ? const <Map<String, dynamic>>[]
              : (params.isEmpty
                  ? _extractCategoryItemsStrict(decoded)
                  : _extractCategoryItemsBroad(decoded));

          _log(
            '[fetchCategories] rawItems=${rawItems.length} '
            'sample=${_sampleMapItems(rawItems)}',
          );

          if (rawItems.isEmpty) {
            final fallback = await IsolateParser.parseCategoryList(rawBody);
            _log(
              '[fetchCategories] isolateFallback count=${fallback.length} '
              'sample=${fallback.take(5).map((e) => "${e.typeId}:${e.typeName}").join(" | ")}',
            );
            if (fallback.isNotEmpty) return fallback;
            continue;
          }

          if (_looksLikeVodItems(rawItems)) {
            _log('[fetchCategories] skip because looks like vod items');
            continue;
          }

          final items = rawItems
              .map(_normalizeCategoryItem)
              .map(VideoCategory.fromJson)
              .where((item) => item.typeName.trim().isNotEmpty)
              .toList(growable: false);

          _log(
            '[fetchCategories] parsed count=${items.length} '
            'sample=${items.take(5).map((e) => "${e.typeId}:${e.typeName}").join(" | ")}',
          );

          if (items.isNotEmpty) return items;
        } catch (e, st) {
          _log('[fetchCategories] candidate failed params=${_paramsText(params)} error=$e');
          _log(st.toString());
        }
      }

      _log('[fetchCategories] fallback empty');
      return [];
    } catch (e, st) {
      _log('[fetchCategories] failed: $e');
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
    final url = _buildVodBaseUrl(baseUrl);
    if (url.isEmpty) {
      _log('[fetchVideos] skip empty baseUrl');
      return [];
    }

    _log(
      '[fetchVideos] start baseUrl=$baseUrl '
      'builtUrl=$url '
      'typeId=${typeId?.toString() ?? "all"} '
      'page=$page '
      'enableVodProxy=$enableVodProxy '
      'enableVodMediaProxy=$enableVodMediaProxy',
    );

    final candidates = <Map<String, String>>[];

    // 只有“全部 + 第 1 页”时，先试根接口
    if (typeId == null && page == 1) {
      candidates.add(const <String, String>{});
    }

    if (typeId != null && typeId > 0) {
      candidates.addAll([
        {'ac': 'list', 't': '$typeId', 'pg': '$page'},
        {'ac': 'videolist', 't': '$typeId', 'pg': '$page'},
        {'t': '$typeId', 'pg': '$page'},
        {'ac': 'list', 't': '$typeId', 'page': '$page'},
        {'t': '$typeId', 'page': '$page'},
      ]);
    } else {
      candidates.addAll([
        {'ac': 'list', 'pg': '$page'},
        {'ac': 'videolist', 'pg': '$page'},
        {'pg': '$page'},
        {'page': '$page'},
      ]);
    }

    _log(
      '[fetchVideos] candidates=${candidates.map(_paramsText).join(" || ")}',
    );

    try {
      return await _fetchVodListByCandidates(url, candidates);
    } catch (e, st) {
      _log('[fetchVideos] failed: $e');
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
    final url = _buildVodBaseUrl(baseUrl);
    final query = keyword.trim();
    if (url.isEmpty || query.isEmpty) {
      _log('[searchVideo] skip empty url or keyword');
      return [];
    }

    _log('[searchVideo] start baseUrl=$baseUrl builtUrl=$url keyword=$query');

    final candidates = <Map<String, String>>[
      {'ac': 'list', 'wd': query},
      {'ac': 'videolist', 'wd': query},
      {'ac': 'search', 'wd': query},
      {'wd': query},
    ];

    for (final params in candidates) {
      try {
        final requestUrl = _withQuery(url, params);
        _log(
          '[searchVideo] try requestUrl=$requestUrl '
          'params=${_paramsText(params)}',
        );

        final rawBody = await _getRawString(requestUrl);
        final items = await IsolateParser.parseVodList(rawBody);

        _log(
          '[searchVideo] parsed count=${items.length} '
          'sample=${_sampleVodItems(items)}',
        );

        if (items.isNotEmpty) return _patchVodItemsMedia(items, url);
      } catch (e, st) {
        _log('[searchVideo] candidate failed params=${_paramsText(params)} error=$e');
        _log(st.toString());
      }
    }

    _log('[searchVideo] fallback empty');
    return [];
  }

  /// 获取详情
  static Future<VodItem?> fetchDetail(String baseUrl, int vodId) async {
    final url = _buildVodBaseUrl(baseUrl);
    if (url.isEmpty || vodId <= 0) {
      _log('[fetchDetail] skip empty url or invalid vodId=$vodId');
      return null;
    }

    _log('[fetchDetail] start baseUrl=$baseUrl builtUrl=$url vodId=$vodId');

    final candidates = <Map<String, String>>[
      {'ac': 'detail', 'ids': '$vodId'},
      {'ac': 'detail', 'id': '$vodId'},
      {'ids': '$vodId'},
      {'id': '$vodId'},
    ];

    for (final params in candidates) {
      try {
        final requestUrl = _withQuery(url, params);
        _log(
          '[fetchDetail] try requestUrl=$requestUrl '
          'params=${_paramsText(params)}',
        );

        final rawBody = await _getRawString(requestUrl);
        _log('[fetchDetail] raw preview=${_preview(rawBody)}');

        // 1) 先尝试按列表解析
        try {
          final items = await IsolateParser.parseVodList(rawBody);
          _log(
            '[fetchDetail] parseVodList count=${items.length} '
            'sample=${_sampleVodItems(items)}',
          );
          if (items.isNotEmpty) {
            return _patchVodItemMedia(items.first, url);
          }
        } catch (e) {
          _log('[fetchDetail] parseVodList failed: $e');
        }

        // 2) 再尝试 JSON
        try {
          final decoded = _decodeJsonSafely(rawBody);
          _log('[fetchDetail] decodedType=${decoded.runtimeType}');

          final list = _toMapList(decoded);
          if (list.isNotEmpty) {
            _log(
              '[fetchDetail] decoded list count=${list.length} '
              'sample=${_sampleMapItems(list)}',
            );
            return _patchVodItemMedia(VodItem.fromJson(list.first), url);
          }

          final map = IsolateParser.asMap(decoded);
          if (map != null) {
            _log(
              '[fetchDetail] decoded map keys=${map.keys.take(20).join(" | ")}',
            );

            if (map.containsKey('vod_id') ||
                map.containsKey('vodId') ||
                map.containsKey('vod_name') ||
                map.containsKey('vodName')) {
              return _patchVodItemMedia(VodItem.fromJson(map), url);
            }
          }
        } catch (e) {
          _log('[fetchDetail] json parse failed: $e');
        }

        // 3) 最后尝试 XML
        final xmlMap = _parseVodXmlDetail(rawBody);
        if (xmlMap != null) {
          _log('[fetchDetail] xmlMap keys=${xmlMap.keys.take(20).join(" | ")}');
          return _patchVodItemMedia(VodItem.fromJson(xmlMap), url);
        }

        _log('[fetchDetail] no detail matched for params=${_paramsText(params)}');
      } catch (e, st) {
        _log('[fetchDetail] candidate failed params=${_paramsText(params)} error=$e');
        _log(st.toString());
      }
    }

    _log('[fetchDetail] fallback null');
    return null;
  }
}