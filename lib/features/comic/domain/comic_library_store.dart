import 'dart:convert';
import 'package:box/core/storage/cache_store.dart';
import 'comic_book.dart';
import 'comic_reader_state.dart';

/// 漫画本地库存储
class ComicLibraryStore {
  ComicLibraryStore({CacheStore? cacheStore})
      : _cache = cacheStore ?? CacheStore(namespace: 'comic_library');

  final CacheStore _cache;

  static const String _keyBooks = 'books';
  static const String _keyProgress = 'progress';

  Future<void> add(ComicBook book) async {
    final books = await _fetchBooks();
    books.removeWhere((e) => e.id == book.id);
    books.insert(0, book);
    await _saveBooks(books);
  }

  Future<void> remove(String id) async {
    final books = await _fetchBooks();
    books.removeWhere((e) => e.id == id);
    await _saveBooks(books);
  }

  Future<void> save(List<ComicBook> books) async {
    await _saveBooks(books);
  }

  /// 读取所有漫画
  Future<List<ComicBook>> fetch() async {
    return _fetchBooks();
  }

  Future<List<ComicBook>> _fetchBooks() async {
    final raw = await _cache.read(_keyBooks);
    if (raw is! List) return <ComicBook>[];

    final books = <ComicBook>[];
    for (final item in raw) {
      if (item is Map) {
        try {
          books.add(ComicBook.fromJson(Map<String, dynamic>.from(item)));
        } catch (_) {
          // ignore corrupt entries
        }
      }
    }
    books.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return books;
  }

  Future<void> _saveBooks(List<ComicBook> books) async {
    await _cache.write(
      _keyBooks,
      books.map((e) => e.toJson()).toList(),
    );
  }

  Future<ComicReaderState?> loadProgress(String comicBookId) async {
    final raw = await _cache.read('$_keyProgress/$comicBookId');
    if (raw is String) {
      try {
        return ComicReaderState.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<void> saveProgress(ComicReaderState state) async {
    await _cache.write(
      '$_keyProgress/${state.comicBookId}',
      jsonEncode(state.toJson()),
    );
  }
}
