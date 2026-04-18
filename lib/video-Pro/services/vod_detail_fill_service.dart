import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../utils/app_logger.dart';
import '../models/video_source.dart';
import '../models/vod_item.dart';
import 'video_api_service.dart';

class VodDetailFillService {
  VodDetailFillService._();

  static final VodDetailFillService instance = VodDetailFillService._();

  static const Duration _timeout = Duration(seconds: 20);
  static const int _maxCacheSize = 100;

  final LinkedHashMap<String, VodItem> _cache = LinkedHashMap<String, VodItem>();
  final Map<String, Future<VodItem?>> _inFlight = <String, Future<VodItem?>>{};

  void _log(String message) {
    if (kDebugMode) {
      AppLogger.instance.log(message, tag: 'DETAIL_FILL');
    }
  }

  String _sourceKey(VideoSource source) {
    final id = source.id.toString().trim();
    if (id.isNotEmpty && id != 'null') return 'id:$id';

    final detailUrl = source.detailUrl.trim();
    if (detailUrl.isNotEmpty) return 'detail:$detailUrl';

    final url = source.url.trim();
    if (url.isNotEmpty) return 'url:$url';

    return 'name:${source.name.trim()}';
  }

  String _key(VideoSource source, int vodId) {
    return '${_sourceKey(source)}#$vodId';
  }

  String _requestBaseUrl(VideoSource source) {
    final detail = source.detailUrl.trim();
    if (detail.isNotEmpty) return detail;
    return source.url.trim();
  }

  bool _hasText(String? value) {
    if (value == null) return false;
    final text = value.trim();
    return text.isNotEmpty && text.toLowerCase() != 'null';
  }

  String? _pickText(String? preferred, String? fallback) {
    if (_hasText(preferred)) return preferred!.trim();
    if (_hasText(fallback)) return fallback!.trim();
    return null;
  }

  VodItem _mergeItems(VodItem base, VodItem detail) {
    return base.copyWith(
      vodName: _pickText(detail.vodName, base.vodName) ?? base.vodName,
      vodPic: _pickText(detail.vodPic, base.vodPic),
      vodRemarks: _pickText(detail.vodRemarks, base.vodRemarks),
      vodTime: _pickText(detail.vodTime, base.vodTime),
      vodYear: _pickText(detail.vodYear, base.vodYear),
      vodArea: _pickText(detail.vodArea, base.vodArea),
      vodLang: _pickText(detail.vodLang, base.vodLang),
      vodDirector: _pickText(detail.vodDirector, base.vodDirector),
      vodActor: _pickText(detail.vodActor, base.vodActor),
      vodContent: _pickText(detail.vodContent, base.vodContent),
      typeName: _pickText(detail.typeName, base.typeName),
      vodPlayFrom: _pickText(detail.vodPlayFrom, base.vodPlayFrom),
      vodPlayUrl: _pickText(detail.vodPlayUrl, base.vodPlayUrl),
      typeId: detail.typeId != 0 ? detail.typeId : base.typeId,
    );
  }

  void _trimCache() {
    while (_cache.length > _maxCacheSize) {
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
    }
  }

  /// 详情补图 / 补全详情
  ///
  /// - 如果传入 baseItem 且已经有封面，直接返回
  /// - 如果缓存命中，直接返回缓存
  /// - 如果正在请求同一个条目，复用同一个 Future
  Future<VodItem?> fill({
    required VideoSource source,
    required int vodId,
    VodItem? baseItem,
    bool forceRefresh = false,
  }) async {
    final key = _key(source, vodId);

    if (!forceRefresh && baseItem != null && _hasText(baseItem.vodPic)) {
      _log('[fill] skip, baseItem already has cover key=$key');
      return baseItem;
    }

    if (!forceRefresh && baseItem == null) {
      final cached = _cache[key];
      if (cached != null) {
        _log('[fill] cache hit key=$key cover=${cached.vodPic}');
        return cached;
      }
    }

    final pending = _inFlight[key];
    if (pending != null) {
      _log('[fill] join in-flight key=$key');
      final joined = await pending;
      if (joined != null) return joined;
      return baseItem;
    }

    final future = _loadAndMerge(
      source: source,
      vodId: vodId,
      baseItem: baseItem,
      key: key,
    );

    _inFlight[key] = future;

    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<VodItem?> _loadAndMerge({
    required VideoSource source,
    required int vodId,
    required VodItem? baseItem,
    required String key,
  }) async {
    final baseUrl = _requestBaseUrl(source);
    if (baseUrl.isEmpty || vodId <= 0) {
      _log(
        '[loadAndMerge] skip invalid baseUrl or vodId '
        'key=$key baseUrl=$baseUrl vodId=$vodId',
      );
      return baseItem;
    }

    try {
      _log(
        '[loadAndMerge] start key=$key '
        'baseUrl=$baseUrl vodId=$vodId',
      );

      final detail = await VideoApiService.fetchDetail(baseUrl, vodId)
          .timeout(_timeout);

      if (detail == null) {
        _log('[loadAndMerge] detail null key=$key');
        if (baseItem != null) {
          _cache[key] = baseItem;
          _trimCache();
        }
        return baseItem;
      }

      final merged = baseItem == null ? detail : _mergeItems(baseItem, detail);

      _cache[key] = merged;
      _trimCache();

      _log(
        '[loadAndMerge] done key=$key '
        'vodId=${merged.vodId} '
        'vodName=${merged.vodName} '
        'vodPic=${merged.vodPic ?? "null"}',
      );

      return merged;
    } catch (e, st) {
      AppLogger.instance.logError(e, st, 'DETAIL_FILL');
      _log('[loadAndMerge] failed key=$key error=$e');

      if (baseItem != null) {
        _cache[key] = baseItem;
        _trimCache();
      }

      return baseItem;
    }
  }

  void clearCache() {
    _cache.clear();
    _log('[clearCache] cleared');
  }

  void clearItem(VideoSource source, int vodId) {
    final key = _key(source, vodId);
    _cache.remove(key);
    _log('[clearItem] removed key=$key');
  }

  int get cacheSize => _cache.length;
}