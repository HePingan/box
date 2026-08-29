import 'package:box/core/storage/cache_store.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'core/bookshelf_manager.dart';
import 'core/models.dart';
import 'core/novel_repository.dart';
import 'core/novel_source.dart';
import 'core/novel_source_factory.dart';

// ===================== Novel 模块公共 API =====================
// 外部（features/app）只应通过本 barrel 依赖 novel 模块，
// 不要再深路径 import novel/pages/... 或 novel/controllers/...。
// 这样 novel 内部页面/控制器可自由重构而不波及调用方。
export 'core/novel_source_factory.dart' show NovelSourceFactory;
export 'controllers/novel_detail_controller.dart' show NovelDetailController;
export 'pages/novel_detail_page.dart' show NovelDetailPage;
export 'pages/novel_list_page.dart'
    show NovelListPage, NovelListPageWithProvider;
export 'pages/source_manager/book_source_bootstrap.dart'
    show BookSourceBootstrap, BookSourceBootstrapResult;
export 'pages/source_manager/book_source_manager.dart' show BookSourceManager;
export 'pages/source_manager/book_source_manager_page.dart'
    show BookSourceManagerPage;
export 'pages/source_manager/book_source_diagnostic_page.dart'
    show BookSourceDiagnosticPage;
export 'pages/source_manager/book_source_model.dart' show BookSourceModel;

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

  /// 直接注入一个 repository（仅测试用）。
  ///
  /// [configureRuleSource] 只能从书源 JSON 经 factory 造 source，无法塞入假 source，
  /// 于是 controller/页面层一直没法在无网络环境下测——这也是 pages/ 与 controllers/
  /// 长期零测试覆盖的直接原因。这个入口专门补上它。
  @visibleForTesting
  static void injectRepositoryForTest(NovelRepository repository) {
    _repository = repository;
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
