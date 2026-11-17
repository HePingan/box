/// 「AI 作答过程」推送的合并器。
///
/// 为什么需要它（2026-11-17 真机报障「一直读屏闪烁」）：过程区块每推一行，
/// 原生悬浮窗就要整块重绘一次。读屏链路在压缩/请求/重试阶段会连续推 4~6 次，
/// 真机上肉眼看到的就是闪。合并规则只有两条：
///
///   1. **内容没变就不推**（同一段文字反复推没有意义，只是重绘）；
///   2. **[minIntervalMs] 内的推送合并掉**，终态用 `force: true` 兜底，
///      所以最后那行「④ 识别成功」或「✖ 失败」永远不会被节流吃掉。
///
/// 时钟可注入，便于单测（不依赖真实时间）。
class QuizProcThrottle {
  QuizProcThrottle({
    this.minIntervalMs = 250,
    int Function()? clock,
  }) : _clock = clock ?? _nowMs;

  static int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  /// 两次推送之间至少间隔多久（毫秒）。0 = 只做「内容去重」。
  final int minIntervalMs;
  final int Function() _clock;

  String _lastText = '';
  int _lastAtMs = 0;
  int _pushed = 0;
  int _skipped = 0;

  /// 真正推出去的次数（自检/单测用）。
  int get pushed => _pushed;

  /// 被合并掉的次数（自检/单测用）。
  int get skipped => _skipped;

  /// 这次要不要推。[force] = 终态，必须推。
  bool shouldPush(String text, {bool force = false}) {
    final now = _clock();
    if (!force) {
      if (text == _lastText) {
        _skipped++;
        return false;
      }
      if (minIntervalMs > 0 && now - _lastAtMs < minIntervalMs) {
        _skipped++;
        return false;
      }
    }
    _lastText = text;
    _lastAtMs = now;
    _pushed++;
    return true;
  }

  /// 换题/新一轮时清空去重状态（否则新一题的相同首行会被当成「没变」而吞掉）。
  void reset() {
    _lastText = '';
    _lastAtMs = 0;
  }
}
