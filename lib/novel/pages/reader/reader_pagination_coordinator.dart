import 'reader_paginator.dart';

/// 后台补页的数据源。
///
/// 只暴露协调器真正需要的两个能力，这样测试可以塞一个假源进来，
/// 不必构造真的 [IncrementalPageIterator]（那个要跑 TextPainter，
/// 依赖字体度量，在纯 Dart 测试里既慢又不稳）。
class ReaderChunkSource {
  const ReaderChunkSource({required this.isDone, required this.nextChunk});

  /// 包装真实分页迭代器。
  factory ReaderChunkSource.fromIterator(IncrementalPageIterator iterator) {
    return ReaderChunkSource(
      isDone: () => iterator.isDone,
      nextChunk: iterator.nextChunk,
    );
  }

  final bool Function() isDone;
  final List<String> Function() nextChunk;
}

/// 分页轮次仲裁 + 后台补页节奏。
///
/// 这块逻辑原本散在 `_ReaderPageState` 的 `_calculatePages` /
/// `_paginateRemaining` 里，和 `setState`、`addPostFrameCallback` 缠在一起，
/// 结果是「代数计数器」「取消标志」「刷新节奏」三件事都无法单独验证——
/// 而这三件事恰好是历史上出过真 bug 的地方：
///
/// - LayoutBuilder 会在首帧（fitWidth 还是 0）和稳定帧各触发一次分页，
///   同一章因此可能连开两轮。旧实现里两轮共用一个取消标志，后一轮把
///   前一轮 cancel 掉之后，前一轮在补页循环中途 return —— 而「恢复阅读
///   位置」挂在那个循环末尾，于是恢复永远不执行，用户停在第 1 页。
///   修法是每轮领一个代号，只有代号仍是最新的那轮才收尾。
///
/// - 补页循环每 2 个 chunk 刷一次 UI。循环退出时可能还剩 1 个没刷的
///   chunk，必须在收尾时一并写回，否则本章最后几页会丢、翻不到章末。
///
/// 抽出来之后这两条都能用 fake_async 直接验证，不需要真机。
/// Flutter 相关的副作用（setState / postFrameCallback）留给调用方，
/// 通过回调注入。
class ReaderPaginationCoordinator {
  ReaderPaginationCoordinator({
    this.flushEveryChunks = 2,
    this.yieldDelay = const Duration(milliseconds: 1),
  })  : assert(flushEveryChunks > 0, 'flushEveryChunks 必须为正数'),
        assert(!yieldDelay.isNegative, 'yieldDelay 不能为负');

  /// 累积多少个 chunk 刷一次 UI。调大减少重建次数，调小让页数增长更平滑。
  final int flushEveryChunks;

  /// 每算一个 chunk 后让出事件循环的时长。
  ///
  /// 必须 > 0：分页是 CPU 密集的同步计算，不让出会把整帧卡住。
  final Duration yieldDelay;

  int _generation = 0;
  bool _cancelFlag = false;

  /// 当前最新轮次代号。
  int get generation => _generation;

  /// 取消标志的当前状态。仅供断言与测试观察。
  bool get isCancelled => _cancelFlag;

  /// 开启新一轮：取消在跑的旧轮，代号自增并返回本轮代号。
  ///
  /// 返回值必须由调用方持有并在收尾时用于 [isCurrent] 判定。
  int beginRound() {
    _cancelFlag = true;
    return ++_generation;
  }

  /// 后台补页正式开始前放开取消标志。
  ///
  /// [beginRound] 会把标志置为 true 以掐断旧轮；本轮真正要跑之前必须
  /// 放开，否则第一次 stale 检查就把自己判死。
  void armBackgroundRound() {
    _cancelFlag = false;
  }

  /// 主动取消当前在跑的补页（例如切章、清空分页状态时）。
  void cancel() {
    _cancelFlag = true;
  }

  /// [generation] 是否仍是最新一轮。
  ///
  /// 收尾动作（恢复阅读位置、关闭恢复闸门）只认最新轮，过期轮安静退出。
  bool isCurrent(int generation) => generation == _generation;

  /// 本轮是否已作废：调用方已销毁、被新一轮顶替、或被显式取消。
  bool isStale(int generation, {required bool mounted}) {
    return !mounted || generation != _generation || _cancelFlag;
  }

  /// 后台逐块补齐分页。
  ///
  /// 每算一个 chunk 就让出事件循环，避免阻塞 UI。累积到
  /// [flushEveryChunks] 个 chunk 触发一次 [onFlush]；全部算完后触发
  /// [onComplete]，并把最后一批不足 [flushEveryChunks] 的余量一起带出去。
  ///
  /// 任何一次 stale 检查失败都立即返回，且**不**触发 [onComplete] ——
  /// 过期轮次不能代替新轮做收尾。
  Future<void> drain({
    required ReaderChunkSource source,
    required int generation,
    required List<String> initialPages,
    required bool Function() mounted,
    required void Function(List<String> pages) onFlush,
    required void Function(List<String> pages) onComplete,
  }) async {
    final accumulated = <String>[...initialPages];
    var pendingChunks = 0;

    // 每次都重新调用 mounted()，不能提前求值存起来：
    // 判定点之间隔着 await，State 随时可能被 dispose。
    bool stale() => isStale(generation, mounted: mounted());

    while (!source.isDone()) {
      await Future<void>.delayed(yieldDelay);

      if (stale()) return;

      final chunk = source.nextChunk();
      // 空 chunk 意味着源已经吐不出东西了。不 break 会死循环：
      // isDone 可能因为边界条件仍返回 false。
      if (chunk.isEmpty) break;

      accumulated.addAll(chunk);
      pendingChunks++;

      if (pendingChunks >= flushEveryChunks) {
        if (stale()) return;
        onFlush(List<String>.unmodifiable(accumulated));
        pendingChunks = 0;
      }
    }

    if (stale()) return;

    // 无条件收尾，不看 pendingChunks 是否为 0：
    // 循环可能在刷新过后立刻退出（pendingChunks == 0），此时页面列表
    // 已经是完整的，但 _paginatingRemaining 这类「排版中」状态仍需关掉。
    onComplete(List<String>.unmodifiable(accumulated));
  }
}
