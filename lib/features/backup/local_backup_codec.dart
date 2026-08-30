import 'dart:convert';

/// 备份包的纯 Dart 编解码器，避免把 Hive 的二进制对象直接暴露给文件格式。
///
/// 备份只保存应用数据，不包含视频文件本体；下载任务的 localPath 会保留，
/// 恢复后若文件仍存在即可继续使用，否则任务仍可被用户重新下载。
class LocalBackupCodec {
  static const format = 'box_local_backup';
  static const version = 1;

  static String encode({
    required Map<String, List<Map<String, dynamic>>> hiveBoxes,
    required String quizJson,
  }) {
    return const JsonEncoder.withIndent('  ').convert({
      'format': format,
      'version': version,
      'exportedAt': DateTime.now().toIso8601String(),
      'quiz': jsonDecode(quizJson),
      'hive': hiveBoxes,
    });
  }

  static LocalBackupData decode(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map ||
        value['format'] != format ||
        value['version'] != version) {
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
    return LocalBackupData(quizJson: jsonEncode(quiz), hiveBoxes: hive);
  }
}

class LocalBackupData {
  const LocalBackupData({required this.quizJson, required this.hiveBoxes});
  final String quizJson;
  final Map<String, List<Map<String, dynamic>>> hiveBoxes;
}
