import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
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

  /// 串行化「读-改-写」的尾链。
  ///
  /// 书架的每个写操作都是 `await 读` → 改 → `await 写`，中间有 await 间隙。
  /// 两个并发写会各自基于同一份快照修改，后写的覆盖先写的（用户同时收藏两本
  /// 书只进一本）。把写操作串成链，保证同一时刻只有一个读-改-写在跑。
  Future<void> _writeChain = Future<void>.value();

  /// 把一个读-改-写操作排到串行链尾，返回它自己的完成态。
  Future<void> _serialize(Future<void> Function() action) {
    final next = _writeChain.then((_) => action(), onError: (_) => action());
    // 链本身要吞掉异常，否则一次失败会毒化后续所有写操作。
    _writeChain = next.catchError((_) {});
    return next;
  }

  /// 丢弃已解码的内存缓存，下次读取重新从 SharedPreferences 载入。
  ///
  /// 恢复备份后必须调用：本类是「读缓存 → 改 → 全量写回」的模式，
  /// 若缓存还是恢复前的旧书架，用户随后任意一次增删都会把恢复的内容
  /// 整个覆盖掉。故意**不动** `_writeChain` —— 那是串行锁，中途换掉会让
  /// 在途写入与后续写入失去互斥，重新引入丢写。
  void invalidateCache() {
    _bookshelfCache = null;
  }

  /// 仅供测试：清空内存缓存与串行链，模拟冷启动。
  @visibleForTesting
  void resetForTest() {
    _prefs = null;
    _bookshelfCache = null;
    _writeChain = Future<void>.value();
  }

  Future<SharedPreferences> get _prefsAsync async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// 读取书架。返回**副本**：调用方常做 removeWhere/insert，若返回缓存本体
  /// 会就地污染内存态（即使随后 _save 失败，UI 也已显示错误内容）。
  Future<List<NovelBook>> getBookshelf() async {
    final cached = await _loadCache();
    return List<NovelBook>.of(cached);
  }

  /// 内部读取：返回缓存本体，仅供本类在串行链内使用。
  Future<List<NovelBook>> _loadCache() async {
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
          } catch (e) {
            // 跳过坏条目而不是整架报废，但要留痕 ——
            // 静默会让「书莫名消失」查不出原因。
            debugPrint('[BookshelfManager] 跳过无法解析的书架条目: $e');
          }
        }
      }
      _bookshelfCache = _dedupe(books);
    } catch (e, st) {
      // 这里失败意味着整个书架 JSON 损坏，用户会看到「书架空了」。
      // 控制流保持降级（不能因为存储损坏就崩），但必须留下线索，
      // 否则这类故障在用户侧完全无法定性。
      debugPrint('[BookshelfManager] 书架数据解析失败，已降级为空书架: $e\n$st');
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

  Future<void> addToBookshelf(NovelBook book) {
    return _serialize(() async {
      // 必须在串行链内重新读，不能用链外的旧快照，否则又变回丢写。
      final books = List<NovelBook>.of(await _loadCache());
      final key = _bookKey(book);
      books.removeWhere((b) => _bookKey(b) == key);
      books.insert(0, book);
      await _save(books);
    });
  }

  Future<void> replaceBookshelf(List<NovelBook> books) {
    final snapshot = List<NovelBook>.of(books);
    return _serialize(() => _save(snapshot));
  }

  Future<void> removeFromBookshelf(String bookId) {
    return _serialize(() async {
      final books = List<NovelBook>.of(await _loadCache());
      books.removeWhere((b) => b.id == bookId || b.detailUrl == bookId);
      await _save(books);
    });
  }

  Future<void> clearBookshelf() {
    return _serialize(() async {
      final prefs = await _prefsAsync;
      await prefs.remove(_storageKey);
      _bookshelfCache = [];
    });
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
