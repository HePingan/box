import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'models.dart';
import 'video_source.dart';

class LicensedCatalogVideoSource implements VideoSource {
  LicensedCatalogVideoSource({
    required List<String> catalogUrls,
    this.catalogName = '授权影视源',
    http.Client? client,
    this.requestTimeout = const Duration(milliseconds: 4500),
    this.maxConcurrentRequests = 48,
    this.providerCacheTtl = const Duration(minutes: 20),
  })  : catalogUrls = List.unmodifiable(
          catalogUrls.map((e) => e.trim()).where((e) => e.isNotEmpty),
        ),
        _client = client ?? http.Client() {
    if (this.catalogUrls.isEmpty) {
      throw ArgumentError('catalogUrls 不能为空');
    }
  }

  final List<String> catalogUrls;
  final String catalogName;
  final http.Client _client;
  final Duration requestTimeout;
  final int maxConcurrentRequests;
  final Duration providerCacheTtl;

  Future<List<_LicensedProvider>>? _providersFuture;
  List<_LicensedProvider>? _providersCache;
  DateTime? _providersLoadedAt;

  final Map<String, _ProviderStats> _stats = {};
  final Map<String, List<_ProviderClass>> _classCache = {};

  @override
  String get sourceName => catalogName;

  @override
  List<VideoCategory> get categories => const [
        VideoCategory(id: 'latest', title: '最新', query: 'latest', description: '聚合所有可用授权站点的最新更新'),
        VideoCategory(id: 'movie', title: '电影', query: 'movie', description: '自动映射各站点的电影分类'),
        VideoCategory(id: 'tv', title: '电视剧', query: 'tv', description: '自动映射各站点的剧集分类'),
        VideoCategory(id: 'anime', title: '动漫', query: 'anime', description: '自动映射各站点的动漫分类'),
        VideoCategory(id: 'variety', title: '综艺', query: 'variety', description: '自动映射各站点的综艺分类'),
        VideoCategory(id: 'short', title: '短剧', query: 'short', description: '自动映射微短剧 / 短剧 / 竖屏剧分类'),
      ];

  Stream<List<VideoItem>> searchVideosStream(String keyword, {int page = 1}) async* {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;

    final providers = await _loadProviders();
    if (providers.isEmpty) return;

    final sortedProviders = _sortProviders(providers);
    
    await for (final partialList in _streamProviders(
      sortedProviders,
      (provider) => _searchFromProvider(provider, trimmed, page),
    )) {
      final distinct = _dedupItems(partialList);
      distinct.sort((a, b) => _searchScore(b, trimmed).compareTo(_searchScore(a, trimmed)));
      yield distinct;
    }
  }

  Stream<List<VideoItem>> fetchByPathStream(String path, {int page = 1}) async* {
    final normalized = path.trim().toLowerCase();
    final providers = await _loadProviders();
    if (providers.isEmpty) return;

    final sortedProviders = _sortProviders(providers);
    final semantic = _parseSemanticCategory(normalized);

    Stream<List<VideoItem>> stream;

    switch (semantic) {
      case _SemanticCategory.latest:
        stream = _streamProviders(sortedProviders, (p) => _fetchLatestFromProvider(p, page));
        break;
      case _SemanticCategory.movie:
      case _SemanticCategory.tv:
      case _SemanticCategory.anime:
      case _SemanticCategory.variety:
      case _SemanticCategory.shortDrama:
        stream = _streamProviders(sortedProviders, (p) => _fetchCategoryFromProvider(p, semantic, page));
        break;
      case _SemanticCategory.unknown:
        if (normalized.isEmpty || normalized == '1') {
          stream = _streamProviders(sortedProviders, (p) => _fetchLatestFromProvider(p, page));
        } else {
          stream = _streamProviders(sortedProviders, (p) => _searchFromProvider(p, normalized, page));
        }
        break;
    }

    await for (final partialList in stream) {
      final distinct = _dedupItems(partialList);
      distinct.sort(_compareListItems);
      yield distinct;
    }
  }

  Stream<List<VideoItem>> _streamProviders(
    List<_LicensedProvider> providers,
    Future<List<VideoItem>> Function(_LicensedProvider provider) task,
  ) async* {
    final all = <VideoItem>[];
    int pending = providers.length;
    final controller = StreamController<List<VideoItem>>();

    if (pending == 0) {
      controller.close();
      yield* controller.stream;
      return;
    }

    for (final provider in providers) {
      task(provider).then((items) {
        if (items.isNotEmpty) {
          all.addAll(items);
          controller.add(List.from(all));
        }
      }).catchError((_) {}).whenComplete(() {
        pending--;
        if (pending == 0) controller.close();
      });
    }

    yield* controller.stream;
  }

  @override
  Future<List<VideoItem>> searchVideos(String keyword, {int page = 1}) async {
    List<VideoItem> result = [];
    await for (final items in searchVideosStream(keyword, page: page)) {
      result = items;
    }
    return result;
  }

  @override
  Future<List<VideoItem>> fetchByPath(String path, {int page = 1}) async {
    List<VideoItem> result = [];
    await for (final items in fetchByPathStream(path, page: page)) {
      result = items;
    }
    return result;
  }

  @override
  Future<VideoDetail> fetchDetail({
    required VideoItem item,
  }) async {
    final providers = await _loadProviders();
    if (providers.isEmpty) {
      throw Exception('没有可用的授权站点');
    }

    final prioritized = <_LicensedProvider>[];
    final seen = <String>{};

    void addProvider(_LicensedProvider provider) {
      if (seen.add(provider.key)) {
        prioritized.add(provider);
      }
    }

    final byKey = providers.where((e) => e.key == item.providerKey);
    for (final provider in byKey) {
      addProvider(provider);
    }
    final byName = providers.where((e) => e.name == item.sourceName);
    for (final provider in byName) {
      addProvider(provider);
    }
    for (final provider in _sortProviders(providers)) {
      addProvider(provider);
    }

    Object? lastError;
    for (final provider in prioritized) {
      try {
        final detail = await _fetchDetailFromProvider(provider, item);
        if (detail.playSources.isNotEmpty ||
            detail.description.trim().isNotEmpty ||
            detail.cover.trim().isNotEmpty) {
          return detail;
        }
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('获取详情失败：$lastError');
  }

  Future<List<_LicensedProvider>> _loadProviders({bool forceRefresh = false}) async {
    final now = DateTime.now();

    if (!forceRefresh &&
        _providersCache != null &&
        _providersLoadedAt != null &&
        now.difference(_providersLoadedAt!) < providerCacheTtl) {
      return _providersCache!;
    }

    if (!forceRefresh && _providersFuture != null) {
      return _providersFuture!;
    }

    final future = _doLoadProviders();
    _providersFuture = future;

    try {
      final providers = await future;
      _providersCache = providers;
      _providersLoadedAt = DateTime.now();
      return providers;
    } finally {
      _providersFuture = null;
    }
  }

  Future<List<_LicensedProvider>> _doLoadProviders() async {
    final all = <_LicensedProvider>[];

    for (final catalogUrl in catalogUrls) {
      try {
        final response = await _client.get(Uri.parse(catalogUrl)).timeout(requestTimeout);

        if (response.statusCode < 200 || response.statusCode >= 300) {
          continue;
        }

        final text = _decodeResponseBody(response);
        final providers = _parseCatalogManifest(text, catalogUrl);
        all.addAll(providers);
      } catch (_) {}
    }

    final dedup = <String, _LicensedProvider>{};
    for (final provider in all) {
      dedup.putIfAbsent(provider.apiUrl, () => provider);
    }

    return dedup.values.toList();
  }

  List<_LicensedProvider> _parseCatalogManifest(String text, String catalogUrl) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const [];

    final parsedJson = _tryJsonDecode(trimmed);
    if (parsedJson != null) {
      final fromJson = _parseProvidersFromJson(parsedJson);
      if (fromJson.isNotEmpty) return fromJson;
    }

    final lines = const LineSplitter().convert(trimmed);
    final result = <_LicensedProvider>[];

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#') || line.startsWith('//') || line.startsWith(';')) {
        continue;
      }

      String name = '';
      String api = '';

      if (line.contains('|')) {
        final parts = line.split('|');
        if (parts.length >= 2) {
          name = parts.first.trim();
          api = parts.sublist(1).join('|').trim();
        }
      } else if (line.contains(',')) {
        final parts = line.split(',');
        if (parts.length >= 2) {
          name = parts.first.trim();
          api = parts.sublist(1).join(',').trim();
        }
      } else if (_looksLikeHttpUrl(line)) {
        api = line;
      }

      api = _normalizeApiUrl(api);
      if (api.isEmpty) continue;

      final provider = _LicensedProvider(
        key: _stableKey(api),
        name: name.isNotEmpty ? name : _guessProviderName(api),
        apiUrl: api,
        siteUrl: _siteUrlFromApi(api),
        headers: const {},
        catalogUrl: catalogUrl,
      );

      result.add(provider);
    }

    return result;
  }

  List<_LicensedProvider> _parseProvidersFromJson(dynamic jsonValue) {
    final list = <dynamic>[];

    if (jsonValue is List) {
      list.addAll(jsonValue);
    } else if (jsonValue is Map) {
      for (final key in ['sites', 'providers', 'list', 'data', 'items']) {
        final value = jsonValue[key];
        if (value is List) {
          list.addAll(value);
          break;
        }
      }
      if (list.isEmpty) {
        for (final entry in jsonValue.entries) {
          if (entry.value is List) {
            list.addAll(entry.value as List);
            break;
          }
        }
      }
    }

    final result = <_LicensedProvider>[];

    for (final element in list) {
      if (element is String) {
        final api = _normalizeApiUrl(element);
        if (api.isEmpty) continue;

        result.add(
          _LicensedProvider(
            key: _stableKey(api),
            name: _guessProviderName(api),
            apiUrl: api,
            siteUrl: _siteUrlFromApi(api),
            headers: const {},
            catalogUrl: '',
          ),
        );
        continue;
      }

      if (element is! Map) continue;
      final map = Map<String, dynamic>.from(element);

      final api = _normalizeApiUrl(
        _pickString(map, ['api', 'apiUrl', 'url', 'link', 'vodApi', 'vod_api']),
      );
      if (api.isEmpty) continue;

      final name = _pickString(map, ['name', 'title', 'siteName', 'site_name']);
      final siteUrl = _pickString(map, ['siteUrl', 'site_url', 'web', 'webUrl', 'home']);
      final headers = _parseManifestHeaders(map['headers']);

      result.add(
        _LicensedProvider(
          key: _stableKey(api),
          name: name.isNotEmpty ? name : _guessProviderName(api),
          apiUrl: api,
          siteUrl: siteUrl.isNotEmpty ? siteUrl : _siteUrlFromApi(api),
          headers: headers,
          catalogUrl: '',
        ),
      );
    }

    return result;
  }

  Map<String, String> _parseManifestHeaders(dynamic raw) {
    if (raw is! Map) return const {};
    final result = <String, String>{};

    raw.forEach((key, value) {
      final k = key.toString().trim();
      final v = value?.toString().trim() ?? '';
      if (k.isEmpty || v.isEmpty) return;
      result[_normalizeHeaderKey(k)] = v;
    });

    return result;
  }

  List<_LicensedProvider> _sortProviders(List<_LicensedProvider> providers) {
    final sorted = [...providers];
    sorted.sort((a, b) {
      final scoreA = _providerScore(a);
      final scoreB = _providerScore(b);
      return scoreB.compareTo(scoreA);
    });
    return sorted;
  }

  double _providerScore(_LicensedProvider provider) {
    final stats = _stats[provider.key];
    if (stats == null) return 0;
    final now = DateTime.now();
    final cooling = stats.cooldownUntil != null && now.isBefore(stats.cooldownUntil!);
    var score = 0.0;
    score += stats.successCount * 3.0;
    score -= stats.failureCount * 2.5;
    score -= stats.averageLatencyMs / 1200.0;
    if (cooling) score -= 1000;
    return score;
  }

  void _recordSuccess(_LicensedProvider provider, Duration latency) {
    final stats = _stats.putIfAbsent(provider.key, () => _ProviderStats());
    stats.successCount += 1;
    stats.averageLatencyMs = stats.averageLatencyMs <= 0
        ? latency.inMilliseconds.toDouble()
        : (stats.averageLatencyMs * 0.7) + latency.inMilliseconds * 0.3;

    if (stats.failureCount > 0) {
      stats.failureCount = math.max(0, stats.failureCount - 1);
    }
    stats.cooldownUntil = null;
  }

  void _recordFailure(_LicensedProvider provider) {
    final stats = _stats.putIfAbsent(provider.key, () => _ProviderStats());
    stats.failureCount += 1;
    if (stats.failureCount >= 2) {
      final coolMinutes = math.min(15, stats.failureCount * 2);
      stats.cooldownUntil = DateTime.now().add(Duration(minutes: coolMinutes));
    }
  }

  Future<List<VideoItem>> _searchFromProvider(_LicensedProvider provider, String keyword, int page) async {
    final stopwatch = Stopwatch()..start();
    try {
      final feed = await _fetchParsedFeed(provider, _buildSearchTargets(provider, keyword, page));
      _cacheClasses(provider, feed.classes);
      _recordSuccess(provider, stopwatch.elapsed);
      return feed.items;
    } catch (_) {
      _recordFailure(provider);
      return const [];
    }
  }

  Future<List<VideoItem>> _fetchLatestFromProvider(_LicensedProvider provider, int page) async {
    final stopwatch = Stopwatch()..start();
    try {
      final feed = await _fetchParsedFeed(provider, _buildLatestTargets(provider, page));
      _cacheClasses(provider, feed.classes);
      _recordSuccess(provider, stopwatch.elapsed);
      return feed.items;
    } catch (_) {
      _recordFailure(provider);
      return const [];
    }
  }

  Future<List<VideoItem>> _fetchCategoryFromProvider(_LicensedProvider provider, _SemanticCategory category, int page) async {
    final stopwatch = Stopwatch()..start();
    try {
      await _ensureProviderClasses(provider);
      final classes = _classCache[provider.key] ?? const [];
      final matched = _matchClassIds(classes, category);
      if (matched.isEmpty) return const [];
      final all = <VideoItem>[];
      for (final classId in matched.take(3)) {
        final feed = await _fetchParsedFeed(provider, _buildCategoryTargets(provider, classId, page));
        _cacheClasses(provider, feed.classes);
        all.addAll(feed.items);
      }
      _recordSuccess(provider, stopwatch.elapsed);
      return all;
    } catch (_) {
      _recordFailure(provider);
      return const [];
    }
  }

  Future<void> _ensureProviderClasses(_LicensedProvider provider) async {
    final exists = _classCache[provider.key];
    if (exists != null && exists.isNotEmpty) return;
    try {
      final feed = await _fetchParsedFeed(provider, _buildLatestTargets(provider, 1));
      _cacheClasses(provider, feed.classes);
    } catch (_) {}
  }

  void _cacheClasses(_LicensedProvider provider, List<_ProviderClass> classes) {
    if (classes.isEmpty) return;
    _classCache[provider.key] = classes;
  }

  List<String> _matchClassIds(List<_ProviderClass> classes, _SemanticCategory category) {
    bool match(String name, List<RegExp> patterns) => patterns.any((exp) => exp.hasMatch(name));
    final result = <String>[];

    final moviePatterns = <RegExp>[RegExp(r'电影'), RegExp(r'movie', caseSensitive: false)];
    final tvPatterns = <RegExp>[RegExp(r'电视剧'), RegExp(r'连续剧'), RegExp(r'剧'), RegExp(r'\btv\b', caseSensitive: false)];
    final animePatterns = <RegExp>[RegExp(r'动漫'), RegExp(r'动画'), RegExp(r'番剧'), RegExp(r'anime', caseSensitive: false)];
    final varietyPatterns = <RegExp>[RegExp(r'综艺'), RegExp(r'variety', caseSensitive: false)];
    final shortPatterns = <RegExp>[RegExp(r'短剧'), RegExp(r'微短剧'), RegExp(r'竖屏'), RegExp(r'爽剧')];

    for (final item in classes) {
      final name = item.name.trim();
      if (name.isEmpty) continue;

      final ok = switch (category) {
        _SemanticCategory.movie => match(name, moviePatterns),
        _SemanticCategory.tv => match(name, tvPatterns),
        _SemanticCategory.anime => match(name, animePatterns),
        _SemanticCategory.variety => match(name, varietyPatterns),
        _SemanticCategory.shortDrama => match(name, shortPatterns),
        _SemanticCategory.latest || _SemanticCategory.unknown => false,
      };
      if (ok) result.add(item.id);
    }
    return result.toSet().toList();
  }

  Future<VideoDetail> _fetchDetailFromProvider(_LicensedProvider provider, VideoItem item) async {
    final stopwatch = Stopwatch()..start();
    final targets = <_RequestTarget>[];

    if (_looksLikeHttpUrl(item.detailUrl)) {
      targets.add(_RequestTarget(name: 'detailUrl', url: Uri.parse(item.detailUrl), headers: _defaultRequestHeaders(provider)));
    }
    if (item.id.trim().isNotEmpty) {
      targets.addAll(_buildDetailTargets(provider, item.id.trim()));
    }
    if (targets.isEmpty && item.title.trim().isNotEmpty) {
      targets.addAll(_buildSearchTargets(provider, item.title.trim(), 1));
    }

    final feed = await _fetchParsedFeed(provider, targets, preferDetail: true);
    _cacheClasses(provider, feed.classes);
    _recordSuccess(provider, stopwatch.elapsed);

    if (feed.detail != null) {
      final detail = feed.detail!;
      return detail.copyWith(item: detail.item.copyWith(mergedItems: const []));
    }
    if (feed.items.isNotEmpty) {
      final best = feed.items.first;
      return VideoDetail(item: best.copyWith(mergedItems: const []), cover: best.cover, description: best.intro, playSources: const [], sourceUrl: feed.sourceUrl);
    }
    throw Exception('当前站点未返回详情数据');
  }

  Future<_ParsedFeed> _fetchParsedFeed(_LicensedProvider provider, List<_RequestTarget> targets, {bool preferDetail = false}) async {
    Object? lastError;
    final fallbackClasses = <_ProviderClass>[];

    for (final target in targets) {
      try {
        final response = await _client.get(target.url, headers: target.headers).timeout(requestTimeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          lastError = 'HTTP ${response.statusCode}';
          continue;
        }
        final text = _decodeResponseBody(response);
        if (text.trim().isEmpty) continue;

        final parsed = _parseApiResponse(text, provider: provider, requestUrl: target.url.toString(), preferDetail: preferDetail);
        
        if (parsed.classes.isNotEmpty) {
          fallbackClasses.addAll(parsed.classes);
        }

        if (parsed.items.isNotEmpty || parsed.detail != null) {
          return _ParsedFeed(
            items: parsed.items,
            detail: parsed.detail,
            classes: parsed.classes.isNotEmpty ? parsed.classes : fallbackClasses,
            sourceUrl: parsed.sourceUrl,
          );
        }
      } catch (e) {
        lastError = e;
      }
    }
    
    if (fallbackClasses.isNotEmpty) {
      return _ParsedFeed(items: const [], detail: null, classes: fallbackClasses, sourceUrl: targets.first.url.toString());
    }

    throw Exception('片源请求失败：$lastError');
  }

  _ParsedFeed _parseApiResponse(String text, {required _LicensedProvider provider, required String requestUrl, required bool preferDetail}) {
    final jsonValue = _tryJsonDecode(text);
    if (jsonValue != null) {
      return _parseJsonFeed(jsonValue, provider: provider, requestUrl: requestUrl, preferDetail: preferDetail);
    }
    return _parseXmlFeed(text, provider: provider, requestUrl: requestUrl, preferDetail: preferDetail);
  }

  _ParsedFeed _parseJsonFeed(dynamic root, {required _LicensedProvider provider, required String requestUrl, required bool preferDetail}) {
    final classes = _extractJsonClasses(root);
    final list = _extractJsonList(root);

    final items = list
        .map((e) => _videoItemFromJsonMap(e, provider: provider, sourceUrl: requestUrl))
        .where((e) => e.title.trim().isNotEmpty || e.id.trim().isNotEmpty).toList();

    VideoDetail? detail;
    if (preferDetail && list.isNotEmpty) {
      detail = _videoDetailFromJsonMap(list.first, provider: provider, sourceUrl: requestUrl);
    }
    return _ParsedFeed(items: items, detail: detail, classes: classes, sourceUrl: requestUrl);
  }

  _ParsedFeed _parseXmlFeed(String text, {required _LicensedProvider provider, required String requestUrl, required bool preferDetail}) {
    final document = XmlDocument.parse(text);
    final classes = <_ProviderClass>[];
    for (final element in document.descendants.whereType<XmlElement>()) {
      if (_localName(element.name) != 'ty') continue;
      final id = element.getAttribute('id')?.trim() ?? '';
      final name = element.innerText.trim();
      if (id.isEmpty || name.isEmpty) continue;
      classes.add(_ProviderClass(id: id, name: name));
    }

    final videos = <XmlElement>[];
    for (final element in document.descendants.whereType<XmlElement>()) {
      if (_localName(element.name) == 'video') videos.add(element);
    }

    final items = videos
        .map((e) => _videoItemFromXmlElement(e, provider: provider, sourceUrl: requestUrl))
        .where((e) => e.title.trim().isNotEmpty || e.id.trim().isNotEmpty).toList();

    VideoDetail? detail;
    if (preferDetail && videos.isNotEmpty) {
      detail = _videoDetailFromXmlElement(videos.first, provider: provider, sourceUrl: requestUrl);
    }
    return _ParsedFeed(items: items, detail: detail, classes: classes, sourceUrl: requestUrl);
  }

  List<_ProviderClass> _extractJsonClasses(dynamic root) {
    dynamic classes;
    if (root is Map) {
      classes = root['class'] ?? (root['data'] is Map ? root['data']['class'] : null) ?? (root['result'] is Map ? root['result']['class'] : null);
    }
    if (classes is! List) return const [];
    final result = <_ProviderClass>[];
    for (final raw in classes) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final id = _pickString(map, ['type_id', 'id', 'tid', 'class_id']);
      final name = _pickString(map, ['type_name', 'name', 'title', 'class_name']);
      if (id.isNotEmpty && name.isNotEmpty) result.add(_ProviderClass(id: id, name: name));
    }
    return result;
  }

  List<Map<String, dynamic>> _extractJsonList(dynamic root) {
    dynamic list;
    if (root is List) list = root;
    else if (root is Map) list = root['list'] ?? (root['data'] is Map ? root['data']['list'] : null) ?? (root['result'] is Map ? root['result']['list'] : null) ?? (root['data'] is List ? root['data'] : null);
    if (list is! List) return const [];
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  VideoItem _videoItemFromJsonMap(Map<String, dynamic> map, {required _LicensedProvider provider, required String sourceUrl}) {
    final id = _pickString(map, ['vod_id', 'id']);
    final title = _cleanText(_pickString(map, ['vod_name', 'name', 'title']));
    final cover = _resolveUrl(sourceUrl, _pickString(map, ['vod_pic', 'pic', 'cover', 'thumb']));
    final intro = _cleanText(_pickString(map, ['vod_content', 'content', 'description', 'desc']));
    final remark = _cleanText(_pickString(map, ['vod_remarks', 'remarks', 'remark', 'note']));
    final subtitle = _cleanText(_pickString(map, ['vod_sub', 'sub', 'subtitle']));
    final category = _cleanText(_pickString(map, ['type_name', 'category', 'class', 'vod_class']));
    final year = _cleanText(_pickString(map, ['vod_year', 'year']));
    final area = _cleanText(_pickString(map, ['vod_area', 'area']));

    final detailUrl = id.isNotEmpty ? _buildUri(provider.apiUrl, query: {'ac': 'detail', 'ids': id}).toString() : sourceUrl;

    return VideoItem(id: id, title: title, detailUrl: detailUrl, cover: cover, intro: intro, subtitle: subtitle, category: category, yearText: year, sourceName: provider.name, providerKey: provider.key, area: area, remark: remark);
  }

  VideoDetail _videoDetailFromJsonMap(Map<String, dynamic> map, {required _LicensedProvider provider, required String sourceUrl}) {
    final item = _videoItemFromJsonMap(map, provider: provider, sourceUrl: sourceUrl);
    final creator = _joinNonEmpty([_cleanText(_pickString(map, ['vod_director', 'director'])), _cleanText(_pickString(map, ['vod_actor', 'actor', 'actors']))], separator: ' / ');
    final tags = <String>{..._splitTags(_pickString(map, ['vod_class', 'class'])), if (item.category.isNotEmpty) item.category, if (item.yearText.isNotEmpty) item.yearText, if (item.area.isNotEmpty) item.area}.where((e) => e.trim().isNotEmpty).toList();
    final playSources = _parseJsonPlaySources(map, sourceUrl);
    return VideoDetail(item: item, cover: item.cover, description: item.intro, creator: creator, sourceUrl: sourceUrl, tags: tags, playSources: playSources);
  }

  VideoItem _videoItemFromXmlElement(XmlElement element, {required _LicensedProvider provider, required String sourceUrl}) {
    final id = _xmlChildText(element, const ['id']);
    final title = _cleanText(_xmlChildText(element, const ['name', 'title']));
    final cover = _resolveUrl(sourceUrl, _xmlChildText(element, const ['pic', 'cover', 'thumb']));
    final intro = _cleanText(_xmlChildText(element, const ['des', 'content', 'description']));
    final remark = _cleanText(_xmlChildText(element, const ['note', 'last', 'state']));
    final category = _cleanText(_xmlChildText(element, const ['type', 'typename']));
    final year = _cleanText(_xmlChildText(element, const ['year']));
    final area = _cleanText(_xmlChildText(element, const ['area']));

    final detailUrl = id.isNotEmpty ? _buildUri(provider.apiUrl, query: {'ac': 'detail', 'ids': id}).toString() : sourceUrl;
    return VideoItem(id: id, title: title, detailUrl: detailUrl, cover: cover, intro: intro, subtitle: '', category: category, yearText: year, sourceName: provider.name, providerKey: provider.key, area: area, remark: remark);
  }

  VideoDetail _videoDetailFromXmlElement(XmlElement element, {required _LicensedProvider provider, required String sourceUrl}) {
    final item = _videoItemFromXmlElement(element, provider: provider, sourceUrl: sourceUrl);
    final actor = _cleanText(_xmlChildText(element, const ['actor']));
    final director = _cleanText(_xmlChildText(element, const ['director']));
    final creator = _joinNonEmpty([director, actor], separator: ' / ');
    final tags = <String>{if (item.category.isNotEmpty) item.category, if (item.yearText.isNotEmpty) item.yearText, if (item.area.isNotEmpty) item.area}.toList();
    final playSources = _parseXmlPlaySources(element, sourceUrl);
    return VideoDetail(item: item, cover: item.cover, description: item.intro, creator: creator, sourceUrl: sourceUrl, tags: tags, playSources: playSources);
  }

  List<VideoPlaySource> _parseJsonPlaySources(Map<String, dynamic> map, String sourceUrl) {
    final fromText = _pickString(map, ['vod_play_from', 'play_from']);
    final urlText = _pickString(map, ['vod_play_url', 'play_url']);
    if (fromText.isNotEmpty || urlText.isNotEmpty) {
      return _parsePlaySourceBlocks(fromText, urlText, sourceUrl);
    }
    final rawList = map['vod_play_list'] ?? map['play_list'] ?? map['urls'];
    if (rawList is List) {
      final result = <VideoPlaySource>[];
      for (final raw in rawList) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final name = _pickString(item, ['name', 'from', 'flag', 'player']);
        final urls = item['urls'];
        if (urls is List) {
          final episodes = <VideoEpisode>[];
          for (var i = 0; i < urls.length; i++) {
            final row = urls[i];
            if (row is Map) {
              final rowMap = Map<String, dynamic>.from(row);
              final title = _pickString(rowMap, ['name', 'title']).trim().isNotEmpty ? _pickString(rowMap, ['name', 'title']).trim() : '第${i + 1}集';
              final url = _resolveUrl(sourceUrl, _pickString(rowMap, ['url', 'link']));
              if (url.isNotEmpty) episodes.add(VideoEpisode(title: title, url: url, index: episodes.length));
            }
          }
          if (episodes.isNotEmpty) result.add(VideoPlaySource(name: name.isNotEmpty ? name : '默认线路', episodes: episodes));
        }
      }
      if (result.isNotEmpty) return result;
    }
    return const [];
  }

  List<VideoPlaySource> _parseXmlPlaySources(XmlElement element, String sourceUrl) {
    final result = <VideoPlaySource>[];
    XmlElement? dl;
    for (final child in element.descendants.whereType<XmlElement>()) {
      if (_localName(child.name) == 'dl') {
        dl = child;
        break;
      }
    }
    if (dl == null) return const [];
    for (final dd in dl.children.whereType<XmlElement>()) {
      if (_localName(dd.name) != 'dd') continue;
      final name = dd.getAttribute('flag')?.trim().isNotEmpty == true ? dd.getAttribute('flag')!.trim() : '默认线路';
      final episodes = _parseEpisodeBlock(dd.innerText.trim(), sourceUrl);
      if (episodes.isNotEmpty) result.add(VideoPlaySource(name: name, episodes: episodes));
    }
    return result;
  }

  List<VideoPlaySource> _parsePlaySourceBlocks(String fromText, String urlText, String sourceUrl) {
    final fromParts = fromText.split(r'$$$');
    final urlParts = urlText.split(r'$$$');
    final maxLen = math.max(fromParts.length, urlParts.length);
    final result = <VideoPlaySource>[];
    for (var i = 0; i < maxLen; i++) {
      final name = i < fromParts.length && fromParts[i].trim().isNotEmpty ? fromParts[i].trim() : '线路${i + 1}';
      final block = i < urlParts.length ? urlParts[i].trim() : '';
      final episodes = _parseEpisodeBlock(block, sourceUrl);
      if (episodes.isNotEmpty) result.add(VideoPlaySource(name: name, episodes: episodes));
    }
    return result;
  }

  List<VideoEpisode> _parseEpisodeBlock(String block, String sourceUrl) {
    if (block.trim().isEmpty) return const [];
    final result = <VideoEpisode>[];
    final seen = <String>{};
    for (final rawPart in block.split('#')) {
      final part = rawPart.trim();
      if (part.isEmpty) continue;
      String title = '', url = '';
      final dollarIndex = part.indexOf(r'$');
      if (dollarIndex > 0) {
        title = part.substring(0, dollarIndex).trim();
        url = part.substring(dollarIndex + 1).trim();
      } else {
        url = part;
        title = '第${result.length + 1}集';
      }
      url = _resolveUrl(sourceUrl, url);
      if (url.isEmpty) continue;
      if (!seen.add('$title|$url')) continue;
      result.add(VideoEpisode(title: title.isNotEmpty ? title : '第${result.length + 1}集', url: url, index: result.length));
    }
    return result;
  }

  List<_RequestTarget> _buildLatestTargets(_LicensedProvider provider, int page) => [
        _RequestTarget(name: 'videolist', url: _buildUri(provider.apiUrl, query: {'ac': 'videolist', 'pg': '$page'}), headers: _defaultRequestHeaders(provider)),
        _RequestTarget(name: 'list', url: _buildUri(provider.apiUrl, query: {'ac': 'list', 'pg': '$page'}), headers: _defaultRequestHeaders(provider)),
        _RequestTarget(name: 'detail', url: _buildUri(provider.apiUrl, query: {'ac': 'detail', 'pg': '$page'}), headers: _defaultRequestHeaders(provider)),
      ];

  List<_RequestTarget> _buildSearchTargets(_LicensedProvider provider, String keyword, int page) => [
        _RequestTarget(name: 'search-detail', url: _buildUri(provider.apiUrl, query: {'ac': 'detail', 'wd': keyword, 'pg': '$page'}), headers: _defaultRequestHeaders(provider)),
        _RequestTarget(name: 'search-videolist', url: _buildUri(provider.apiUrl, query: {'ac': 'videolist', 'wd': keyword, 'pg': '$page'}), headers: _defaultRequestHeaders(provider)),
      ];

  List<_RequestTarget> _buildCategoryTargets(_LicensedProvider provider, String categoryId, int page) => [
        _RequestTarget(name: 'category-videolist', url: _buildUri(provider.apiUrl, query: {'ac': 'videolist', 't': categoryId, 'pg': '$page'}), headers: _defaultRequestHeaders(provider)),
        _RequestTarget(name: 'category-list', url: _buildUri(provider.apiUrl, query: {'ac': 'list', 't': categoryId, 'pg': '$page'}), headers: _defaultRequestHeaders(provider)),
        _RequestTarget(name: 'category-detail', url: _buildUri(provider.apiUrl, query: {'ac': 'detail', 't': categoryId, 'pg': '$page'}), headers: _defaultRequestHeaders(provider)),
      ];

  List<_RequestTarget> _buildDetailTargets(_LicensedProvider provider, String id) => [
        _RequestTarget(name: 'detail-by-id', url: _buildUri(provider.apiUrl, query: {'ac': 'detail', 'ids': id}), headers: _defaultRequestHeaders(provider)),
      ];

  Map<String, String> _defaultRequestHeaders(_LicensedProvider provider) => {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
        'Accept': '*/*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Connection': 'keep-alive',
        ...provider.headers,
      };

  Uri _buildUri(String baseUrl, {Map<String, String>? query}) {
    final uri = Uri.parse(baseUrl);
    final merged = <String, String>{};
    merged.addAll(uri.queryParameters);
    if (query != null) merged.addAll(query);
    return uri.replace(queryParameters: merged);
  }

  _SemanticCategory _parseSemanticCategory(String raw) {
    switch (raw) {
      case '': case '1': case 'latest': case 'new': case 'home': case 'index': return _SemanticCategory.latest;
      case 'movie': case 'film': case 'type=movie': case 'type=film': return _SemanticCategory.movie;
      case 'tv': case 'drama': case 'series': case 'type=tv': return _SemanticCategory.tv;
      case 'anime': case 'cartoon': case 'type=anime': return _SemanticCategory.anime;
      case 'variety': case 'show': case 'type=variety': return _SemanticCategory.variety;
      case 'short': case 'short_drama': case 'shortdrama': case 'microdrama': case 'type=short': return _SemanticCategory.shortDrama;
      default: return _SemanticCategory.unknown;
    }
  }

  List<VideoItem> _dedupItems(List<VideoItem> raw) {
    final map = <String, VideoItem>{};
    for (final item in raw) {
      if (item.title.trim().isEmpty && item.id.trim().isEmpty) continue;
      final key = '${item.providerKey}|${item.id}|${item.detailUrl}';
      map.putIfAbsent(key, () => item);
    }
    return map.values.toList();
  }

  int _compareListItems(VideoItem a, VideoItem b) {
    final scoreCompare = _itemQualityScore(b).compareTo(_itemQualityScore(a));
    if (scoreCompare != 0) return scoreCompare;
    final yearCompare = b.yearText.compareTo(a.yearText);
    if (yearCompare != 0) return yearCompare;
    return a.title.compareTo(b.title);
  }

  int _itemQualityScore(VideoItem item) {
    var score = 0;
    if (item.cover.trim().isNotEmpty) score += 4;
    if (item.intro.trim().isNotEmpty) score += 3;
    if (item.category.trim().isNotEmpty) score += 2;
    if (item.yearText.trim().isNotEmpty) score += 1;
    if (item.remark.trim().isNotEmpty) score += 1;
    return score;
  }

  int _searchScore(VideoItem item, String keyword) {
    final title = _normalizeTitle(item.title);
    final kw = _normalizeTitle(keyword);
    var score = _itemQualityScore(item);
    if (title == kw) score += 100;
    if (title.startsWith(kw)) score += 40;
    if (title.contains(kw)) score += 20;
    if (item.remark.contains('完结') || item.remark.contains('全集')) score += 6;
    if (item.yearText.trim().isNotEmpty) score += 2;
    return score;
  }

  dynamic _tryJsonDecode(String text) {
    try { return jsonDecode(text); } catch (_) { return null; }
  }

  String _decodeResponseBody(http.Response response) {
    try { return utf8.decode(response.bodyBytes); } catch (_) { return response.body; }
  }

  String _pickString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  String _xmlChildText(XmlElement parent, List<String> names) {
    for (final name in names) {
      for (final child in parent.children.whereType<XmlElement>()) {
        if (_localName(child.name) == name) {
          final text = child.innerText.trim();
          if (text.isNotEmpty) return text;
        }
      }
    }
    for (final name in names) {
      for (final child in parent.descendants.whereType<XmlElement>()) {
        if (_localName(child.name) == name) {
          final text = child.innerText.trim();
          if (text.isNotEmpty) return text;
        }
      }
    }
    return '';
  }

  String _localName(XmlName name) {
    final local = name.local.trim();
    return local.isNotEmpty ? local : name.toString().trim();
  }

  // ============== 核心修复点：将 HTML 转义写成字符串拼接，极力避免各种平台的复制渲染变形 ==============
  String _cleanText(String input) {
    if (input.trim().isEmpty) return '';
    var text = input
        .replaceAll(RegExp(r'<!\[CDATA\[|\]\]>'), '')
        .replaceAll(RegExp(r'<[^>]+>'), ' ');
    
    text = text.replaceAll('&' 'nbsp;', ' ');
    text = text.replaceAll('&' 'amp;', '&');
    text = text.replaceAll('&' 'lt;', '<');
    text = text.replaceAll('&' 'gt;', '>');
    text = text.replaceAll('&' 'quot;', '"');
    text = text.replaceAll('&' '#39;', "'"); // 原来这里直接写了普通的转义代码，结果被浏览器视图吞并了，导致解析大爆炸报错！
    
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  List<String> _splitTags(String raw) => raw.split(RegExp(r'[,，/\s]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  String _joinNonEmpty(List<String> values, {String separator = ' '}) => values.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().join(separator);

  String _normalizeTitle(String input) => input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r'[【】\[\]\(\)（）《》·\-_.:,，。：；!！?？]'), '');

  bool _looksLikeHttpUrl(String input) {
    final uri = Uri.tryParse(input.trim());
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  String _normalizeApiUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return '';
    if (url.startsWith('//')) url = 'https:$url';
    if (!_looksLikeHttpUrl(url)) return '';
    return url;
  }

  String _resolveUrl(String base, String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    if (_looksLikeHttpUrl(value)) return value;
    if (value.startsWith('//')) return 'https:$value';
    final baseUri = Uri.tryParse(base);
    if (baseUri == null) return value;
    try { return baseUri.resolve(value).toString(); } catch (_) { return value; }
  }

  String _guessProviderName(String apiUrl) {
    final uri = Uri.tryParse(apiUrl);
    if (uri == null || uri.host.trim().isEmpty) return '未知站点';
    final host = uri.host;
    final segments = host.split('.');
    if (segments.length >= 2) return segments[segments.length - 2];
    return host;
  }

  String _siteUrlFromApi(String apiUrl) {
    final uri = Uri.tryParse(apiUrl);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) return '';
    return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}/';
  }

  String _stableKey(String input) => base64Url.encode(utf8.encode(input)).replaceAll('=', '').substring(0, math.min(16, base64Url.encode(utf8.encode(input)).replaceAll('=', '').length));

  String _normalizeHeaderKey(String key) {
    switch (key.trim().toLowerCase()) {
      case 'user-agent': return 'User-Agent';
      case 'referer': return 'Referer';
      case 'origin': return 'Origin';
      case 'accept': return 'Accept';
      case 'accept-language': return 'Accept-Language';
      case 'cookie': return 'Cookie';
      case 'connection': return 'Connection';
      default: return key.trim();
    }
  }
}

enum _SemanticCategory { latest, movie, tv, anime, variety, shortDrama, unknown }

class _LicensedProvider {
  final String key;
  final String name;
  final String apiUrl;
  final String siteUrl;
  final Map<String, String> headers;
  final String catalogUrl;
  const _LicensedProvider({required this.key, required this.name, required this.apiUrl, required this.siteUrl, required this.headers, required this.catalogUrl});
}

class _ProviderClass {
  final String id;
  final String name;
  const _ProviderClass({required this.id, required this.name});
}

class _ProviderStats {
  int successCount = 0;
  int failureCount = 0;
  double averageLatencyMs = 0;
  DateTime? cooldownUntil;
}

class _RequestTarget {
  final String name;
  final Uri url;
  final Map<String, String> headers;
  const _RequestTarget({required this.name, required this.url, required this.headers});
}

class _ParsedFeed {
  final List<VideoItem> items;
  final VideoDetail? detail;
  final List<_ProviderClass> classes;
  final String sourceUrl;
  const _ParsedFeed({required this.items, required this.detail, required this.classes, required this.sourceUrl});
}
