import 'core/cache_store.dart';
import 'core/html_novel_source.dart';
import 'core/models.dart';
import 'core/novel_repository.dart';
import 'core/novel_source.dart';
import 'core/qm_novel_source.dart';
import 'core/source_rules.dart';

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

  static void configure({
    required NovelSource source,
    CacheStore? cache,
  }) {
    _repository = NovelRepository(
      source: source,
      cache: cache ?? CacheStore(namespace: 'novel_module'),
    );
  }

  static void configureQimao({
    required String baseUrl,
    Map<String, String>? headers,
    CacheStore? cache,
  }) {
    configure(
      source: QmNovelSource(
        baseUrl: baseUrl,
        headers: headers,
      ),
      cache: cache,
    );
  }

  static void configureHtml({
    required String baseUrl,
    required SourceRules rules,
    Map<String, String>? headers,
    CacheStore? cache,
  }) {
    configure(
      source: HtmlNovelSource(
        baseUrl: baseUrl,
        rules: rules,
        headers: headers,
      ),
      cache: cache,
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
      'NovelModule 未配置，请先调用 NovelModule.configure...',
    );
  }

  @override
  Future<List<NovelBook>> searchBooks(String keyword, {int page = 1}) => Future.error(_error());

  @override
  Future<List<NovelBook>> fetchByPath(String path) => Future.error(_error());

  @override
  Future<NovelDetail> fetchDetail({required String bookId, String? detailUrl}) => Future.error(_error());

  @override
  Future<ChapterContent> fetchChapter({required NovelDetail detail, required int chapterIndex}) => Future.error(_error());
}