import 'dart:convert';

/// 备份包的纯 Dart 编解码器，避免把 Hive 的二进制对象直接暴露给文件格式。
///
/// 备份只保存应用数据，不包含视频文件本体；下载任务的 localPath 会保留，
/// 恢复后若文件仍存在即可继续使用，否则任务仍可被用户重新下载。
class LocalBackupCodec {
  static const format = 'box_local_backup';

  /// 当前写出的版本。
  ///
  /// v2 增加了 `prefs` 段（小说书架/书源/阅读进度等 SharedPreferences 资产）。
  /// v1 的备份文件里没有这一段，但仍然必须能恢复 —— 用户手上可能已经存了
  /// v1 备份，拒绝读会把「还能救回一部分」变成「完全救不回」。
  static const version = 2;

  /// 仍然接受的历史版本。
  static const supportedVersions = <int>{1, 2};

  static String encode({
    required Map<String, List<Map<String, dynamic>>> hiveBoxes,
    required String quizJson,
    Map<String, dynamic> prefs = const <String, dynamic>{},
  }) {
    return const JsonEncoder.withIndent('  ').convert({
      'format': format,
      'version': version,
      'exportedAt': DateTime.now().toIso8601String(),
      'quiz': jsonDecode(quizJson),
      'hive': hiveBoxes,
      'prefs': prefs,
    });
  }

  static LocalBackupData decode(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map ||
        value['format'] != format ||
        !supportedVersions.contains(value['version'])) {
      throw const FormatException('不是受支持的 Box 本地数据备份');
    }
    final hiveRaw = value['hive'];
    final quiz = value['quiz'];
    if (hiveRaw is! Map || quiz is! Map || quiz['items'] is! List) {
      throw const FormatException('备份文件内容不完整');
    }
    final hive = <String, List<Map<String, dynamic>>>{};
    for (final entry in hiveRaw.entries) {
      if (entry.key is! String || entry.value is! List) {
        throw const FormatException('备份中的 Hive 数据格式错误');
      }
      final records = <Map<String, dynamic>>[];
      for (final record in entry.value as List) {
        if (record is! Map ||
            record['key'] == null ||
            !record.containsKey('value')) {
          throw const FormatException('备份中的记录格式错误');
        }
        records.add(Map<String, dynamic>.from(record));
      }
      hive[entry.key as String] = records;
    }
    // v1 备份没有 prefs 段，按空处理而不是报错。
    final prefsRaw = value['prefs'];
    final prefs = <String, dynamic>{};
    if (prefsRaw is Map) {
      for (final entry in prefsRaw.entries) {
        if (entry.key is! String) {
          throw const FormatException('备份中的设置数据格式错误');
        }
        prefs[entry.key as String] = entry.value;
      }
    }
    return LocalBackupData(
      quizJson: jsonEncode(quiz),
      hiveBoxes: hive,
      prefs: prefs,
    );
  }
}

class LocalBackupData {
  const LocalBackupData({
    required this.quizJson,
    required this.hiveBoxes,
    this.prefs = const <String, dynamic>{},
  });
  final String quizJson;
  final Map<String, List<Map<String, dynamic>>> hiveBoxes;

  /// SharedPreferences 资产（小说书架/书源/阅读进度等）。v1 备份为空。
  final Map<String, dynamic> prefs;
}
