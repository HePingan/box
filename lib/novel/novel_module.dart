import 'core/cache_store.dart';
import 'core/models.dart';
import 'core/novel_repository.dart';
import 'core/novel_source.dart';
import 'core/qm_novel_source.dart';

class NovelModule {
  static NovelRepository? _repository;

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
}

class _UnconfiguredSource implements NovelSource {
  const _UnconfiguredSource();

  @override
  Future<List<NovelBook>> searchBooks(String keyword, {int page = 1}) {
    return Future.error(
      StateError('NovelModule 未配置，请在 main() 先调用 NovelModule.configureQimao(...)'),
    );
  }

  @override
  Future<List<NovelBook>> fetchByPath(String path) {
    return Future.error(
      StateError('NovelModule 未配置，请在 main() 先调用 NovelModule.configureQimao(...)'),
    );
  }

  @override
  Future<NovelDetail> fetchDetail({
    required String bookId,
    String? detailUrl,
  }) {
    return Future.error(
      StateError('NovelModule 未配置，请在 main() 先调用 NovelModule.configureQimao(...)'),
    );
  }

  @override
  Future<ChapterContent> fetchChapter({
    required NovelDetail detail,
    required int chapterIndex,
  }) {
    return Future.error(
      StateError('NovelModule 未配置，请在 main() 先调用 NovelModule.configureQimao(...)'),
    );
  }
}