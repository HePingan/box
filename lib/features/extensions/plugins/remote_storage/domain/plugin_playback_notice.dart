/// ⑥B 后台播放：远程存储播放器的通知文案与通知按钮映射。
///
/// 抽成纯函数的原因和 [PlaybackBackgroundPolicy] 一样：这类「通知上到底该写什么、
/// 按钮该做什么」的判断一旦埋进 State，就没人能证明它对了；而它正是用户在锁屏界面上
/// 唯一能看到的反馈。
library;

/// 通知栏「上一首/下一首」在单曲场景下的步进量。
///
/// 白噪音/电台是单曲循环，没有下一首可言；按钮留着却什么都不做比没有更差，
/// 所以映射成前后 15 秒 —— 长音频里这也是用户真的会用的操作。
const Duration kPlaybackSeekStep = Duration(seconds: 15);

class PluginPlaybackNotice {
  const PluginPlaybackNotice._();

  /// 通知标题：循环播放时带上「循环」，否则用户看到一条静止的标题会以为卡住了。
  static String title({required String entryName, required bool looping}) {
    final name = entryName.trim();
    final base = name.isEmpty ? '远程存储' : name;
    return looping ? '$base · 循环' : base;
  }

  /// 通知副文案。
  static String text({required bool playing, required bool isAudio}) {
    if (!playing) return '已暂停';
    return isAudio ? '正在播放 · 可在通知栏暂停' : '正在后台播放';
  }

  /// 通知按钮 → 进度增量；不认识的命令返回 null（交给调用方忽略）。
  ///
  /// 值必须与 [PlaybackNotificationChannel] 的命令常量一致，
  /// 这里用字面量是为了让本文件不依赖平台通道。
  static Duration? seekDeltaFor(String command) {
    switch (command) {
      case 'previous':
        return -kPlaybackSeekStep;
      case 'next':
        return kPlaybackSeekStep;
      default:
        return null;
    }
  }
}
