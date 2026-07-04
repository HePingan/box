import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'novel_cache_keys.dart';

class BookshelfManager {
  BookshelfManager._();

  static final BookshelfManager _instance = BookshelfManager._();
  static BookshelfManager get instance => _instance;

  static const String _storageKey = NovelCacheKeys.bookshelf;

  SharedPreferences? _prefs;
  List<NovelBook>? _bookshelfCache;

  Future<SharedPreferences> get _prefsAsync async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<List<NovelBook>> getBookshelf() async {
    if (_bookshelfCache != null) return _bookshelfCache!;

    final prefs = await _prefsAsync;
    final str = prefs.getString(_storageKey);
    if (str == null || str.isEmpty) {
      _bookshelfCache = [];
      return _bookshelfCache!;
    }

    try {
      final raw = jsonDecode(str);
      if (raw is! List) {
        _bookshelfCache = [];
        return _bookshelfCache!;
      }
      final books = <NovelBook>[];
      for (final item in raw) {
        if (item is Map) {
          try {
            books.add(NovelBook.fromJson(Map<String, dynamic>.from(item)));
          } catch (_) {}
        }
      }
      _bookshelfCache = _dedupe(books);
    } catch (_) {
      _bookshelfCache = [];
    }
    return _bookshelfCache!;
  }

  Future<List<NovelDetail>> getBookshelfBooks() async {
    final books = await getBookshelf();
    return books
        .map((book) => NovelDetail(book: book, chapters: const []))
        .toList();
  }

  Future<bool> isInBookshelf(String bookId) async {
    final books = await getBookshelf();
    return books.any((b) => b.id == bookId || b.detailUrl == bookId);
  }

  Future<void> addToBookshelf(NovelBook book) async {
    final books = await getBookshelf();
    final key = _bookKey(book);
    books.removeWhere((b) => _bookKey(b) == key);
    books.insert(0, book);
    await _save(books);
  }

  Future<void> replaceBookshelf(List<NovelBook> books) async {
    await _save(books);
  }

  Future<void> removeFromBookshelf(String bookId) async {
    final books = await getBookshelf();
    books.removeWhere((b) => b.id == bookId || b.detailUrl == bookId);
    await _save(books);
  }

  Future<void> clearBookshelf() async {
    final prefs = await _prefsAsync;
    await prefs.remove(_storageKey);
    _bookshelfCache = [];
  }

  static String _bookKey(NovelBook book) {
    return book.id.isNotEmpty ? book.id : book.detailUrl;
  }

  static List<NovelBook> _dedupe(List<NovelBook> books) {
    final seen = <String>{};
    final result = <NovelBook>[];
    for (final book in books) {
      final key = _bookKey(book);
      if (key.isEmpty) continue;
      if (seen.add(key)) {
        result.add(book);
      }
    }
    return result;
  }

  Future<void> _save(List<NovelBook> books) async {
    final prefs = await _prefsAsync;
    final normalized = _dedupe(books);
    final list = normalized.map((b) => b.toJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(list));
    _bookshelfCache = normalized;
  }
}
