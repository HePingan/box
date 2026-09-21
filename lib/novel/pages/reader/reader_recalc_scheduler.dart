/// 分页重排的「合并到帧末」调度器。
///
/// ## 为什么需要它
///
/// 重排分页很贵（`TextPainter` 逐页测量），所以同一帧里来的多次请求必须合并成
/// 一次。原先在 `reader_page.dart` 里是这么写的：
///
/// ```dart
/// if (_pageCalcScheduled) return;      // ← 丢帧竞态
/// _pageCalcScheduled = true;
/// WidgetsBinding.instance.addPostFrameCallback((_) {
///   _pageCalcScheduled = false;
///   _calculatePages(fitWidth, firstPageHeight, normalPageHeight);  // 闭包捕获的是第一次的尺寸
/// });
/// ```
///
/// 合并的意图是对的，实现方式错了：**它保留第一次的尺寸、丢弃后续所有更新**。
/// 而调用点 `reader_page.dart` 会在请求的同一帧里立刻把 `_lastFitWidth`
/// 更新成最新值，于是两者永久错位：
///
/// ```
/// 帧 A  fitWidth=344 → _lastFitWidth=344，排期(344)
/// 帧 B  fitWidth=248 → _lastFitWidth=248，请求被 return 丢掉
/// 帧末  _calculatePages(344)              ← 按全屏宽度分页
/// 帧 C  fitWidth=248 == _lastFitWidth     ← 判定「尺寸没变」，不再排期
/// ```
///
/// 结果：分页结果按 344dp 排版，窗口实际只有 248dp，而且**再没有任何一帧
/// 能触发重排**。用户看到永久 spinner；放大回全屏时尺寸又变一次、重新排期
/// 才恢复 —— 正是「小窗转圈、全屏正常」这个现象。
///
/// 小窗切换恰好高频触发：一次进出会连发 `configuration_changed` 中间态和
/// 稳定态两三帧，中间态被采纳、稳定态被丢弃的概率很高。全屏下尺寸一步到位，
/// 所以平时完全看不出问题。
///
/// ## 语义
///
/// 合并保留**最后一次**请求的尺寸。这是「重排」这个动作的正确语义：中间态
/// 的尺寸已经过时，没有任何理由按它排版。
class ReaderRecalcScheduler {
  ReaderRecalcScheduler({required this.run, this.schedule});

  /// 真正执行重排。参数依次为 fitWidth / firstPageHeight / normalPageHeight。
  final void Function(double fitWidth, double firstHeight, double normalHeight)
      run;

  /// 把 [flush] 排到帧末。生产环境传 `addPostFrameCallback`；
  /// 测试里不传，手动调 [flush]，从而不需要 Flutter binding。
  final void Function(void Function() callback)? schedule;

  double? _fitWidth;
  double? _firstHeight;
  double? _normalHeight;
  bool _scheduled = false;

  /// 是否有待处理的重排请求。
  bool get hasPending => _fitWidth != null;

  /// 请求一次重排。同一帧内多次调用只会执行一次，且用**最后一次**的尺寸。
  void request({
    required double fitWidth,
    required double firstHeight,
    required double normalHeight,
  }) {
    // 关键：无条件覆盖。旧实现在这里 return，把最新尺寸丢了。
    _fitWidth = fitWidth;
    _firstHeight = firstHeight;
    _normalHeight = normalHeight;

    if (_scheduled) return;
    _scheduled = true;
    schedule?.call(flush);
  }

  /// 执行待处理的重排（帧末回调，或测试里手动调）。
  void flush() {
    _scheduled = false;

    final w = _fitWidth;
    final f = _firstHeight;
    final n = _normalHeight;
    if (w == null || f == null || n == null) return;

    _fitWidth = null;
    _firstHeight = null;
    _normalHeight = null;

    run(w, f, n);
  }

  /// 丢弃待处理请求。`dispose()` 时调，避免帧末回调打到已销毁的 State 上。
  void cancel() {
    _fitWidth = null;
    _firstHeight = null;
    _normalHeight = null;
    _scheduled = false;
  }
}
