import 'dart:async';
import 'package:flutter/material.dart';
import 'package:box/features/comic/domain/comic_book.dart';
import 'package:box/features/comic/domain/comic_reader_state.dart';
import 'package:box/features/comic/domain/comic_library_store.dart';

/// 漫画阅读器控制器（镜像小说阅读器模式）
class ComicReaderController extends ChangeNotifier {
  ComicReaderController({
    required this.comicBook,
    int initialPageIndex = 0,
    ComicLibraryStore? libraryStore,
  })  : _libraryStore = libraryStore,
        _currentPageIndex = initialPageIndex;

  final ComicBook comicBook;
  final ComicLibraryStore? _libraryStore;

  int _currentPageIndex;
  int get currentPageIndex => _currentPageIndex;

  int? _totalPages;
  int get totalPages => _totalPages ?? comicBook.pages.length;

  bool _isScrollMode = false;
  bool get isScrollMode => _isScrollMode;

  bool loading = true;
  bool isError = false;
  String errorText = '';

  Future<void> loadPages() async {
    loading = true;
    isError = false;
    notifyListeners();

    try {
      _totalPages = comicBook.pages.length;
      loading = false;
      notifyListeners();
    } catch (e) {
      isError = true;
      errorText = e.toString();
      notifyListeners();
    }
  }

  void goNext() {
    if (_currentPageIndex < totalPages - 1) {
      _currentPageIndex++;
      notifyListeners();
    }
  }

  void goPrevious() {
    if (_currentPageIndex > 0) {
      _currentPageIndex--;
      notifyListeners();
    }
  }

  void setPage(int index) {
    _currentPageIndex = index.clamp(0, totalPages - 1);
    notifyListeners();
  }

  void toggleScrollMode() {
    _isScrollMode = !_isScrollMode;
    notifyListeners();
  }

  Future<void> saveProgress() async {
    final store = _libraryStore ?? ComicLibraryStore();
    final state = ComicReaderState(
      comicBookId: comicBook.id,
      currentPageIndex: _currentPageIndex,
      totalPages: totalPages,
      isScrollMode: _isScrollMode,
      lastReadAt: DateTime.now().millisecondsSinceEpoch,
    );
    await store.saveProgress(state);
  }

  Future<ComicReaderState?> loadProgress() async {
    final store = _libraryStore ?? ComicLibraryStore();
    return store.loadProgress(comicBook.id);
  }

  @override
  void dispose() {
    saveProgress();
    super.dispose();
  }
}
