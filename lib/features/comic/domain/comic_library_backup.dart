import 'comic_book.dart';
import 'comic_library_store.dart';

/// 漫画收藏的备份适配器。
///
/// 为什么需要它：漫画库存在 `CacheStore(namespace: 'comic_library')`，也就是
/// getApplicationSupportDirectory() 下的普通文件。而 LocalBackupService 只
/// 采集三种东西 —— Hive box、SharedPreferences、题库 sqflite。漫画一条都不沾，
/// 所以备份包里从来没有它。用户导出备份、重装、恢复，看到「恢复成功」，
/// 漫画书架却是空的。静默丢失比报错更糟，因为用户以为自己有备份。
class ComicLibraryBackup {
  /// 备份文件里的分区名。改这个字符串会让老备份里的漫画读不出来。
  static const String sectionKey = 'comic_library';

  /// 导出为可 JSON 序列化的记录列表。
  static Future<List<Map<String, dynamic>>> export(
    ComicLibraryStore store,
  ) async {
    final books = await store.fetch();
    return books.map((e) => e.toJson()).toList();
  }

  /// 从备份分区恢复，返回真正写入的条目数。
  ///
  /// 两条刻意的设计：
  /// 1. 合并而非覆盖 —— 恢复不该把本机已有的漫画删掉；
  /// 2. 坏条目跳过而非抛异常 —— 一条脏数据不应该让整次恢复失败。
  static Future<int> import(
    ComicLibraryStore store,
    List<dynamic> records,
  ) async {
    final existing = await store.fetch();
    final byId = <String, ComicBook>{for (final b in existing) b.id: b};

    var restored = 0;
    for (final record in records) {
      if (record is! Map) continue;
      try {
        final book = ComicBook.fromJson(Map<String, dynamic>.from(record));
        // 本机已有同 id 时保留本机版本：它的阅读进度更新。
        if (byId.containsKey(book.id)) continue;
        byId[book.id] = book;
        restored++;
      } catch (_) {
        // 跳过损坏条目
      }
    }

    if (restored > 0) {
      await store.save(byId.values.toList());
    }
    return restored;
  }

  /// 构造测试用条目。放在生产代码里是因为测试需要一个与真实模型同步的
  /// 样本构造器，重复手写字段容易和模型漂移。
  static ComicBook sampleEntry({required String id, required String title}) {
    return ComicBook(
      id: id,
      title: title,
      sourceType: ComicSourceType.file,
      filePath: '/tmp/$id.cbz',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
