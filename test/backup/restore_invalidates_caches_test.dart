import 'dart:convert';

import 'package:box/features/backup/local_backup_service.dart';
import 'package:box/novel/core/bookshelf_manager.dart';
import 'package:box/novel/core/models.dart';
import 'package:box/novel/core/novel_cache_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 恢复备份后，内存里的单例缓存必须失效。
///
/// 真实故事：恢复只把值写进 SharedPreferences，但 BookshelfManager 是
/// 全局单例，`_bookshelfCache` 还端着恢复**之前**的旧书架。用户接着
/// 加一本书 → `addToBookshelf` 从旧缓存出发 → `_save` 把旧书架整个
/// 写回 prefs → 刚恢复的书架被静默覆盖。
///
/// 表现是「恢复成功，重启后书架却是空的」——比恢复失败更难查，因为
/// 提示语说的是成功。
void main() {
  late NovelBook restoredBook;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    BookshelfManager.instance.resetForTest();
    // 题库走 sqflite，纯 Dart 环境没有 databaseFactory。本用例只关心
    // 书架缓存，把题库通道短路掉，避免无关依赖把测试挡在门外。
    LocalBackupService.importQuizJson = (_) async => 0;
    LocalBackupService.exportQuizJson = () async => '{"items":[]}';
    restoredBook = const NovelBook(
      id: 'b-restored',
      title: '恢复回来的书',
      author: '作者',
      intro: '',
      coverUrl: '',
      detailUrl: 'http://example.com/b-restored',
    );
  });

  tearDown(() {
    LocalBackupService.readPrefs = LocalBackupService.defaultReadPrefs;
    LocalBackupService.writePrefs = LocalBackupService.defaultWritePrefs;
    LocalBackupService.importQuizJson = LocalBackupService.defaultQuizImport;
    LocalBackupService.exportQuizJson = LocalBackupService.defaultQuizExport;
    BookshelfManager.instance.resetForTest();
  });

  /// 造一个只含书架的 v2 备份。
  String backupWithBookshelf(List<NovelBook> books) {
    return jsonEncode(<String, Object>{
      'format': 'box_local_backup',
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'quiz': <String, Object>{'items': <Object>[]},
      'hive': <String, Object>{},
      'prefs': <String, Object>{
        NovelCacheKeys.bookshelf: jsonEncode(
          books.map((b) => b.toJson()).toList(),
        ),
      },
    });
  }

  test('恢复后立即读书架，拿到的是恢复的内容而不是旧内存缓存', () async {
    // 先让单例把「旧状态（空书架）」读进内存缓存。
    final before = await BookshelfManager.instance.getBookshelf();
    expect(before, isEmpty);

    await LocalBackupService.restoreBackup(backupWithBookshelf([restoredBook]));

    final after = await BookshelfManager.instance.getBookshelf();
    expect(
      after.map((b) => b.id),
      contains('b-restored'),
      reason: '恢复后内存缓存没失效，读到的还是恢复前的旧书架',
    );
  });

  test('恢复后再加一本书，不会把恢复的书架覆盖掉', () async {
    // 关键回归：这是用户真正会遇到的路径。
    await BookshelfManager.instance.getBookshelf(); // 预热旧缓存（空）

    await LocalBackupService.restoreBackup(backupWithBookshelf([restoredBook]));

    // 恢复完用户随手加了一本 —— 走的是 _loadCache() → _save() 全量写回。
    await BookshelfManager.instance.addToBookshelf(
      const NovelBook(
        id: 'b-new',
        title: '新加的书',
        author: '',
        intro: '',
        coverUrl: '',
        detailUrl: 'http://example.com/b-new',
      ),
    );

    final ids = (await BookshelfManager.instance.getBookshelf())
        .map((b) => b.id)
        .toList();
    expect(ids, contains('b-new'));
    expect(
      ids,
      contains('b-restored'),
      reason: '旧内存缓存被 _save 全量写回，恢复的书架被静默覆盖',
    );

    // 落盘也要对：重启后读到的才是最终事实。
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(NovelCacheKeys.bookshelf);
    expect(raw, isNotNull);
    final persisted = (jsonDecode(raw!) as List)
        .map((e) => (e as Map)['id'] as String)
        .toList();
    expect(
      persisted,
      containsAll(<String>['b-restored', 'b-new']),
      reason: '磁盘上的书架缺了恢复的书，重启后就会发现数据没了',
    );
  });
}
