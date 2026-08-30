/// 备份需要覆盖的 SharedPreferences 键。
///
/// 为什么单独一个文件：小说模块的用户资产**全部**存在 SharedPreferences，
/// 而备份服务原来只导 Hive box + 题库(sqflite)，导致书架/书源/阅读进度
/// 一条都进不了备份。1.7.0 换包名后所有人必须卸载重装，备份是唯一的数据
/// 通道，漏了就是静默的不可逆丢失（用户以为备份成功了）。
///
/// 判断标准：**用户自己攒出来的**才备份，能重新抓的缓存不备份。
/// 所以这里收书架、书源、进度、设置，不收 `search:` / `detail:` /
/// `chapter:` 这些网络缓存（章节正文还落在文件里，见 NovelCacheManager，
/// 塞进 JSON 备份会让文件涨到几十 MB）。
class BackupPrefKeys {
  const BackupPrefKeys._();

  /// 固定键：键名写死，逐个导出。
  static const List<String> fixedKeys = <String>[
    // —— 小说：书架与分组 ——
    'user_bookshelf_v1', // NovelCacheKeys.bookshelf
    'bookshelf_groups', // BookshelfGroup._groupsKey
    'bookshelf_group_members', // BookshelfGroup._membersKey
    // —— 小说：书源（用户自己配的，丢了要重新加）——
    'novel_book_sources_v1', // BookSourceManager.storageKey
    'novel_current_book_source_id_v1', // BookSourceManager.currentSourceKey
    // —— 小说：阅读器设置 ——
    'reader_settings', // NovelCacheKeys.readerSettings
    // —— 小说：离线缓存清单 ——
    // 正文本体在文件里，不进备份；这份元数据留着，恢复后能看出
    // 哪些书曾离线过（正文没了会重新下）。
    'offline_books_meta_v3', // OfflineCacheService._metaKey
    'offline_cached_books_v2', // 旧版书 ID 集合，兼容老数据
  ];

  /// 前缀键：键名是动态生成的，只能按前缀捞。
  ///
  /// `reading_progress:<bookId>` —— 每本书一条，是「继续阅读」的定位依据。
  /// 漏掉的表现是重装后每本书都从第一章开始。
  static const List<String> prefixes = <String>[
    'reading_progress',
  ];

  /// 某个 key 是否属于备份范围。
  static bool covers(String key) {
    if (fixedKeys.contains(key)) return true;
    for (final prefix in prefixes) {
      // 同时接受 `reading_progress` 本身和 `reading_progress:<id>`。
      if (key == prefix || key.startsWith('$prefix:')) return true;
    }
    return false;
  }
}
