import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart'; // 确保这里指向你存放 NovelBook 的那个 models 文件

class BookshelfManager {
  static const String _key = 'user_bookshelf_v1';

  // 获取书架内所有书籍
  static Future<List<NovelBook>> getBookshelf() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_key);
    if (str == null || str.isEmpty) return [];

    try {
      final List list = jsonDecode(str);
      return list.map((e) => NovelBook(
            id: e['id'] ?? '',
            title: e['title'] ?? '',
            author: e['author'] ?? '',
            intro: e['intro'] ?? '',
            coverUrl: e['coverUrl'] ?? '',
            detailUrl: e['detailUrl'] ?? '',
            category: e['category'] ?? '',
            status: e['status'] ?? '',
            wordCount: e['wordCount'] ?? '',
          )).toList();
    } catch (_) {
      return [];
    }
  }

  // 检查一本小说是否已在书架中
  static Future<bool> isInBookshelf(String bookId) async {
    final books = await getBookshelf();
    return books.any((b) => b.id == bookId);
  }

  // 点击加入书架 (最新加入的排在前面)
  static Future<void> addToBookshelf(NovelBook book) async {
    final books = await getBookshelf();
    if (!books.any((b) => b.id == book.id)) {
      books.insert(0, book);
      await _save(books);
    }
  }

  // 点击移出书架
  static Future<void> removeFromBookshelf(String bookId) async {
    final books = await getBookshelf();
    books.removeWhere((b) => b.id == bookId);
    await _save(books);
  }

  // 内部保存逻辑
  static Future<void> _save(List<NovelBook> books) async {
    final prefs = await SharedPreferences.getInstance();
    final list = books.map((b) => {
          'id': b.id,
          'title': b.title,
          'author': b.author,
          'intro': b.intro,
          'coverUrl': b.coverUrl,
          'detailUrl': b.detailUrl,
          'category': b.category,
          'status': b.status,
          'wordCount': b.wordCount,
        }).toList();
    await prefs.setString(_key, jsonEncode(list));
  }
}