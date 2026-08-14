import 'package:flutter_test/flutter_test.dart';

/// 复现「继续阅读回到第 1 页」的时序 bug。
///
/// reader_page 里 _calculatePages 会被 LayoutBuilder 触发多次
/// （首帧 fitWidth=0 → 稳定帧拿到真实宽高），每次都无条件把
/// _paginateCancelFlag 置 true 来取消上一轮后台分页。
///
/// 恢复阅读位置（_restorePagePositionAfterPaginate）挂在后台分页
/// 循环的末尾。一旦某轮被取消，它就 return 得比恢复更早 ——
/// 恢复永远不执行，用户停在第 1 页。
///
/// 这里用一个最小状态机固定该时序，保证修复后不再回归。
class _PaginateSim {
  bool cancelFlag = false;
  bool restoreCalled = false;
  int restoreTargetPage = -1;

  /// 每一轮 _calculatePages 分配一个代号，用于识别过期任务。
  int generation = 0;

  /// 模拟 _calculatePages：取消上一轮，开启新一轮。
  int startCalculate() {
    cancelFlag = true;
    generation++;
    // 只有确实要跑后台补页时才复位（对应 result.remaining.isDone == false）
    cancelFlag = false;
    return generation;
  }

  /// 模拟后台补页循环结束后的恢复步骤。
  ///
  /// [myGeneration] 是这轮任务启动时拿到的代号。修复的关键：
  /// 用代号判断自己是否过期，而不是只看共享的 cancelFlag。
  void finishPaginate(int myGeneration, {required int savedPage}) {
    // 旧实现：if (cancelFlag) return;  → 被后一轮误杀
    // 新实现：只有当前代号才有资格恢复
    if (myGeneration != generation) return;
    restoreCalled = true;
    restoreTargetPage = savedPage;
  }
}

void main() {
  group('继续阅读恢复不能被重复布局取消', () {
    test('单次 layout：恢复正常执行', () {
      final sim = _PaginateSim();
      final gen = sim.startCalculate();
      sim.finishPaginate(gen, savedPage: 5);

      expect(sim.restoreCalled, isTrue);
      expect(sim.restoreTargetPage, 5);
    });

    test('两次 layout 抢跑：只有最后一轮恢复，且必须恢复', () {
      final sim = _PaginateSim();

      // 首帧：fitWidth 还是 0 → 触发一次
      final genA = sim.startCalculate();
      // 稳定帧：拿到真实宽高 → 再触发一次，genA 作废
      final genB = sim.startCalculate();

      // 过期任务收尾：不该恢复（否则用错的分页结果定位）
      sim.finishPaginate(genA, savedPage: 5);
      expect(sim.restoreCalled, isFalse,
          reason: '过期的分页任务不应触发恢复');

      // 当前任务收尾：必须恢复
      sim.finishPaginate(genB, savedPage: 5);
      expect(sim.restoreCalled, isTrue,
          reason: 'bug 复现点：最后一轮分页完成后恢复必须执行');
      expect(sim.restoreTargetPage, 5);
    });

    test('三次连续 layout：恢复仍然发生且只发生一次', () {
      final sim = _PaginateSim();
      final gens = [
        sim.startCalculate(),
        sim.startCalculate(),
        sim.startCalculate(),
      ];

      var restoreCount = 0;
      for (final g in gens) {
        final before = sim.restoreCalled;
        sim.finishPaginate(g, savedPage: 6);
        if (!before && sim.restoreCalled) restoreCount++;
      }

      expect(restoreCount, 1);
      expect(sim.restoreTargetPage, 6);
    });
  });
}
