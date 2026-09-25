// 传输队列落盘（284 P1）。
//
// 为什么需要：队列原本是纯内存的，app 被杀或系统回收后"排队中/在传"的任务全部消失，
// 用户得重新点一遍（下载虽然落了 .part 可以续传，但队列本身没了）。
//
// 设计取舍：
// - 只落**单文件 JSON**（不用 SharedPreferences 塞大数组），文件坏了当"没有"处理，
//   不让一条脏记录卡住整个恢复流程；
// - 只落"重建 runner 需要的字段"（见 [TransferRestoreSpec]），UI 文案/回调不入库；
// - 条数上限 [kMaxPersistedTasks]：只留最新的若干条，剩下的宁可丢也不要写一个
//   几 MB 的文件。

import 'dart:convert';
import 'dart:io';

import 'package:box/utils/app_logger.dart';
import 'package:box/utils/log_channels.dart';
import 'package:path_provider/path_provider.dart';

class TransferQueueStore {
  TransferQueueStore({Future<Directory> Function()? dirProvider})
      : _dirProvider = dirProvider ?? getApplicationDocumentsDirectory;

  /// 文件放应用文档目录（和账户/偏好同一处）。
  static const String fileName = 'remote_storage_transfer_queue.json';

  /// 最多落多少条：超了只留最新的（[records] 已按"新的在前"排好）。
  static const int kMaxPersistedTasks = 200;

  final Future<Directory> Function() _dirProvider;

  Future<File> _file() async {
    final dir = await _dirProvider();
    return File('${dir.path}/$fileName');
  }

  /// 读回记录；文件不存在/读不出来/JSON 坏了/不是数组 → 一律返回空表。
  Future<List<Map<String, Object?>>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map) item.map((k, v) => MapEntry('$k', v)),
      ];
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '读取传输队列落盘失败（按空处理）: $e',
        level: LogLevel.debug,
      );
      return const [];
    }
  }

  Future<void> save(List<Map<String, Object?>> records) async {
    try {
      final file = await _file();
      final kept = records.length > kMaxPersistedTasks
          ? records.sublist(0, kMaxPersistedTasks)
          : records;
      // 先写临时文件再改名：写一半被杀不会留下半个 JSON 把下次恢复毒掉。
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(kept), flush: true);
      await temp.rename(file.path);
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '写传输队列落盘失败: $e',
        level: LogLevel.debug,
      );
    }
  }

  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '清传输队列落盘失败: $e',
        level: LogLevel.debug,
      );
    }
  }
}
