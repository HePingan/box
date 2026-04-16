class NovelCacheKeys {
  const NovelCacheKeys._();

  /// 搜索结果缓存
  static String search(String keyword, int page) {
    return 'search:${keyword.trim()}:$page';
  }

  /// 发现页 / 路由列表缓存
  static String path(String path) {
    return 'path:$path';
  }

  /// 书籍详情缓存
  static String detail({
    required String bookId,
    String? detailUrl,
  }) {
    final target = detailUrl != null && detailUrl.trim().isNotEmpty
        ? detailUrl.trim()
        : bookId;
    return 'detail:$target';
  }

  /// 章节正文缓存
  static String chapter(String chapterUrl) {
    return 'chapter:$chapterUrl';
  }

  /// 阅读进度基础 key
  static const String readingProgress = 'reading_progress';

  /// 阅读设置 key
  static const String readerSettings = 'reader_settings';

  /// 书架 key
  static const String bookshelf = 'user_bookshelf_v1';

  /// 按书籍区分的阅读进度 key
  static String readingProgressOf(String bookId) {
    return '$readingProgress:$bookId';
  }

  /// 兼容旧代码：progress(...) 等价于 readingProgressOf(...)
  static String progress(String bookId) {
    return readingProgressOf(bookId);
  }
}