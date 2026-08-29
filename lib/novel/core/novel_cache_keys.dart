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
  static String detail({required String bookId, String? detailUrl}) {
    final target = detailUrl != null && detailUrl.trim().isNotEmpty
        ? detailUrl.trim()
        : bookId;
    return 'detail:$target';
  }

  /// 章节正文缓存。
  ///
  /// 必须 trim：写入侧（NovelRepository.fetchChapter）传的是源返回的原始 URL，
  /// 读取/删除侧（OfflineCacheService）历史上各自 `.trim()` 后再传。部分小说源
  /// 返回带尾空格的章节 URL，两侧算出不同键 —— 表现为「已缓存 0/300 章」但磁盘
  /// 已有数据，且清理时删不掉。归一化收在这里，避免调用点再次漂移。
  static String chapter(String chapterUrl) {
    return 'chapter:${chapterUrl.trim()}';
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
