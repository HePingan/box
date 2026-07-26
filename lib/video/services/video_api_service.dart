import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../utils/app_logger.dart';
import '../config/video_proxy_config.dart';
import '../models/video_category.dart';
import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../utils/isolate_parser.dart';
import 'request_policy.dart';
import 'search_failure_exception.dart';
import 'shared_http_client.dart';
import 'ttl_cache.dart';

class VideoApiService {
  static const Duration _defaultTimeout = Duration(seconds: 25);

  static const Map<String, String> _defaultHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36',
    'Accept':
        'application/json, text/html, application/xhtml+xml, application/xml;q=0.9, image/avif, image/webp, image/apng, */*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
  };

  static VideoProxyConfig vodProxyConfig = const VideoProxyConfig(
    enabled: bool.fromEnvironment(
      'VIDEO_VOD_PROXY_ENABLED',
      defaultValue: true,
    ),
    mediaEnabled: bool.fromEnvironment(
      'VIDEO_VOD_MEDIA_PROXY_ENABLED',
      defaultValue: false,
    ),
    proxyPrefix: String.fromEnvironment(
      'VIDEO_VOD_PROXY_PREFIX',
      defaultValue: kDefaultVideoProxyPrefix,
    ),
  );

  static void configureVodProxy({
    bool? enabled,
    bool? mediaEnabled,
    String? proxyPrefix,
  }) {
    vodProxyConfig = vodProxyConfig.copyWith(
      enabled: enabled,
      mediaEnabled: mediaEnabled,
      proxyPrefix: proxyPrefix,
    );
  }

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
    return items
        .take(limit)
        .map((e) {
          return jsonEncode({
            'vod_id': e.vodId,
            'vod_name': e.vodName,
            'vod_pic': e.vodPic,
            'type_id': e.typeId,
            'type_name': e.typeName,
          });
        })
        .join(' | ');
  }

  static String _sampleMapItems(
    List<Map<String, dynamic>> items, {
    int limit = 2,
  }) {
    if (items.isEmpty) return '[]';
    return items
        .take(limit)
        .map((e) => _preview(jsonEncode(e), max: 500))
        .join(' | ');
  }

  static bool _isProxyUrl(String url) => vodProxyConfig.isProxyUrl(url);

  static String _wrapWithProxy(String url) => vodProxyConfig.wrapWithProxy(url);

  /// 先补成标准 VOD 接口，再按需包代理
  static String _buildVodBaseUrl(String baseUrl) {
    return vodProxyConfig.buildVodBaseUrl(baseUrl);
  }

  /// 智能拼接 query：
  /// - 普通 URL：直接追加参数
  /// - 带 ?url=xxx 的嵌套代理/转发 URL：把参数追加到真正的内层目标地址
  static String _withQuery(String baseUrl, Map<String, String> params) {
    return vodProxyConfig.withQuery(baseUrl, params);
  }

  /// 递归展开嵌套 url，用于推断真实目标站点
  static String _unwrapTargetUrl(String url, {int maxDepth = 3}) {
    return vodProxyConfig.unwrapTargetUrl(url, maxDepth: maxDepth);
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

  static Future<String> _getRawString(
    String url, {
    Duration timeout = _defaultTimeout,
    Map<String, String>? headers,
    VideoGetRequestPolicy policy = const VideoGetRequestPolicy(),
  }) async {
    final mergedHeaders = <String, String>{..._headersForUrl(url), ...?headers};

    _log('[GET] url=$url');

    try {
      final response = await policy.execute(() async {
        final response = await SharedHttpClient.instance
            .get(Uri.parse(url), headers: mergedHeaders)
            .timeout(timeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw VideoHttpException(response.statusCode);
        }
        return response;
      });

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
        throw VideoHttpException(response.statusCode);
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

  /// 目录中有时把真实采集 API 再套进第三方 `?url=` 转发器。
  ///
  /// 那层转发器会单独下线（百度云就是 404），而内层标准 VOD API 仍可用。
  /// 解开后仍会按当前配置走本应用的代理，不会绕过既有网络策略。
  static String _preferDirectVodApiUrl(String rawUrl) {
    final original = rawUrl.trim();
    if (original.isEmpty || vodProxyConfig.isProxyUrl(original)) {
      return original;
    }

    final target = _unwrapTargetUrl(original);
    if (target == original) return original;
    final uri = Uri.tryParse(target);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return original;

    final path = uri.path.toLowerCase();
    if (path.contains('/api.php/provide/vod') ||
        path.contains('/provide/vod') ||
        path.contains('api.php')) {
      _log('[sources] unwrap nested VOD API $original -> $target');
      return target;
    }
    return original;
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

    // Try standard list keys first using shared _toMapList
    for (final key in const [
      'sources',
      'list',
      'data',
      'items',
      'rows',
      'result',
    ]) {
      final list = _toMapList(map[key]);
      if (list.isNotEmpty) return list;
    }

    // 'class' / 'categories' are category-oriented, skip for source items
    // Fall through to apiSite handling

    final apiSite = map['api_site'] ?? map['apiSite'];
    if (apiSite is Map) {
      return apiSite.entries
          .map((entry) {
            final item =
                IsolateParser.asMap(entry.value) ?? <String, dynamic>{};

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
              'url': _preferDirectVodApiUrl(
                _asString(
                  item['url'] ??
                      item['api'] ??
                      item['apiUrl'] ??
                      item['api_url'] ??
                      '',
                ),
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
          })
          .where((e) => _asString(e['url']).isNotEmpty)
          .toList(growable: false);
    }

    return const <Map<String, dynamic>>[];
  }

  static Map<String, dynamic>? _normalizeSourceItem(Map<String, dynamic> raw) {
    final url = _preferDirectVodApiUrl(
      _asString(raw['url'] ?? raw['api'] ?? raw['apiUrl'] ?? raw['api_url']),
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
    final typeId =
        int.tryParse(_asString(raw['type_id'] ?? raw['typeId'] ?? raw['id'])) ??
        0;
    final typeName = _asString(
      raw['type_name'] ?? raw['typeName'] ?? raw['name'] ?? raw['title'],
    );
    final pid =
        int.tryParse(
          _asString(raw['type_pid'] ?? raw['typePid'] ?? raw['pid']),
        ) ??
        0;

    return <String, dynamic>{
      ...raw,
      'type_id': typeId,
      'typeId': typeId,
      'type_name': typeName,
      'typeName': typeName,
      'type_pid': pid,
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
      return vodProxyConfig.mediaEnabled ? _wrapWithProxy(value) : value;
    }

    // 协议相对地址
    if (value.startsWith('//')) {
      final absolute = 'https:$value';
      return vodProxyConfig.mediaEnabled ? _wrapWithProxy(absolute) : absolute;
    }

    final origin = _originBase(_unwrapTargetUrl(baseUrl ?? ''));
    if (origin == null) return value;

    final path = value.startsWith('/') ? value.substring(1) : value;
    final resolved = origin.resolve(path).toString();

    if (!vodProxyConfig.mediaEnabled) return resolved;
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
    return items
        .map((e) => _patchVodItemMedia(e, baseUrl))
        .toList(growable: false);
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

  /// 记住每个源命中过的参数模板签名，避免每次都从头盲试全部候选。
  /// key = baseUrl，value = 命中的模板签名（见 [_paramTemplateSignature]）。
  static final Map<String, String> _winningParamTemplate = <String, String>{};

  /// 把一组请求参数归一成“模板签名”：变量值(t/pg/page)用占位符，
  /// 保留结构性键值(如 ac=list)。用于跨 typeId/page 复用命中格式。
  static String _paramTemplateSignature(Map<String, String> params) {
    if (params.isEmpty) return '<root>';
    const variableKeys = {'t', 'pg', 'page', 'wd', 'ids', 'id'};
    final entries =
        params.entries
            .map(
              (e) => variableKeys.contains(e.key)
                  ? '${e.key}=?'
                  : '${e.key}=${e.value}',
            )
            .toList()
          ..sort();
    return entries.join('&');
  }

  /// 若该源已有命中记录，把匹配的候选提到队首优先尝试。
  static List<Map<String, String>> _prioritizeCandidates(
    String baseUrl,
    List<Map<String, String>> candidates,
  ) {
    final winner = _winningParamTemplate[baseUrl];
    if (winner == null) return candidates;

    final matched = <Map<String, String>>[];
    final rest = <Map<String, String>>[];
    for (final params in candidates) {
      if (_paramTemplateSignature(params) == winner) {
        matched.add(params);
      } else {
        rest.add(params);
      }
    }

    if (matched.isEmpty) return candidates;

    _log(
      '[fetchVodListByCandidates] prioritize cached template=$winner '
      'for baseUrl=$baseUrl',
    );
    return [...matched, ...rest];
  }

  static Future<List<VodItem>> _fetchVodListByCandidates(
    String baseUrl,
    List<Map<String, String>> candidates,
  ) async {
    final ordered = _prioritizeCandidates(baseUrl, candidates);

    for (final params in ordered) {
      try {
        final items = await _fetchVodListByParams(baseUrl, params);
        if (items.isNotEmpty) {
          final signature = _paramTemplateSignature(params);
          _winningParamTemplate[baseUrl] = signature;
          _log(
            '[fetchVodListByCandidates] success '
            'params=${_paramsText(params)} '
            'template=$signature '
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
  ///
  /// GitHub raw 国内直连极不稳定，这里对 raw.githubusercontent.com 自动生成
  /// jsDelivr / ghproxy 镜像候选，任一命中即返回，避免首屏整个拉不出来。
  static Future<List<VideoSource>> fetchSources(String configUrl) async {
    final url = configUrl.trim();
    if (url.isEmpty) {
      _log('[fetchSources] skip empty configUrl');
      return [];
    }

    final candidates = _catalogUrlCandidates(url);
    _log(
      '[fetchSources] start configUrl=$url '
      'candidates=${candidates.length} -> ${candidates.join(" | ")}',
    );

    for (final candidate in candidates) {
      try {
        final decoded = await _getJson(candidate);
        _log(
          '[fetchSources] via=$candidate decodedType=${decoded.runtimeType}',
        );

        final rawItems = _extractSourceItems(decoded);
        _log(
          '[fetchSources] rawItems=${rawItems.length} '
          'sampleKeys=${rawItems.isNotEmpty ? rawItems.first.keys.take(12).join(" | ") : "-"}',
        );

        final sources = rawItems
            .map(_normalizeSourceItem)
            .whereType<Map<String, dynamic>>()
            .map(VideoSource.fromJson)
            .toList(growable: false);

        if (sources.isNotEmpty) {
          _log(
            '[fetchSources] success via=$candidate '
            'parsedSources=${sources.length} '
            'sample=${sources.take(5).map((e) => e.name).join(" | ")}',
          );
          return sources;
        }

        _log('[fetchSources] empty result via=$candidate, try next mirror');
      } catch (e, st) {
        _log('[fetchSources] candidate failed url=$candidate error=$e');
        _log(st.toString());
      }
    }

    _log('[fetchSources] all candidates failed');
    return [];
  }

  /// 为目录地址生成镜像候选：原地址优先，其后是 GitHub raw 的镜像。
  static List<String> _catalogUrlCandidates(String rawUrl) {
    final trimmed = rawUrl.trim();
    final candidates = <String>[trimmed];

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.host.toLowerCase() == 'raw.githubusercontent.com') {
      final segs = uri.pathSegments;
      // /{user}/{repo}/{branch}/{path...}
      if (segs.length >= 4) {
        final user = segs[0];
        final repo = segs[1];
        final branch = segs[2];
        final path = segs.sublist(3).join('/');

        candidates.addAll([
          'https://cdn.jsdelivr.net/gh/$user/$repo@$branch/$path',
          'https://fastly.jsdelivr.net/gh/$user/$repo@$branch/$path',
          'https://ghproxy.net/$trimmed',
        ]);
      }
    }

    // 去重保序
    final seen = <String>{};
    return candidates.where((u) => u.isNotEmpty && seen.add(u)).toList();
  }

  /// 分类：
  /// 1. 优先尝试根接口
  /// 2. 再尝试 ac=class
  /// 3. 再尝试 ac=list
  ///
  /// 注意：根接口只接受“明确是分类”的结构，避免把视频列表误判成分类
  /// 分类列表变化很慢，套 30 分钟 TTL 缓存，切 tab / 返回近乎秒开。
  static Future<List<VideoCategory>> fetchCategories(String baseUrl) {
    return TtlCache.getOrFetch<List<VideoCategory>>(
      'categories::$baseUrl',
      ttl: const Duration(minutes: 30),
      shouldCache: (value) => value.isNotEmpty,
      loader: () => _fetchCategoriesImpl(baseUrl),
    );
  }

  static Future<List<VideoCategory>> _fetchCategoriesImpl(
    String baseUrl,
  ) async {
    final url = _buildVodBaseUrl(baseUrl);
    if (url.isEmpty) {
      _log('[fetchCategories] skip empty baseUrl');
      return [];
    }

    _log(
      '[fetchCategories] start baseUrl=$baseUrl '
      'builtUrl=$url '
      'proxyEnabled=${vodProxyConfig.enabled}',
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
            _log(
              '[fetchCategories] decode json failed, will try fallback parser',
            );
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
          _log(
            '[fetchCategories] candidate failed params=${_paramsText(params)} error=$e',
          );
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
  /// 列表页短时效缓存(5 分钟):翻回上一页 / 来回切分类近乎秒开。
  ///
  /// [typeQuery] 是真正写进 `t=` 的值。父分类会被展开成子分类逗号多选
  /// (如 "6,7,8,9")，用来救活“顶级分类不挂视频、视频挂子类”的源。
  /// 为空时退回用 [typeId] 本身。[typeId] 始终作为“身份”用于缓存键与匹配。
  static Future<List<VodItem>> fetchVideos(
    String baseUrl,
    int? typeId,
    int page, {
    String? typeQuery,
  }) {
    final tKey = (typeQuery != null && typeQuery.trim().isNotEmpty)
        ? typeQuery.trim()
        : (typeId?.toString() ?? 'all');
    return TtlCache.getOrFetch<List<VodItem>>(
      'videos::$baseUrl::$tKey::$page',
      ttl: const Duration(minutes: 5),
      shouldCache: (value) => value.isNotEmpty,
      loader: () =>
          _fetchVideosImpl(baseUrl, typeId, page, typeQuery: typeQuery),
    );
  }

  static Future<List<VodItem>> _fetchVideosImpl(
    String baseUrl,
    int? typeId,
    int page, {
    String? typeQuery,
  }) async {
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
      'proxyEnabled=${vodProxyConfig.enabled} '
      'mediaProxyEnabled=${vodProxyConfig.mediaEnabled}',
    );

    final candidates = <Map<String, String>>[];

    // 只有“全部 + 第 1 页”时，先试根接口
    if (typeId == null && page == 1) {
      candidates.add(const <String, String>{});
    }

    if (typeId != null && typeId > 0) {
      // 优先用展开后的 typeQuery(父类→子类逗号多选);为空退回 typeId 本身。
      final tValue = (typeQuery != null && typeQuery.trim().isNotEmpty)
          ? typeQuery.trim()
          : '$typeId';
      candidates.addAll([
        {'ac': 'list', 't': tValue, 'pg': '$page'},
        {'ac': 'videolist', 't': tValue, 'pg': '$page'},
        {'t': tValue, 'pg': '$page'},
        {'ac': 'list', 't': tValue, 'page': '$page'},
        {'t': tValue, 'page': '$page'},
      ]);
      // 若用了展开的多选 ID,再补一组“原始 typeId 单选”兜底:
      // 万一某源不认逗号多选,还能用父类 ID 试一次。
      if (tValue != '$typeId') {
        candidates.addAll([
          {'ac': 'list', 't': '$typeId', 'pg': '$page'},
          {'t': '$typeId', 'pg': '$page'},
        ]);
      }
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
  ///
  /// 返回值语义：
  /// - 成功且无匹配 → 返回空列表 []
  /// - 所有候选参数均网络/解析失败 → 向上抛出异常
  /// - 至少一个候选成功但无结果 → 返回空列表 []（与"成功且无匹配"相同）
  ///
  /// [timeout] 是**整个搜索的总预算**（覆盖全部候选参数的累计尝试时间），
  /// 而非每个候选的超时。[fastFail] 为 true 时默认使用 8 秒总预算，
  /// 单源搜索场景下避免死源拖慢整体聚合。
  static Future<List<VodItem>> searchVideo(
    String baseUrl,
    String keyword, {
    bool fastFail = false,
    Duration? timeout,
  }) async {
    final url = _buildVodBaseUrl(baseUrl);
    final query = keyword.trim();
    if (url.isEmpty || query.isEmpty) {
      _log('[searchVideo] skip empty url or keyword');
      return [];
    }

    final policy = fastFail
        ? const VideoGetRequestPolicy(maxAttempts: 1)
        : const VideoGetRequestPolicy();
    final effectiveTimeout =
        timeout ?? (fastFail ? const Duration(seconds: 8) : _defaultTimeout);

    _log('[searchVideo] start baseUrl=$baseUrl builtUrl=$url keyword=$query');

    final candidates = <Map<String, String>>[
      {'ac': 'list', 'wd': query},
      {'ac': 'videolist', 'wd': query},
      {'ac': 'search', 'wd': query},
      {'wd': query},
    ];

    // 按总超时预算逐个尝试候选参数；任一命中即返回。
    final stopwatch = Stopwatch()..start();
    final errors = <Object?>[];
    var hadSuccessfulCandidate = false;
    for (final params in candidates) {
      // 检查是否已耗尽总预算
      if (stopwatch.elapsed >= effectiveTimeout) {
        _log(
          '[searchVideo] total timeout budget exhausted '
          'elapsed=${stopwatch.elapsed}',
        );
        break;
      }

      final remaining = effectiveTimeout - stopwatch.elapsed;
      if (remaining <= Duration.zero) break;

      try {
        final requestUrl = _withQuery(url, params);
        _log(
          '[searchVideo] try requestUrl=$requestUrl '
          'params=${_paramsText(params)} '
          'remainingBudget=$remaining',
        );

        // _getRawString 的 request policy 可能包含重试；对其整体再施加
        // 剩余预算，确保重试和退避也不能越过本次搜索的总时限。
        final rawBody = await _getRawString(
          requestUrl,
          timeout: remaining,
          policy: policy,
        ).timeout(remaining);
        final items = await IsolateParser.parseVodList(rawBody);
        hadSuccessfulCandidate = true;

        _log(
          '[searchVideo] parsed count=${items.length} '
          'sample=${_sampleVodItems(items)}',
        );

        if (items.isNotEmpty) return _patchVodItemsMedia(items, url);
      } catch (e, st) {
        errors.add(e);
        _log(
          '[searchVideo] candidate failed params=${_paramsText(params)} error=$e',
        );
        _log(st.toString());
      }
    }

    if (!hadSuccessfulCandidate && errors.isNotEmpty) {
      throw AllSearchCandidatesFailedException(
        baseUrl: baseUrl,
        keyword: query,
        errors: errors,
      );
    }

    _log('[searchVideo] completed without matches');
    return [];
  }

  /// 获取详情
  /// 详情短时效缓存(10 分钟):重复点开同一部片、返回再进近乎秒开。
  static Future<VodItem?> fetchDetail(String baseUrl, int vodId) {
    return TtlCache.getOrFetch<VodItem?>(
      'detail::$baseUrl::$vodId',
      ttl: const Duration(minutes: 10),
      shouldCache: (value) => value != null,
      loader: () => _fetchDetailImpl(baseUrl, vodId),
    );
  }

  static Future<VodItem?> _fetchDetailImpl(String baseUrl, int vodId) async {
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

        _log(
          '[fetchDetail] no detail matched for params=${_paramsText(params)}',
        );
      } catch (e, st) {
        _log(
          '[fetchDetail] candidate failed params=${_paramsText(params)} error=$e',
        );
        _log(st.toString());
      }
    }

    _log('[fetchDetail] fallback null');
    return null;
  }
}
