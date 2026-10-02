/// 线路失败计数（纯逻辑，可单测）。
///
/// 为什么单独抽出来：这段逻辑原来写在 `VideoPlayContainer` 的 State 里，
/// 阈值判断是 `_consecutiveFailures >= 2`，但同一个 `hasError` 分支紧接着
/// 调用的 `_failFast()` 会把计数器清零、`_initPlayer()` 每次重试也清零一次，
/// 于是计数器永远到不了 2 —— 「换线重试仍然失败就自动换线路」这条功能
/// 从来没有生效过（2026-10-02 定位）。抽成纯类之后，用例可以钉住
/// 「重试之间计数器不许被清零」这条真正的约束。
///
/// 语义：
/// - [recordFailure] 记一次硬失败（起播失败或播放中报错）；
/// - `decisive` 用于**不需要再试**的失败（例如地址是网页线路，重试一定还是失败）；
/// - [recordPlaybackStarted] 只在**真正起播成功**时清零——不是「这次没报错」就清零。
class LineFailoverPolicy {
  LineFailoverPolicy({this.threshold = 2}) : assert(threshold > 0);

  /// 连续失败到几次才自动换线路。
  final int threshold;

  int _failures = 0;

  /// 当前连续失败次数。
  int get failures => _failures;

  /// 记一次失败。返回 true = 应该换线路，而不是把错误丢给用户。
  bool recordFailure({required bool hasFallbackLine, bool decisive = false}) {
    _failures++;
    if (!hasFallbackLine) {
      // 已经没有别的线路可换了，计数没有意义，别让残留值影响下一次。
      _failures = 0;
      return false;
    }
    if (decisive || _failures >= threshold) {
      _failures = 0;
      return true;
    }
    return false;
  }

  /// 真正起播成功后清零。
  void recordPlaybackStarted() {
    _failures = 0;
  }
}
