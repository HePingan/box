import 'archive_video_source.dart';
import 'models.dart';
import 'sample_video_source.dart';
import 'video_source.dart';

class CompositeVideoSource implements VideoSource {
  CompositeVideoSource({
    required this.archive,
    required this.sample,
  });

  final ArchiveVideoSource archive;
  final SampleVideoSource sample;

  @override
  String get sourceName => '${archive.sourceName} + ${sample.sourceName}';

  @override
  List<VideoCategory> get categories {
    final map = <String, VideoCategory>{};
    for (final c in [...archive.categories, ...sample.categories]) {
      map[c.id] = c;
    }
    return map.values.toList();
  }

  @override
  Future<List<VideoItem>> searchVideos(String keyword, {int page = 1}) async {
    try {
      final list = await archive.searchVideos(keyword, page: page);
      if (list.isNotEmpty) return list;
    } catch (_) {}
    return sample.searchVideos(keyword, page: page);
  }

  @override
  Future<List<VideoItem>> fetchByPath(String path, {int page = 1}) async {
    final lower = path.trim().toLowerCase();
    if (lower.contains('sample') || lower.contains('示例')) {
      return sample.fetchByPath(path, page: page);
    }

    try {
      final list = await archive.fetchByPath(path, page: page);
      if (list.isNotEmpty) return list;
    } catch (_) {}

    return sample.fetchByPath(path, page: page);
  }

  @override
  Future<VideoDetail> fetchDetail({
    required String videoId,
    String? detailUrl,
  }) async {
    final lowerId = videoId.toLowerCase();
    final lowerUrl = (detailUrl ?? '').toLowerCase();

    if (lowerId.startsWith('sample_') ||
        lowerUrl.contains('gtv-videos-bucket') ||
        lowerUrl.contains('/sample/')) {
      return sample.fetchDetail(videoId: videoId, detailUrl: detailUrl);
    }

    try {
      return await archive.fetchDetail(videoId: videoId, detailUrl: detailUrl);
    } catch (_) {
      return sample.fetchDetail(videoId: videoId, detailUrl: detailUrl);
    }
  }
}