import 'package:flutter/foundation.dart';
import '../core/models.dart';
import '../core/novel_exceptions.dart';
import '../novel_module.dart';

class NovelDetailController extends ChangeNotifier {
  final NovelBook entryBook;

  bool _loading = true;
  String _error = '';
  bool _reverse = false;
  bool _inBookshelf = false;

  NovelDetail? _detail;
  ReadingProgress? _progress;

  bool _isCaching = false;
  bool _cancelCache = false;
  int _cacheCurrent = 0;
  int _cacheTotal = 0;

  NovelDetailController({required this.entryBook}) {
    _load(forceRefresh: false);
    _checkInBookshelf();
  }

  // Getters
  bool get loading => _loading;
  String get error => _error;
  bool get reverse => _reverse;
  bool get inBookshelf => _inBookshelf;
  NovelDetail? get detail => _detail;
  ReadingProgress? get progress => _progress;
  bool get isCaching => _isCaching;
  int get cacheCurrent => _cacheCurrent;
  int get cacheTotal => _cacheTotal;
  bool get hasDetail => _detail != null;

  Future<void> _checkInBookshelf() async {
    final bookId = _detail?.book.id ?? entryBook.id;
    final inShelf = await NovelModule.bookshelf.isInBookshelf(bookId);
    _inBookshelf = inShelf;
    notifyListeners();
  }

  Future<void> _load({required bool forceRefresh}) async {
    _loading = true;
    _error = '';
    notifyListeners();

    try {
      final detail = await NovelModule.repository.fetchDetail(
        bookId: entryBook.id,
        detailUrl: entryBook.detailUrl,
        forceRefresh: forceRefresh,
      );

      final newBook = detail.book;
      final merged = NovelDetail(
        book: entryBook.copyWith(
          title: newBook.title.isNotEmpty ? newBook.title : null,
          author: newBook.author.isNotEmpty ? newBook.author : null,
          intro: newBook.intro.isNotEmpty ? newBook.intro : null,
          coverUrl: newBook.coverUrl.isNotEmpty ? newBook.coverUrl : null,
          category: newBook.category.isNotEmpty ? newBook.category : null,
          status: newBook.status.isNotEmpty ? newBook.status : null,
          wordCount: newBook.wordCount.isNotEmpty ? newBook.wordCount : null,
        ),
        chapters: detail.chapters,
      );

      final progress = await NovelModule.repository.getProgress(merged.book.id);
      await _checkInBookshelf();

      _detail = merged;
      _progress = progress;
      _loading = false;
      _error = '';
      notifyListeners();

      // 如果简介为空，后台补全
      if (merged.book.intro.trim().isEmpty) {
        _silentPatchMissingMetadata(merged.book.title, merged.book.author);
      }
    } on FormatException {
      // 书源切换后，旧书 detailUrl/id 格式不兼容当前书源
      await _tryRemapOrError();
    } on NovelException {
      await _tryRemapOrError();
    } catch (e) {
      _error = '加载失败：$e';
      _loading = false;
      notifyListeners();
    }
  }

  /// 书源不兼容时，尝试按书名搜索重新匹配；失败则显示友好提示
  Future<void> _tryRemapOrError() async {
    final remapped = await _tryRemapByTitle();
    if (remapped != null) {
      _detail = remapped;
      _loading = false;
      _error = '';
      notifyListeners();
      return;
    }
    _error = '书源已更换，请在书架中移除该书籍后重新搜索添加';
    _loading = false;
    notifyListeners();
  }

  /// 书源切换后，旧书的 detailUrl/id 在当前书源中无法使用。
  /// 尝试按书名搜索，若找到则自动「映射」到当前书源并更新书架。
  Future<NovelDetail?> _tryRemapByTitle() async {
    final title = entryBook.title.trim();
    final author = entryBook.author.trim();
    if (title.isEmpty) return null;

    try {
      final results = await NovelModule.repository.searchBooks(
        title,
        page: 1,
        forceRefresh: true,
      );

      // 优先匹配书名 + 作者，其次仅匹配书名
      NovelBook? match;
      for (final book in results) {
        if (book.title == title && author.isNotEmpty && book.author == author) {
          match = book;
          break;
        }
      }
      match ??= results.cast<NovelBook?>().firstWhere(
        (b) => b!.title == title,
        orElse: () => results.isNotEmpty ? results.first : null,
      );

      if (match == null) return null;

      // 用新书源的 detailUrl 重新获取详情
      final detail = await NovelModule.repository.fetchDetail(
        bookId: match.id,
        detailUrl: match.detailUrl,
        forceRefresh: true,
      );

      // 更新书架条目 → 下次直接走新书源
      await NovelModule.bookshelf.addToBookshelf(match);

      final merged = NovelDetail(
        book: match.copyWith(
          title: detail.book.title.isNotEmpty ? detail.book.title : null,
          author: detail.book.author.isNotEmpty ? detail.book.author : null,
          intro: detail.book.intro.isNotEmpty ? detail.book.intro : null,
          coverUrl: detail.book.coverUrl.isNotEmpty
              ? detail.book.coverUrl
              : null,
          category:
              detail.book.category.isNotEmpty ? detail.book.category : null,
          status: detail.book.status.isNotEmpty ? detail.book.status : null,
          wordCount:
              detail.book.wordCount.isNotEmpty ? detail.book.wordCount : null,
        ),
        chapters: detail.chapters,
      );
      return merged;
    } catch (_) {
      return null;
    }
  }

  Future<void> reload({bool forceRefresh = true}) async {
    await _load(forceRefresh: forceRefresh);
  }

  Future<void> _silentPatchMissingMetadata(String title, String author) async {
    if (title.isEmpty) return;
    try {
      final searchResults = await NovelModule.repository.searchBooks(
        title,
        page: 1,
        forceRefresh: true,
      );

      NovelBook? exactBook;
      for (var book in searchResults) {
        if (book.title == title) {
          exactBook = book;
          break;
        }
      }

      if (exactBook != null && exactBook.intro.isNotEmpty && _detail != null) {
        _detail = NovelDetail(
          book: _detail!.book.copyWith(
            intro: exactBook.intro,
            category: exactBook.category.isNotEmpty ? exactBook.category : null,
            status: exactBook.status.isNotEmpty ? exactBook.status : null,
            wordCount: exactBook.wordCount.isNotEmpty
                ? exactBook.wordCount
                : null,
          ),
          chapters: _detail!.chapters,
        );
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> toggleBookshelf() async {
    final bookToSave = _detail?.book ?? entryBook;
    if (_inBookshelf) {
      await NovelModule.bookshelf.removeFromBookshelf(bookToSave.id);
      _inBookshelf = false;
    } else {
      await NovelModule.bookshelf.addToBookshelf(bookToSave);
      _inBookshelf = true;
    }
    notifyListeners();
  }

  Future<void> toggleCache() async {
    if (_isCaching) {
      _cancelCache = true;
      _isCaching = false;
      _cacheCurrent = 0;
      notifyListeners();
      return;
    }

    final detail = _detail;
    if (detail == null || detail.chapters.isEmpty) return;

    _isCaching = true;
    _cancelCache = false;
    _cacheTotal = detail.chapters.length;
    _cacheCurrent = 0;
    notifyListeners();

    if (!_inBookshelf) {
      await toggleBookshelf();
    }

    for (int i = 0; i < detail.chapters.length; i++) {
      if (_cancelCache) break;
      try {
        await NovelModule.repository.fetchChapter(
          detail: detail,
          chapterIndex: i,
          forceRefresh: false,
        );
      } catch (_) {}

      if (i % 10 == 0) await Future.delayed(const Duration(milliseconds: 20));
      _cacheCurrent = i + 1;
      notifyListeners();
    }

    if (!_cancelCache) {
      _isCaching = false;
      _cacheCurrent = 0;
      notifyListeners();
    }
  }

  void toggleReverse() {
    _reverse = !_reverse;
    notifyListeners();
  }

  Future<void> refreshProgress() async {
    if (_detail == null) return;
    final p = await NovelModule.repository.getProgress(_detail!.book.id);
    _progress = p;
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelCache = true;
    super.dispose();
  }
}
