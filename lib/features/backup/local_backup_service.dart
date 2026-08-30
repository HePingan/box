import 'dart:convert';
import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../novel/core/bookshelf_group.dart';
import '../../novel/core/bookshelf_manager.dart';
import '../../novel/pages/reader/reader_paginator.dart';
import '../quiz_plugin/domain/quiz_bank.dart';
import 'backup_pref_keys.dart';
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
    // 源内搜索用的是独立 box（见 video_search_page.dart），漏掉会静默丢数据。
    'video_source_search_history_box',
    'video_play_line_memory_box',
    'video_source_visibility_box',
    'video_download_tasks_v1',
  ];

  /// 仅供测试断言备份清单完整性。
  static List<String> get debugBoxNames => List.unmodifiable(_boxNames);

  /// 仅供测试断言 SharedPreferences 覆盖面。
  static List<String> get debugPrefKeys =>
      List.unmodifiable(BackupPrefKeys.fixedKeys);

  static List<String> get debugPrefPrefixes =>
      List.unmodifiable(BackupPrefKeys.prefixes);

  /// SharedPreferences 读写钩子。
  ///
  /// 纯 Dart 测试环境没有 shared_preferences 的平台实现，替换这两个钩子
  /// 才能在单测里验证「小说资产确实进了备份、也确实恢复得回来」。
  static Future<Map<String, Object>> Function() readPrefs = defaultReadPrefs;
  static Future<void> Function(Map<String, Object> values) writePrefs =
      defaultWritePrefs;

  static Future<Map<String, Object>> defaultReadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, Object>{};
    for (final key in prefs.getKeys()) {
      if (!BackupPrefKeys.covers(key)) continue;
      final value = prefs.get(key);
      if (value != null) result[key] = value;
    }
    return result;
  }

  static Future<void> defaultWritePrefs(Map<String, Object> values) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in values.entries) {
      final key = entry.key;
      final value = entry.value;
      // 必须按原类型写回：SharedPreferences 是强类型存储，
      // 用 setString 写一个原本是 List<String> 的键，读取侧会抛类型错误。
      if (value is String) {
        await prefs.setString(key, value);
      } else if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is List) {
        await prefs.setStringList(
          key,
          value.map((e) => e.toString()).toList(growable: false),
        );
      }
    }
  }

  /// 题库读写默认走 sqflite。测试环境没有 sqflite 平台实现，
  /// 因此这两个钩子可被替换，用于在纯 Dart 测试里验证 Hive 迁移链路。
  static Future<String> Function() exportQuizJson = defaultQuizExport;
  static Future<int> Function(String raw) importQuizJson = defaultQuizImport;

  /// 默认实现暴露成公开名字，测试才能在 tearDown 里还原钩子。
  /// 否则替换过的钩子会泄漏到后续用例，制造跨文件的诡异失败。
  static Future<String> defaultQuizExport() =>
      QuizBankStorage.exportJsonString();

  static Future<int> defaultQuizImport(String raw) async {
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
      prefs: await _readPrefsOrEmpty(),
    );
  }

  /// 恢复后让持有 prefs 快照的单例重新载入。
  ///
  /// 可替换：这些单例分布在 novel 模块，测试里不一定都能安全触达。
  static Future<void> Function() invalidateCaches = defaultInvalidateCaches;

  static Future<void> defaultInvalidateCaches() async {
    BookshelfManager.instance.invalidateCache();
    BookshelfGroupManager.instance.invalidateCache();
    // 阅读器分页缓存按主题/字号缓存排版结果，恢复了 reader_settings
    // 之后旧排版就不再对应当前设置。
    ReaderPaginator.clearCache();
  }

  /// 单个缓存失效失败不该让整次恢复报错 —— 数据已经落盘了，
  /// 最坏结果是用户重启一次；把异常抛出去反而会显示「恢复失败」，
  /// 诱导用户重复恢复。
  static Future<void> _invalidateInMemoryCaches() async {
    try {
      await invalidateCaches();
    } catch (_) {
      // 静默：落盘已成功，重启即生效。
    }
  }

  /// 读 prefs 失败不能让整个备份失败。
  ///
  /// 视频侧数据（Hive）和小说侧数据（prefs）是两条独立通道，
  /// prefs 读不出来时，导出「视频数据齐、小说数据缺」远好于什么都导不出。
  /// 缺失不静默：summarize() 的分类计数会显示书架/书源为 0，用户看得见。
  static Future<Map<String, Object>> _readPrefsOrEmpty() async {
    try {
      return await readPrefs();
    } catch (_) {
      return const <String, Object>{};
    }
  }

  /// 备份内容清点，用于导出后当场自检。
  ///
  /// 只报总条数（原来的做法）看不出「某一类整体缺失」——书架 0 本和
  /// 备份漏了书架，在总数上是一样的。分类计数能让用户当场发现问题，
  /// 而不是重装后才发现。
  static BackupSummary summarize(String raw) {
    final data = LocalBackupCodec.decode(raw);
    var progressCount = 0;
    for (final key in data.prefs.keys) {
      if (key.startsWith('reading_progress:')) progressCount++;
    }
    return BackupSummary(
      favorites: data.hiveBoxes['video_favorites_box']?.length ?? 0,
      playHistory: data.hiveBoxes['play_history']?.length ?? 0,
      downloads: data.hiveBoxes['video_download_tasks_v1']?.length ?? 0,
      bookshelf: _countJsonList(data.prefs['user_bookshelf_v1']),
      bookSources: _countJsonList(data.prefs['novel_book_sources_v1']),
      readingProgress: progressCount,
      quizItems: _countQuizItems(data.quizJson),
    );
  }

  /// 书架/书源在 prefs 里是 jsonEncode 后的字符串，要解开才知道有几条。
  static int _countJsonList(dynamic value) {
    if (value is List) return value.length;
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) return decoded.length;
        if (decoded is Map) return decoded.length;
      } catch (_) {
        return 0;
      }
    }
    return 0;
  }

  static int _countQuizItems(String quizJson) {
    try {
      final decoded = jsonDecode(quizJson);
      if (decoded is Map && decoded['items'] is List) {
        return (decoded['items'] as List).length;
      }
    } catch (_) {
      // 计数失败不该让备份流程失败。
    }
    return 0;
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
    // 恢复 SharedPreferences 资产（书架/书源/阅读进度等）。
    // 只写备份范围内的键，避免一个被篡改的备份文件顺手改掉登录态之类。
    final prefsToWrite = <String, Object>{};
    for (final entry in data.prefs.entries) {
      if (!BackupPrefKeys.covers(entry.key)) continue;
      final value = entry.value;
      if (value == null) continue;
      prefsToWrite[entry.key] = value as Object;
    }
    if (prefsToWrite.isNotEmpty) {
      // 同理：prefs 写失败不该让已恢复的 Hive 数据白费。
      try {
        await writePrefs(prefsToWrite);
        restored += prefsToWrite.length;
      } catch (_) {
        // 计数不含这部分，用户看到的恢复条数会偏小而不是虚报。
      }
    }
    // prefs 已换了一批值，但内存里的单例还端着恢复前的旧快照。
    // 不失效的后果不是「显示不刷新」这么轻——BookshelfManager 之类
    // 是「读缓存 → 改 → 全量写回」的模式，用户恢复后随手加一本书就会
    // 把刚恢复的书架整个覆盖掉，而提示语说的是恢复成功。
    await _invalidateInMemoryCaches();

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

/// 备份内容分类清点结果。
class BackupSummary {
  const BackupSummary({
    required this.favorites,
    required this.playHistory,
    required this.downloads,
    required this.bookshelf,
    required this.bookSources,
    required this.readingProgress,
    required this.quizItems,
  });

  final int favorites;
  final int playHistory;
  final int downloads;
  final int bookshelf;
  final int bookSources;
  final int readingProgress;
  final int quizItems;

  int get total =>
      favorites +
      playHistory +
      downloads +
      bookshelf +
      bookSources +
      readingProgress +
      quizItems;

  /// 给用户看的一行摘要。只列非零项，避免一堆 0 淹没重点。
  String describe() {
    final parts = <String>[
      if (favorites > 0) '收藏 $favorites',
      if (playHistory > 0) '播放记录 $playHistory',
      if (downloads > 0) '下载 $downloads',
      if (bookshelf > 0) '书架 $bookshelf',
      if (bookSources > 0) '书源 $bookSources',
      if (readingProgress > 0) '阅读进度 $readingProgress',
      if (quizItems > 0) '题目 $quizItems',
    ];
    if (parts.isEmpty) return '备份内没有可迁移的数据';
    return parts.join(' · ');
  }
}
