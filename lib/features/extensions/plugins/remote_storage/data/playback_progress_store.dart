// 播放进度持久化（279 B3 续播）：按「账户 + 远端路径」记录播放位置。
//
// 只写 SharedPreferences（毫秒整数），不涉密；写入节流由播放页的定时器负责，
// 这里不做额外缓存——读一次要开一次 prefs 的代价远小于一次网络请求。

import 'package:shared_preferences/shared_preferences.dart';

import 'package:box/utils/app_logger.dart';
import 'package:box/utils/log_channels.dart';

import '../domain/playback_progress.dart';
import '../domain/remote_storage_models.dart';

/// 播放进度仓库。
class RemotePlaybackProgressStore {
  const RemotePlaybackProgressStore();

  /// 读取上次位置；没有记录时返回 null。
  Future<Duration?> positionFor(
    RemoteStorageAccount account,
    String path,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(playbackProgressKey(account.id, path));
    if (ms == null || ms <= 0) return null;
    return Duration(milliseconds: ms);
  }

  /// 记录位置。看完（[isPlaybackFinished]）或未到阈值时直接清除，避免留下
  /// "续播 3 秒""续播片尾"这类无意义记录。
  Future<void> save(
    RemoteStorageAccount account,
    String path, {
    required Duration position,
    required Duration duration,
  }) async {
    final link = playbackProgressKey(account.id, path);
    final prefs = await SharedPreferences.getInstance();
    if (!shouldResumePlayback(position, duration)) {
      await prefs.remove(link);
      return;
    }
    await prefs.setInt(link, position.inMilliseconds);
  }

  /// 清除记录（用户主动"从头播放"时调用）。
  Future<void> clear(RemoteStorageAccount account, String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(playbackProgressKey(account.id, path));
  }

  /// 清除某账户的**全部**进度记录（删账户时调用），返回清掉的条数。
  ///
  /// 不额外维护索引：SharedPreferences 能列出所有键，直接按前缀过滤即可。
  /// 索引方案看着更"正规"，但漏掉本次改动之前写下的历史键——而那正是要清的东西。
  Future<int> clearAccount(String accountId) async {
    final prefix = playbackProgressKeyPrefix(accountId);
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
      for (final key in keys) {
        await prefs.remove(key);
      }
      return keys.length;
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '清理播放进度失败（账户 $accountId）: $e',
        level: LogLevel.debug,
      );
      return 0;
    }
  }
}
