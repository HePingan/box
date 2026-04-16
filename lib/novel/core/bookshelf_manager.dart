import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'novel_cache_keys.dart';

class BookshelfManager {
  static String get _key => NovelCacheKeys.bookshelf;

  static Future<List<NovelBook>> getBookshelf() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_key);
    if (str == null || str.isEmpty) return [];

    try {
      final raw = jsonDecode(str);
      if (raw is! List) return [];
      final books = <NovelBook>[];
      for (final item in raw) {
        if (item is Map) {
          try {
            books.add(NovelBook.fromJson(Map<String, dynamic>.from(item)));
          } catch (_) {}
        }
      }
      return _dedupe(books);
    } catch (_) {
      return [];
    }
  }

  static Future<List<NovelDetail>> getBookshelfBooks() async {
    final books = await getBookshelf();
    final details = <NovelDetail>[];
    for (final book in books) {
      details.add(NovelDetail(book: book, chapters: []));
    }
    return details;
  }

  static Future<bool> isInBookshelf(String bookId) async {
    final books = await getBookshelf();
    return books.any((b) => b.id == bookId || b.detailUrl == bookId);
  }

  static Future<void> addToBookshelf(NovelBook book) async {
    final books = await getBookshelf();
    books.removeWhere((b) => _bookKey(b) == _bookKey(book));
    books.insert(0, book);
    await _save(books);
  }

  static Future<void> replaceBookshelf(List<NovelBook> books) async {
    await _save(books);
  }

  static Future<void> removeFromBookshelf(String bookId) async {
    final books = await getBookshelf();
    books.removeWhere((b) => b.id == bookId || b.detailUrl == bookId);
    await _save(books);
    await _removeReadingProgress(bookId);
  }

  static Future<void> clearBookshelf() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  // 阅读进度相关
  static String _progressKey(String bookId) {
    return '${NovelCacheKeys.readingProgress}_$bookId';
  }

  static Future<ReadingProgress?> getReadingProgress(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_progressKey(bookId));
    if (str == null || str.isEmpty) return null;
    try {
      final json = jsonDecode(str) as Map<String, dynamic>;
      return ReadingProgress.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveReadingProgress(ReadingProgress progress) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _progressKey(progress.bookId),
      jsonEncode(progress.toJson()),
    );
  }

  static Future<void> _removeReadingProgress(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_progressKey(bookId));
  }

  static Future<void> clearAllReadingProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith('${NovelCacheKeys.readingProgress}_')) {
        await prefs.remove(key);
      }
    }
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

  static Future<void> _save(List<NovelBook> books) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = _dedupe(books);
    final list = normalized.map((b) => b.toJson()).toList();
    await prefs.setString(_key, jsonEncode(list));
  }
}