import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../novel/core/cache_store.dart';
import 'models.dart';
import 'video_source.dart';

class VideoRepository {
  VideoRepository({
    required VideoSource source,
    CacheStore? cache,
  })  : _source = source,
        _cache = cache;

  final VideoSource _source;
  final CacheStore? _cache;

  final Map<String, VideoDetail> _detailMemoryCache = <String, VideoDetail>{};

  SharedPreferences? _prefs;

  VideoSource get source => _source;

  CacheStore? get cache => _cache;

  Future<SharedPreferences> get _prefsInstance async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  String _detailCacheKey(VideoItem item) {
    return '${item.providerKey}|${item.id}|${item.detailUrl}';
  }

  String _recentIdentity(VideoItem item) {
    if (item.id.trim().isNotEmpty) return item.id.trim();
    return '${item.providerKey}|${item.detailUrl}|${item.title}';
  }

  Future<List<VideoItem>> searchVideos(String keyword, {int page = 1}) {
    return _source.searchVideos(keyword, page: page);
  }

  Future<List<VideoItem>> fetchByPath(String path, {int page = 1}) {
    return _source.fetchByPath(path, page: page);
  }

  Future<VideoDetail> fetchDetail({
    required VideoItem item,
    bool forceRefresh = false,
  }) async {
    final cacheKey = _detailCacheKey(item);

    if (!forceRefresh) {
      final cached = _detailMemoryCache[cacheKey];
      if (cached != null) {
        await saveRecentItem(cached.item);
        return cached;
      }
    }

    final detail = await _source.fetchDetail(item: item);
    _detailMemoryCache[cacheKey] = detail;
    await saveRecentItem(detail.item);
    return detail;
  }

  void clearDetailMemoryCache() {
    _detailMemoryCache.clear();
  }

  Future<void> clearDetailMemoryCacheByItem(VideoItem item) async {
    _detailMemoryCache.remove(_detailCacheKey(item));
  }

  Future<List<VideoItem>> getRecentItems() async {
    final prefs = await _prefsInstance;
    final rawList = prefs.getStringList('video_recent_items') ?? const [];

    final result = <VideoItem>[];
    for (final raw in rawList) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          result.add(VideoItem.fromJson(decoded));
        } else if (decoded is Map) {
          result.add(VideoItem.fromJson(Map<String, dynamic>.from(decoded)));
        }
      } catch (_) {}
    }
    return result;
  }

  Future<void> saveRecentItem(VideoItem item) async {
    final prefs = await _prefsInstance;
    final current = await getRecentItems();

    final identity = _recentIdentity(item);
    final next = <VideoItem>[
      item,
      ...current.where((e) => _recentIdentity(e) != identity),
    ];

    final limited = next.take(30).toList();
    final encoded = limited.map((e) => jsonEncode(e.toJson())).toList();

    await prefs.setStringList('video_recent_items', encoded);
  }

  Future<void> clearRecentItems() async {
    final prefs = await _prefsInstance;
    await prefs.remove('video_recent_items');
  }

  Future<VideoPlaybackProgress?> getProgress(String videoId) async {
    final prefs = await _prefsInstance;
    final raw = prefs.getString('video_progress_$videoId');
    return VideoPlaybackProgress.tryDecode(raw);
  }

  Future<void> saveProgress(VideoPlaybackProgress progress) async {
    final prefs = await _prefsInstance;
    await prefs.setString(
      'video_progress_${progress.videoId}',
      progress.encode(),
    );
  }

  Future<void> clearProgress(String videoId) async {
    final prefs = await _prefsInstance;
    await prefs.remove('video_progress_$videoId');
  }
}