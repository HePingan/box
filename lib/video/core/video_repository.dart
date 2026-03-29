import '../../novel/core/cache_store.dart';
import 'models.dart';
import 'video_source.dart';

class VideoRepository {
  VideoRepository({
    required this.source,
    required this.cache,
  });

  final VideoSource source;
  final CacheStore cache;

  static const String _recentItemsKey = 'video_recent_items';

  String _detailKey(String videoId) => 'video_detail_$videoId';
  String _progressKey(String videoId) => 'video_progress_$videoId';

  Future<List<VideoItem>> searchVideos(String keyword, {int page = 1}) {
    return source.searchVideos(keyword, page: page);
  }

  Future<List<VideoItem>> fetchByPath(String path, {int page = 1}) {
    return source.fetchByPath(path, page: page);
  }

  Future<VideoDetail> fetchDetail({
    required VideoItem item,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && item.id.isNotEmpty) {
      final cached = await cache.read(_detailKey(item.id));
      if (cached is Map) {
        final detail = VideoDetail.fromJson(Map<String, dynamic>.from(cached));
        await saveRecentItem(detail.item);
        return detail;
      }
    }

    final detail = await source.fetchDetail(
      videoId: item.id,
      detailUrl: item.detailUrl,
    );

    if (detail.item.id.isNotEmpty) {
      await cache.write(
        _detailKey(detail.item.id),
        detail.toJson(),
        ttl: const Duration(hours: 6),
      );
    }

    await saveRecentItem(detail.item);
    return detail;
  }

  Future<void> saveRecentItem(VideoItem item) async {
    if (item.id.trim().isEmpty) return;

    final raw = await cache.read(_recentItemsKey);
    final list = <VideoItem>[];

    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          list.add(VideoItem.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }

    list.removeWhere((e) => e.id == item.id);
    list.insert(0, item);

    if (list.length > 20) {
      list.removeRange(20, list.length);
    }

    await cache.write(
      _recentItemsKey,
      list.map((e) => e.toJson()).toList(),
    );
  }

  Future<List<VideoItem>> getRecentItems() async {
    final raw = await cache.read(_recentItemsKey);
    if (raw is! List) return const [];

    return raw
        .whereType<Map>()
        .map((e) => VideoItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> saveProgress(VideoPlaybackProgress progress) async {
    if (progress.videoId.trim().isEmpty) return;
    await cache.write(_progressKey(progress.videoId), progress.toJson());
  }

  Future<VideoPlaybackProgress?> getProgress(String videoId) async {
    if (videoId.trim().isEmpty) return null;

    final raw = await cache.read(_progressKey(videoId));
    if (raw is! Map) return null;

    return VideoPlaybackProgress.fromJson(Map<String, dynamic>.from(raw));
  }
}