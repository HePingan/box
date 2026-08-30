import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:box/features/backup/local_backup_service.dart';

void main() {
  setUpAll(() async {
    Hive.init('/tmp/box-backup-test');
    LocalBackupService.exportQuizJson = () async =>
        jsonEncode({'version': 2, 'items': []});
    LocalBackupService.importQuizJson = (raw) async {
      expect(jsonDecode(raw)['items'], isA<List>());
      return 0;
    };
  });

  tearDownAll(() async {
    for (final name in [
      'video_favorites_box',
      'play_history',
      'video_search_history_box',
      'video_source_search_history_box',
      'video_play_line_memory_box',
      'video_source_visibility_box',
      'video_download_tasks_v1',
    ]) {
      if (Hive.isBoxOpen(name)) await Hive.box(name).deleteFromDisk();
    }
  });

  test('创建与恢复备份保留 Hive 记录', () async {
    final box = await Hive.openBox<dynamic>('video_favorites_box');
    await box.put('source::1', {'vodId': 1, 'vodName': '测试片'});

    final raw = await LocalBackupService.createBackup();
    await box.clear();
    expect(box.get('source::1'), isNull);

    final count = await LocalBackupService.restoreBackup(raw);
    expect(count, 1);
    expect(box.get('source::1'), {'vodId': 1, 'vodName': '测试片'});
  });

  test('备份覆盖 lib 中出现的全部 Hive box 名', () async {
    // 防止新增一个 box 却忘记加进备份清单 —— 那样重装即静默丢数据。
    final declared = LocalBackupService.debugBoxNames.toSet();
    expect(declared, contains('video_source_search_history_box'));
    expect(declared.length, greaterThanOrEqualTo(7));
  });

  test('从字节恢复时中文不被拆成乱码', () async {
    final box = Hive.box<dynamic>('video_favorites_box');
    await box.clear();
    await box.put('src::9', {'vodId': 9, 'vodName': '中文片名·测试'});

    final bytes = utf8.encode(await LocalBackupService.createBackup());
    await box.clear();
    await LocalBackupService.restoreBackupBytes(bytes);

    expect((box.get('src::9') as Map)['vodName'], '中文片名·测试');
  });
}
