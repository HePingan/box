import 'dart:convert';
import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../quiz_plugin/domain/quiz_bank.dart';
import 'local_backup_codec.dart';

/// 应用本地数据迁移服务。
///
/// 不导出账号 token 等 SharedPreferences，也不复制视频文件本体；只迁移
/// 能影响用户体验且确实落在本地的 Hive 数据与题库数据库。
class LocalBackupService {
  static const _boxNames = <String>[
    'video_favorites_box',
    'play_history',
    'video_search_history_box',
    'video_play_line_memory_box',
    'video_source_visibility_box',
    'video_download_tasks_v1',
  ];

  /// 题库读写默认走 sqflite。测试环境没有 sqflite 平台实现，
  /// 因此这两个钩子可被替换，用于在纯 Dart 测试里验证 Hive 迁移链路。
  static Future<String> Function() exportQuizJson =
      QuizBankStorage.exportJsonString;
  static Future<int> Function(String raw) importQuizJson = _defaultQuizImport;

  static Future<int> _defaultQuizImport(String raw) async {
    final result = await QuizBankStorage.importFromJsonString(raw, merge: true);
    return result.imported;
  }

  static Future<String> createBackup() async {
    final hive = <String, List<Map<String, dynamic>>>{};
    for (final name in _boxNames) {
      if (!Hive.isBoxOpen(name)) {
        await Hive.openBox<dynamic>(name);
      }
      final box = Hive.box<dynamic>(name);
      hive[name] = [
        for (final key in box.keys)
          {'key': key.toString(), 'value': _jsonSafe(box.get(key))},
      ];
    }
    return LocalBackupCodec.encode(
      quizJson: await exportQuizJson(),
      hiveBoxes: hive,
    );
  }

  static Future<File> writeBackupToTemporaryFile() async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File('${dir.path}/box_local_backup_$stamp.json');
    await file.writeAsString(await createBackup(), encoding: utf8, flush: true);
    return file;
  }

  /// 从文件字节恢复。
  ///
  /// 必须按 UTF-8 解码：备份里的片名、题干几乎都是中文，用
  /// `String.fromCharCodes` 会把多字节字符拆成乱码。
  static Future<int> restoreBackupBytes(List<int> bytes) =>
      restoreBackup(utf8.decode(bytes, allowMalformed: false));

  static Future<int> restoreBackup(String raw) async {
    final data = LocalBackupCodec.decode(raw);
    var restored = 0;
    for (final entry in data.hiveBoxes.entries) {
      if (!_boxNames.contains(entry.key)) continue;
      if (!Hive.isBoxOpen(entry.key)) {
        await Hive.openBox<dynamic>(entry.key);
      }
      final box = Hive.box<dynamic>(entry.key);
      for (final record in entry.value) {
        await box.put(record['key'], record['value']);
        restored++;
      }
    }
    return restored + await importQuizJson(data.quizJson);
  }

  static dynamic _jsonSafe(dynamic value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is DateTime) return value.toIso8601String();
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _jsonSafe(entry.value),
      };
    }
    if (value is Iterable) return value.map(_jsonSafe).toList();
    return value.toString();
  }
}
