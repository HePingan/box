import '../novel/core/cache_store.dart';
import 'core/archive_video_source.dart';
import 'core/composite_video_source.dart';
import 'core/licensed_catalog_video_source.dart';
import 'core/models.dart';
import 'core/sample_video_source.dart';
import 'core/video_repository.dart';
import 'core/video_source.dart';

class VideoModule {
  static VideoRepository? _repository;

  static VideoRepository get repository {
    _repository ??= VideoRepository(
      source: const _UnconfiguredVideoSource(),
      cache: CacheStore(namespace: 'video_module'),
    );
    return _repository!;
  }

  static bool get isConfigured =>
      _repository != null && _repository!.source is! _UnconfiguredVideoSource;

  static void configure({
    required VideoSource source,
    CacheStore? cache,
  }) {
    _repository = VideoRepository(
      source: source,
      cache: cache ?? CacheStore(namespace: 'video_module'),
    );
  }

  static void configureMultiSource({
    required List<VideoSource> sources,
    CacheStore? cache,
    String sourceName = '聚合影视源',
  }) {
    configure(
      source: CompositeVideoSource(
        sources: sources,
        displayName: sourceName,
      ),
      cache: cache,
    );
  }

  static void configureLicensedCatalogSource({
    required List<String> catalogUrls,
    CacheStore? cache,
    String catalogName = '授权影视源',
  }) {
    configure(
      source: CompositeVideoSource(
        displayName: catalogName,
        sources: [
          LicensedCatalogVideoSource(
            catalogUrls: catalogUrls,
            catalogName: catalogName,
          ),
        ],
      ),
      cache: cache,
    );
  }

  static void configurePublicVideoSource({CacheStore? cache}) {
    const rawUrls = String.fromEnvironment('LICENSED_VIDEO_CATALOG_URLS');
    final urls = rawUrls
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final sources = <VideoSource>[
      if (urls.isNotEmpty)
        LicensedCatalogVideoSource(
          catalogUrls: urls,
          catalogName: '聚合影视源',
        ),
      ArchiveVideoSource(),
      const SampleVideoSource(),
    ];

    if (sources.isEmpty) {
      configure(
        source: const _UnconfiguredVideoSource(
          message:
              '未配置授权视频目录源。请调用 VideoModule.configureLicensedCatalogSource(...)，或使用 --dart-define=LICENSED_VIDEO_CATALOG_URLS=url1,url2',
        ),
        cache: cache,
      );
      return;
    }

    configure(
      source: CompositeVideoSource(
        displayName: urls.isNotEmpty ? '聚合影视源' : '公共影视源',
        sources: sources,
      ),
      cache: cache,
    );
  }

  static void resetForTest() {
    _repository = null;
  }
}

class _UnconfiguredVideoSource implements VideoSource {
  final String message;

  const _UnconfiguredVideoSource({
    this.message =
        'VideoModule 未配置。请先调用 VideoModule.configureLicensedCatalogSource(...)',
  });

  StateError _err() => StateError(message);

  @override
  String get sourceName => 'unconfigured';

  @override
  List<VideoCategory> get categories => const [];

  @override
  Future<List<VideoItem>> searchVideos(String keyword, {int page = 1}) {
    return Future.error(_err());
  }

  @override
  Future<List<VideoItem>> fetchByPath(String path, {int page = 1}) {
    return Future.error(_err());
  }

  @override
  Future<VideoDetail> fetchDetail({
    required VideoItem item,
  }) {
    return Future.error(_err());
  }
}