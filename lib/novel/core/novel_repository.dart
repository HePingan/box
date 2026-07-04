import 'cache_store.dart';
import 'models.dart';
import 'novel_cache_keys.dart';
import 'novel_exceptions.dart';
import 'novel_source.dart';

class NovelRepository {
  NovelRepository({
    required this.source,
    required this.cache,
    this.searchTtl = defaultSearchTtl,
    this.pathListTtl = defaultPathListTtl,
    this.detailTtl = defaultDetailTtl,
    this.chapterTtl = defaultChapterTtl,
  });

  final NovelSource source;
  final CacheStore cache;

  /// 缓存策略配置
  static const Duration defaultSearchTtl = Duration(minutes: 10);
  static const Duration defaultPathListTtl = Duration(minutes: 8);
  static const Duration defaultDetailTtl = Duration(hours: 8);
  static const Duration defaultChapterTtl = Duration(days: 30);

  final Duration searchTtl;
  final Duration pathListTtl;
  final Duration detailTtl;
  final Duration chapterTtl;

  /// 通用缓存模板方法：读缓存 → 数据源 → 写缓存 → 异常回退缓存
  Future<T> _withCache<T>({
    required String key,
    required Duration ttl,
    required bool forceRefresh,
    required T? Function(dynamic) decoder,
    required Future<T> Function() source,
    required dynamic Function(T) encoder,
    bool Function(T)? validate,
  }) async {
    if (!forceRefresh) {
      final cached = decoder(await cache.read(key));
      if (cached != null && (validate == null || validate(cached))) {
        return cached;
      }
    }

    try {
      final result = await source();
      await cache.write(key, encoder(result), ttl: ttl);
      return result;
    } catch (_) {
      final cached = decoder(await cache.read(key));
      if (cached != null && (validate == null || validate(cached))) {
        return cached;
      }
      rethrow;
    }
  }

  List<NovelBook>? _decodeBooks(dynamic cached) {
    if (cached is! List) return null;

    try {
      return cached
          .whereType<Map>()
          .map((e) => NovelBook.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  NovelDetail? _decodeDetail(dynamic cached) {
    if (cached is! Map) return null;

    try {
      return NovelDetail.fromJson(Map<String, dynamic>.from(cached));
    } catch (_) {
      return null;
    }
  }

  ChapterContent? _decodeChapter(dynamic cached) {
    if (cached is! Map) return null;

    try {
      return ChapterContent.fromJson(
        Map<String, dynamic>.from(cached),
        fromCache: true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<NovelBook>> searchBooks(
    String keyword, {
    int page = 1,
    bool forceRefresh = false,
  }) async {
    final key = NovelCacheKeys.search(keyword, page);
    return _withCache(
      key: key,
      ttl: searchTtl,
      forceRefresh: forceRefresh,
      decoder: _decodeBooks,
      encoder: (books) => books.map((e) => e.toJson()).toList(),
      source: () => source.searchBooks(keyword, page: page),
    );
  }

  Future<List<NovelBook>> fetchByPath(
    String path, {
    bool forceRefresh = false,
  }) async {
    final key = NovelCacheKeys.path(path);
    return _withCache(
      key: key,
      ttl: pathListTtl,
      forceRefresh: forceRefresh,
      decoder: _decodeBooks,
      encoder: (books) => books.map((e) => e.toJson()).toList(),
      source: () => source.fetchByPath(path),
    );
  }

  Future<NovelDetail> fetchDetail({
    required String bookId,
    String? detailUrl,
    bool forceRefresh = false,
  }) async {
    final key = NovelCacheKeys.detail(bookId: bookId, detailUrl: detailUrl);
    return _withCache(
      key: key,
      ttl: detailTtl,
      forceRefresh: forceRefresh,
      decoder: _decodeDetail,
      encoder: (detail) => detail.toJson(),
      source: () => source.fetchDetail(bookId: bookId, detailUrl: detailUrl),
      validate: (detail) => detail.chapters.isNotEmpty,
    );
  }

  Future<ChapterContent> fetchChapter({
    required NovelDetail detail,
    required int chapterIndex,
    bool forceRefresh = false,
  }) async {
    if (chapterIndex < 0 || chapterIndex >= detail.chapters.length) {
      throw NovelSourceException(
        '章节索引越界: $chapterIndex (共 ${detail.chapters.length} 章)',
      );
    }
    final chapter = detail.chapters[chapterIndex];
    final key = NovelCacheKeys.chapter(chapter.url);
    return _withCache(
      key: key,
      ttl: chapterTtl,
      forceRefresh: forceRefresh,
      decoder: _decodeChapter,
      encoder: (content) => content.toJson(),
      source: () =>
          source.fetchChapter(detail: detail, chapterIndex: chapterIndex),
    );
  }

  Future<void> prefetchChapter({
    required NovelDetail detail,
    required int chapterIndex,
  }) async {
    if (chapterIndex < 0 || chapterIndex >= detail.chapters.length) return;

    await fetchChapter(
      detail: detail,
      chapterIndex: chapterIndex,
      forceRefresh: false,
    );
  }

  Future<void> saveProgress(ReadingProgress progress) async {
    await cache.write(
      NovelCacheKeys.progress(progress.bookId),
      progress.toJson(),
    );
  }

  Future<ReadingProgress?> getProgress(String bookId) async {
    final data = await cache.read(NovelCacheKeys.progress(bookId));
    if (data is Map) {
      return ReadingProgress.fromJson(Map<String, dynamic>.from(data));
    }
    return null;
  }

  Future<void> saveReaderSettings(ReaderSettings settings) async {
    await cache.write(NovelCacheKeys.readerSettings, settings.toJson());
  }

  Future<ReaderSettings> getReaderSettings() async {
    final data = await cache.read(NovelCacheKeys.readerSettings);
    if (data is Map) {
      return ReaderSettings.fromJson(Map<String, dynamic>.from(data));
    }
    return const ReaderSettings();
  }
}
