/// ⑥B 后台播放的判定（纯逻辑，单独放出来是为了能单测）。
///
/// 为什么要抽出来：这类「切后台到底该不该继续出声」的判断一旦写在 State 里，
/// 就没人能证明它对了 —— 而这正是最容易把「息屏听剧」做坏的地方。
class PlaybackBackgroundPolicy {
  const PlaybackBackgroundPolicy();

  /// 切后台 / 息屏 / 进小窗时，播放该不该继续。
  ///
  /// - [isPlaying] 本来就没在播 → 没什么可保活的；
  /// - [isPip] 小窗态**不算后台**（画面还在，用户就是要它继续）；
  /// - 其余情况看用户开关（关掉就退回老行为：切后台即暂停）。
  static bool shouldKeepPlaying({
    required bool enabled,
    required bool isPlaying,
    required bool isPip,
  }) {
    if (!isPlaying) return false;
    if (isPip) return true;
    return enabled;
  }

  /// 回到前台要不要恢复播放。
  ///
  /// 后台保活时它**一直在播**，这时再 play() 等于多此一举，
  /// 还可能把用户刚在通知栏按下的暂停又顶回去 —— 所以只在不保活时才恢复。
  static bool shouldResumeOnForeground({
    required bool keptPlaying,
    required bool wasPlayingBeforeBackground,
  }) {
    if (keptPlaying) return false;
    return wasPlayingBeforeBackground;
  }

  /// 该不该挂前台服务（媒体通知 + 进程保活）。
  ///
  /// 关键：**必须在前台就挂起来**。Android 12+ 不允许 App 退到后台之后再启动
  /// 前台服务（ForegroundServiceStartNotAllowedException），所以「等切后台再挂」
  /// 的方案在现代系统上会直接失败 —— 判据因此只看「开关 + 正在播」，不看 lifecycle。
  static bool shouldRunService({
    required bool enabled,
    required bool isPlaying,
    required bool isPip,
  }) =>
      enabled && isPlaying && !isPip;
}
