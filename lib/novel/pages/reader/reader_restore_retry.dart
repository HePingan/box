/// 恢复阅读位置时，PageView 可能还没 attach 到树上。
///
/// 背景（真机 bug）：进小窗/分屏时窗口高度变化会触发重算分页，重算那一帧
/// `_textPages` 被替换，reader 的 build 走了「没有页 → 转圈」分支，
/// `ReaderPagedView` 连同 `PageView` 整个从树上摘掉，`PageController` 随之
/// detach。此时 postFrame 里的恢复逻辑看到 `hasClients == false` 就直接
/// return，结果 `_pendingRestore` 永远停在 true —— 之后每次 `_saveProgress`
/// 都被闸门挡掉，正文再不刷新，用户看到的是永久转圈。放大到全屏后
/// PageView 正常挂载，`hasClients == true`，同一条路径立刻恢复正常。
///
/// 但也不能无脑重试：退出阅读页时 PageView 是真的没了，那种情况下继续用
/// postFrameCallback 自己排自己会一直烧帧。所以这里把「暂时 detach」和
/// 「已经没了」分开判断。
///
/// 抽成纯函数是为了能在没有 Flutter 树的情况下测到真实决策 —— 真机上这个
/// 分支只在特定机型的窗口切换时机才出现，靠 widget 测试很难稳定复现。
library;

/// 恢复动作。
enum ReaderRestoreAction {
  /// PageView 已就绪，立刻恢复位置。
  restoreNow,

  /// 暂时 detach，下一帧再试。注意：闸门必须继续持有，否则会存下错误页码。
  retryNextFrame,

  /// 不再尝试（页面已卸载 / 没有内容 / 重试超限）。闸门必须关掉。
  abandon,
}

/// PageView detach 时的重试决策。
class ReaderRestoreRetry {
  const ReaderRestoreRetry._();

  /// 最多排多少帧。
  ///
  /// 真机日志里从 `configuration_changed` 到 `after_layout` 约 36ms，60fps 下
  /// 是 2 帧多；慢机和冷启动会更久，所以留出余量。调大会让极端情况下多等
  /// 几帧（用户感知为转圈多持续几十毫秒），调小则可能在慢机上失手回到本 bug。
  /// 这个 8 是按上述日志推的启发式值，不是实测最优 —— 若还有机型复现，
  /// 需要真机日志里 detach 持续的帧数来调准。
  static const int maxAttempts = 8;

  /// 决定这一帧该做什么。
  static ReaderRestoreAction decide({
    required bool hasClients,
    required bool hasPages,
    required bool mounted,
    required int attempt,
  }) {
    if (!mounted) return ReaderRestoreAction.abandon;
    if (!hasPages) return ReaderRestoreAction.abandon;
    if (hasClients) return ReaderRestoreAction.restoreNow;
    if (attempt >= maxAttempts) return ReaderRestoreAction.abandon;
    return ReaderRestoreAction.retryNextFrame;
  }

  /// 这一步之后是否应该关掉 `_pendingRestore` 闸门。
  ///
  /// 只有「下一帧再来」时才继续持有：其余情况（恢复完成、彻底放弃）都必须
  /// 关掉，否则进度永久存不下来 —— 那正是本 bug 最伤的后果。
  static bool shouldCloseGate(ReaderRestoreAction action) =>
      action != ReaderRestoreAction.retryNextFrame;
}
