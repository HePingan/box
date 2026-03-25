class NovelCacheKeys {
  const NovelCacheKeys._();

  static String search(String keyword, int page) {
    return 'search:${keyword.trim()}:$page';
  }

  static String path(String path) {
    return 'path:$path';
  }

  static String detail({
    required String bookId,
    String? detailUrl,
  }) {
    final target = detailUrl != null && detailUrl.trim().isNotEmpty
        ? detailUrl.trim()
        : bookId;
    return 'detail:$target';
  }

  static String chapter(String chapterUrl) {
    return 'chapter:$chapterUrl';
  }

  static String progress(String bookId) {
    return 'progress:$bookId';
  }

  static const String readerSettings = 'reader_settings';
  static const String bookshelf = 'user_bookshelf_v1';
}