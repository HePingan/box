// 漫画收藏必须进备份。
//
// 缺陷背景：漫画库用 `CacheStore(namespace: 'comic_library')` 落在
// getApplicationSupportDirectory() 的文件里，而 LocalBackupService 只导
// Hive box + SharedPreferences + 题库(sqflite) 三条通道 —— 漫画收藏
// 一条都不沾，导出的备份里根本没有它。
//
// 表现是静默的不可逆丢失：用户导出备份、重装、恢复，提示"恢复成功"，
// 但漫画书架是空的。这类丢失比报错更糟，因为用户以为自己有备份。
library;

import 'package:box/features/backup/local_backup_codec.dart';
import 'package:box/features/backup/local_backup_service.dart';
import 'package:box/features/comic/domain/comic_library_backup.dart';
import 'package:box/features/comic/domain/comic_library_store.dart';
import 'package:box/core/storage/cache_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'dart:io';

void main() {
  // Hive 在纯 Dart 测试里没有默认路径，接线守卫会真的去开 box。
  late Directory hiveDir;
  setUpAll(() {
    hiveDir = Directory.systemTemp.createTempSync('box_comic_backup_test');
    Hive.init(hiveDir.path);
  });
  tearDownAll(() async {
    await Hive.close();
    if (hiveDir.existsSync()) hiveDir.deleteSync(recursive: true);
  });

  group('漫画收藏进备份', () {
    test('导出的 section 能被原样导入回来', () async {
      final source = ComicLibraryStore(
        cacheStore: CacheStore.inMemory('comic_library_export'),
      );
      await source.save([
        ComicLibraryBackup.sampleEntry(id: 'c1', title: '漫画一'),
        ComicLibraryBackup.sampleEntry(id: 'c2', title: '漫画二'),
      ]);

      final section = await ComicLibraryBackup.export(source);
      expect(section, hasLength(2));

      final target = ComicLibraryStore(
        cacheStore: CacheStore.inMemory('comic_library_import'),
      );
      final restored = await ComicLibraryBackup.import(target, section);
      expect(restored, 2);

      final books = await target.fetch();
      expect(books.map((e) => e.title), containsAll(['漫画一', '漫画二']));
    });

    test('备份文件里必须真的带上漫画分区（codec 层面）', () {
      final raw = LocalBackupCodec.encode(
        quizJson: '{"items":[]}',
        hiveBoxes: const {},
        prefs: const {},
        extraSections: {
          ComicLibraryBackup.sectionKey: [
            {'id': 'c1', 'title': '漫画一'},
          ],
        },
      );

      final decoded = LocalBackupCodec.decode(raw);
      expect(
        decoded.extraSections[ComicLibraryBackup.sectionKey],
        hasLength(1),
        reason: '漫画分区必须能穿过 encode/decode，否则备份里就是没有它',
      );
    });

    test('老备份文件没有漫画分区时，解码不报错（向后兼容）', () {
      final raw = LocalBackupCodec.encode(
        quizJson: '{"items":[]}',
        hiveBoxes: const {},
        prefs: const {},
      );
      final decoded = LocalBackupCodec.decode(raw);
      expect(decoded.extraSections[ComicLibraryBackup.sectionKey], isNull);
    });

    test('导入坏条目时跳过，不让整次恢复失败', () async {
      final target = ComicLibraryStore(
        cacheStore: CacheStore.inMemory('comic_library_bad'),
      );
      final restored = await ComicLibraryBackup.import(target, [
        {
          'id': 'ok',
          'title': '好的',
          'sourceType': 'file',
          'filePath': '/a.zip',
          'createdAt': 1700000000000,
        },
        {'no': 'id'},
        'not a map',
      ]);
      expect(restored, 1);
      expect((await target.fetch()), hasLength(1));
    });

    test('备份服务真的调用了漫画通道（接线守卫）', () async {
      // 光有适配器不算修好：如果 createBackup/restoreBackup 忘了调用它，
      // 这就是一段谁也用不到的死代码，用户照样丢数据。
      final sample = [
        ComicLibraryBackup.sampleEntry(id: 'wired', title: '接线验证').toJson(),
      ];
      var exportCalled = false;
      List<dynamic>? importedRecords;

      LocalBackupService.exportComicLibrary = () async {
        exportCalled = true;
        return sample;
      };
      LocalBackupService.importComicLibrary = (records) async {
        importedRecords = records;
        return records.length;
      };
      LocalBackupService.exportQuizJson = () async => '{"items":[]}';
      LocalBackupService.importQuizJson = (_) async => 0;
      LocalBackupService.readPrefs = () async => <String, Object>{};
      LocalBackupService.writePrefs = (_) async {};

      addTearDown(() {
        LocalBackupService.exportQuizJson =
            LocalBackupService.defaultQuizExport;
        LocalBackupService.importQuizJson =
            LocalBackupService.defaultQuizImport;
      });

      final raw = await LocalBackupService.createBackup();
      expect(exportCalled, isTrue, reason: 'createBackup 必须采集漫画收藏');
      expect(raw, contains('接线验证'), reason: '备份文件里必须真的有漫画数据');

      await LocalBackupService.restoreBackup(raw);
      expect(
        importedRecords,
        isNotNull,
        reason: 'restoreBackup 必须把漫画分区喂给恢复通道',
      );
      expect(importedRecords, hasLength(1));
    });

    test('恢复是合并而不是覆盖：已有收藏不能被抹掉', () async {
      final target = ComicLibraryStore(
        cacheStore: CacheStore.inMemory('comic_library_merge'),
      );
      await target.save([
        ComicLibraryBackup.sampleEntry(id: 'local', title: '本机已有'),
      ]);

      await ComicLibraryBackup.import(target, [
        ComicLibraryBackup.sampleEntry(id: 'fromBackup', title: '备份里的').toJson(),
      ]);

      final books = await target.fetch();
      expect(
        books.map((e) => e.title),
        containsAll(['本机已有', '备份里的']),
        reason: '恢复不该把本机已有的漫画删掉',
      );
    });

    test('同 id 冲突时保留本机版本（本机进度更新）', () async {
      // 变异测试暴露的盲区：上一条用例两个 id 不同，根本走不到冲突分支，
      // 把「同 id 保留本机」整行删掉它照样绿。
      final store = ComicLibraryStore(
        cacheStore: CacheStore.inMemory('comic_library_conflict'),
      );
      await store.save([
        ComicLibraryBackup.sampleEntry(id: 'same', title: '本机较新的标题'),
      ]);

      final restored = await ComicLibraryBackup.import(store, [
        ComicLibraryBackup.sampleEntry(id: 'same', title: '备份里的旧标题').toJson(),
      ]);

      expect(restored, 0, reason: '冲突条目不该计入恢复数');
      final books = await store.fetch();
      expect(books, hasLength(1), reason: '不该产生重复条目');
      expect(books.single.title, '本机较新的标题');
    });
  });
}
