// 远程存储播放进度（279 B3 续播）的**纯逻辑**。
//
// 刻意不依赖 SharedPreferences / dart:io：这样单测不需要平台通道，web 构建也不用
// 条件编译（与 remote_storage_models.dart 的约定一致）。

/// 续播起点阈值：短于这个位置不值得记。
///
/// 片头试看、点错了立刻退出都会留下几秒进度；恢复它们只会让用户觉得"播放器乱跳"。
const Duration kResumeMinPosition = Duration(seconds: 15);

/// 看完判定比例：位置超过时长的这个比例就视为看完，下次从头播。
const double kResumeFinishedRatio = 0.95;

/// 该位置是否值得"下次继续播放"。
///
/// [duration] 未知（`Duration.zero`，某些流式响应拿不到总时长）时退化为只按位置判断：
/// 位置已过阈值就当可续播。
bool shouldResumePlayback(Duration position, Duration duration) {
  if (position < kResumeMinPosition) return false;
  if (duration <= Duration.zero) return true;
  return position < duration * kResumeFinishedRatio;
}

/// 是否算"已看完"（用于清除进度记录，避免下次又从片尾续起）。
bool isPlaybackFinished(Duration position, Duration duration) {
  if (duration <= Duration.zero) return false;
  return position >= duration * kResumeFinishedRatio;
}

/// 进度文案：`12:34` / `1:02:03`（提示"已从 12:34 继续播放"用）。
String formatPlaybackPosition(Duration position) {
  final total = position.inSeconds < 0 ? 0 : position.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  final mm = hours > 0 ? minutes.toString().padLeft(2, '0') : minutes.toString();
  final ss = seconds.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

/// SharedPreferences 键：账户 + 远端路径。
///
/// 用账户 id 做前缀而不是只用路径：同一个 Dropbox/坚果云路径可能挂在两个账户下，
/// 只按路径存会让两个账户互相覆盖进度。
String playbackProgressKey(String accountId, String path) =>
    'remoteStorage.playback.$accountId|$path';
