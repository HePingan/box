import 'dart:io';

import 'package:box/novel/pages/reader/reader_recalc_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

/// 小窗 → 全屏切换时正文永久转圈的回归锁。
///
/// 真实现象（朋友的红米，1.12.0+205）：小说阅读器调成小窗后一直转圈看不了，
/// 放大回全屏就恢复。日志侧两层都正常（`window_focus` / `viewport metrics`
/// 都按 384x853 → 384x614 → 384x853 走完，19ms 内完成，无 timeout），
/// 所以问题在 Flutter 内部的重排调度，不在窗口层。
///
/// 根因是 `_schedulePageRecalc` 的**丢帧竞态**（reader_page.dart:394-407）：
///
/// ```
/// 帧 A: fitWidth=344 → _lastFitWidth=344, 排期(344), _pageCalcScheduled=true
/// 帧 B: fitWidth=248 → _lastFitWidth=248, 排期被 `if (_pageCalcScheduled) return` 丢掉
/// post-frame: _calculatePages(344)   ← 用帧 A 的旧宽度分页
/// 帧 C: fitWidth=248 == _lastFitWidth(248) → 判定「没变」，不再排期
/// ```
///
/// 于是分页结果是按 344dp 排的、`_lastFitWidth` 记的是 248dp，两者永久不一致，
/// 而且再没有任何一帧能触发重排 —— `_textPages` 停在旧宽度的结果或空列表，
/// spinner 永久转圈。放大回全屏会再变一次尺寸，重新排期一次才恢复，
/// 与用户「放大就正常」的描述完全一致。
///
/// 关键点：**丢掉的那一帧必须补跑**。合并（coalesce）是对的，
/// 但合并后要用**最后一次**的尺寸，不是第一次的。
void main() {
  group('ReaderRecalcScheduler 尺寸合并', () {
    test('同一帧内多次请求只跑一次，且用最后一次的尺寸', () {
      final runs = <List<double>>[];
      final scheduler = ReaderRecalcScheduler(
        run: (w, f, n) => runs.add([w, f, n]),
      );

      scheduler.request(fitWidth: 344, firstHeight: 700, normalHeight: 760);
      scheduler.request(fitWidth: 248, firstHeight: 500, normalHeight: 560);
      scheduler.request(fitWidth: 248, firstHeight: 480, normalHeight: 540);

      expect(runs, isEmpty, reason: '排期后不该同步执行');

      scheduler.flush();

      expect(runs.length, 1, reason: '一帧内多次请求应合并为一次');
      expect(
        runs.single,
        [248.0, 480.0, 540.0],
        reason: '必须用最后一次的尺寸；用第一次的就是小窗永久转圈的根因',
      );
    });

    test('中途尺寸变化不会被丢掉（小窗切换的真实序列）', () {
      final runs = <double>[];
      final scheduler = ReaderRecalcScheduler(
        run: (w, _, _) => runs.add(w),
      );

      // 全屏 384dp - 40 padding = 344
      scheduler.request(fitWidth: 344, firstHeight: 700, normalHeight: 760);
      // 小窗中间态，还没稳定
      scheduler.request(fitWidth: 300, firstHeight: 600, normalHeight: 640);
      // 小窗稳定值 384x614 那一帧
      scheduler.request(fitWidth: 248, firstHeight: 420, normalHeight: 470);
      scheduler.flush();

      expect(runs, [248.0], reason: '应落在小窗最终宽度上，而不是全屏的 344');
    });

    test('flush 后再请求会重新排期', () {
      final runs = <double>[];
      final scheduler = ReaderRecalcScheduler(
        run: (w, _, _) => runs.add(w),
      );

      scheduler.request(fitWidth: 344, firstHeight: 700, normalHeight: 760);
      scheduler.flush();
      scheduler.request(fitWidth: 248, firstHeight: 420, normalHeight: 470);
      scheduler.flush();

      expect(runs, [344.0, 248.0]);
    });

    test('没有待处理请求时 flush 不执行任何东西', () {
      var calls = 0;
      final scheduler = ReaderRecalcScheduler(
        run: (_, _, _) => calls++,
      );

      scheduler.flush();
      expect(calls, 0);
    });

    test('cancel 丢弃待处理请求', () {
      var calls = 0;
      final scheduler = ReaderRecalcScheduler(
        run: (_, _, _) => calls++,
      );

      scheduler.request(fitWidth: 344, firstHeight: 700, normalHeight: 760);
      scheduler.cancel();
      scheduler.flush();

      expect(calls, 0, reason: 'dispose 之后不该再跑分页');
    });

    test('hasPending 反映排期状态', () {
      final scheduler = ReaderRecalcScheduler(run: (_, _, _) {});

      expect(scheduler.hasPending, isFalse);
      scheduler.request(fitWidth: 344, firstHeight: 700, normalHeight: 760);
      expect(scheduler.hasPending, isTrue);
      scheduler.flush();
      expect(scheduler.hasPending, isFalse);
    });
  });

  group('源码级闸门', () {
    test('reader_page 必须走 ReaderRecalcScheduler，且不得留下丢帧形状', () {
      final src = _readerPageSource();

      expect(
        src.contains('ReaderRecalcScheduler'),
        isTrue,
        reason: '调用点被改回手写 _pageCalcScheduled 了？小窗永久转圈会复活',
      );
      // 只看活代码：注释里会引用旧形状来解释这个 bug，不能算命中。
      final code = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');

      expect(
        RegExp(r'if\s*\(\s*_pageCalcScheduled\s*\)\s*return').hasMatch(code),
        isFalse,
        reason: '「已排期就直接 return」正是丢掉最新尺寸的元凶形状',
      );
      expect(
        code.contains('_pageCalcScheduled'),
        isFalse,
        reason: '这个字段应随调度器抽出而删除，留着会被后人当成还在用',
      );
    });
  });
}

String _readerPageSource() {
  // ignore: avoid_slow_async_io
  return _file('lib/novel/pages/reader_page.dart');
}

String _file(String path) {
  final f = File(path);
  if (!f.existsSync()) {
    fail('找不到生产源文件 $path —— 源码级闸门失效');
  }
  return f.readAsStringSync();
}
