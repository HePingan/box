import 'cache_store.dart';
import 'models.dart';
import 'novel_cache_keys.dart';
import 'novel_source.dart';

class NovelRepository {
  NovelRepository({
    required this.source,
    required this.cache,
  });

  final NovelSource source;
  final CacheStore cache;

  static const Duration _searchTtl = Duration(minutes: 10);
  static const Duration _pathListTtl = Duration(minutes: 8);
  static const Duration _detailTtl = Duration(hours: 8);
  static const Duration _chapterTtl = Duration(days: 30);

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

    if (!forceRefresh) {
      final cached = _decodeBooks(await cache.read(key));
      if (cached != null) return cached;
    }

    try {
      final books = await source.searchBooks(keyword, page: page);
      await cache.write(
        key,
        books.map((e) => e.toJson()).toList(),
        ttl: _searchTtl,
      );
      return books;
    } catch (_) {
      final cached = _decodeBooks(await cache.read(key));
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<List<NovelBook>> fetchByPath(
    String path, {
    bool forceRefresh = false,
  }) async {
    final key = NovelCacheKeys.path(path);

    if (!forceRefresh) {
      final cached = _decodeBooks(await cache.read(key));
      if (cached != null) return cached;
    }

    try {
      final books = await source.fetchByPath(path);
      await cache.write(
        key,
        books.map((e) => e.toJson()).toList(),
        ttl: _pathListTtl,
      );
      return books;
    } catch (_) {
      final cached = _decodeBooks(await cache.read(key));
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<NovelDetail> fetchDetail({
    required String bookId,
    String? detailUrl,
    bool forceRefresh = false,
  }) async {
    final key = NovelCacheKeys.detail(
      bookId: bookId,
      detailUrl: detailUrl,
    );

    if (!forceRefresh) {
      final cached = _decodeDetail(await cache.read(key));
      if (cached != null) return cached;
    }

    try {
      final detail = await source.fetchDetail(
        bookId: bookId,
        detailUrl: detailUrl,
      );

      await cache.write(key, detail.toJson(), ttl: _detailTtl);
      return detail;
    } catch (_) {
      final cached = _decodeDetail(await cache.read(key));
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<ChapterContent> fetchChapter({
    required NovelDetail detail,
    required int chapterIndex,
    bool forceRefresh = false,
  }) async {
    final chapter = detail.chapters[chapterIndex];
    final key = NovelCacheKeys.chapter(chapter.url);

    if (!forceRefresh) {
      final cached = _decodeChapter(await cache.read(key));
      if (cached != null) return cached;
    }

    try {
      final chapterContent = await source.fetchChapter(
        detail: detail,
        chapterIndex: chapterIndex,
      );

      await cache.write(key, chapterContent.toJson(), ttl: _chapterTtl);
      return chapterContent;
    } catch (_) {
      final cached = _decodeChapter(await cache.read(key));
      if (cached != null) return cached;
      rethrow;
    }
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
    await cache.write(
      NovelCacheKeys.readerSettings,
      settings.toJson(),
    );
  }

  Future<ReaderSettings> getReaderSettings() async {
    final data = await cache.read(NovelCacheKeys.readerSettings);
    if (data is Map) {
      return ReaderSettings.fromJson(Map<String, dynamic>.from(data));
    }
    return const ReaderSettings();
  }
}