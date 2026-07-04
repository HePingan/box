import 'core/cache_store.dart';
import 'core/bookshelf_manager.dart';
import 'core/models.dart';
import 'core/novel_repository.dart';
import 'core/novel_source.dart';
import 'core/novel_source_factory.dart';

class NovelModule {
  static NovelRepository? _repository;

  static bool get isConfigured =>
      _repository != null && _repository!.source is! _UnconfiguredSource;

  static NovelRepository get repository {
    _repository ??= NovelRepository(
      source: const _UnconfiguredSource(),
      cache: CacheStore(namespace: 'novel_module'),
    );
    return _repository!;
  }

  static BookshelfManager get bookshelf => BookshelfManager.instance;

  /// 仅保留：规则书源 JSON 配置
  static void configureRuleSource({
    required Map<String, dynamic> bookSourceJson,
    CacheStore? cache,
    Duration? searchTtl,
    Duration? pathListTtl,
    Duration? detailTtl,
    Duration? chapterTtl,
  }) {
    _repository = NovelRepository(
      source: NovelSourceFactory.fromBookSourceJson(bookSourceJson),
      cache: cache ?? CacheStore(namespace: 'novel_module'),
      searchTtl: searchTtl ?? NovelRepository.defaultSearchTtl,
      pathListTtl: pathListTtl ?? NovelRepository.defaultPathListTtl,
      detailTtl: detailTtl ?? NovelRepository.defaultDetailTtl,
      chapterTtl: chapterTtl ?? NovelRepository.defaultChapterTtl,
    );
  }

  static void resetForTest() {
    _repository = null;
  }
}

class _UnconfiguredSource implements NovelSource {
  const _UnconfiguredSource();

  Never _error() {
    throw StateError(
      'NovelModule 未配置，请先调用 NovelModule.configureRuleSource(...)',
    );
  }

  @override
  Future<List<NovelBook>> searchBooks(String keyword, {int page = 1}) =>
      Future.error(_error());

  @override
  Future<List<NovelBook>> fetchByPath(String path) => Future.error(_error());

  @override
  Future<NovelDetail> fetchDetail({
    required String bookId,
    String? detailUrl,
  }) => Future.error(_error());

  @override
  Future<ChapterContent> fetchChapter({
    required NovelDetail detail,
    required int chapterIndex,
  }) => Future.error(_error());
}
