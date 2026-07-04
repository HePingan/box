import 'models.dart';

/// 书籍去重工具
class BookDeduplicator {
  BookDeduplicator._();

  /// 为单本书生成去重 key
  static String _keyOf(NovelBook book) =>
      book.id.isNotEmpty ? 'id:${book.id}' : 'url:${book.detailUrl}';

  /// 从列表中剔除重复书籍，返回新列表（保持传入顺序）
  static List<NovelBook> deduplicate(List<NovelBook> books) {
    final seen = <String>{};
    final out = <NovelBook>[];
    for (final book in books) {
      if (seen.add(_keyOf(book))) {
        out.add(book);
      }
    }
    return out;
  }

  /// 向已有列表追加不重复的书籍
  static void appendUnique(List<NovelBook> target, List<NovelBook> incoming) {
    final seen = <String>{
      for (final b in target)
        b.id.isNotEmpty ? 'id:${b.id}' : 'url:${b.detailUrl}',
    };
    for (final book in incoming) {
      if (seen.add(_keyOf(book))) {
        target.add(book);
      }
    }
  }
}
