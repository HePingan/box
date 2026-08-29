import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/novel/pages/reader/reader_pagination_coordinator.dart';

/// 一个可编程的假 chunk 源。
///
/// 真的 IncrementalPageIterator 要跑 TextPainter、依赖字体度量，在纯 Dart
/// 测试里既慢又受平台字体影响。协调器要验的是「轮次仲裁」和「刷新节奏」，
/// 跟真实排版结果无关，所以喂假页最合适。
class _FakeSource {
  _FakeSource(List<List<String>> chunks) : _chunks = List.of(chunks);

  final List<List<String>> _chunks;
  int _cursor = 0;

  /// nextChunk 被调用的次数。用于验证 stale 之后不再拉取。
  int pulls = 0;

  ReaderChunkSource get source => ReaderChunkSource(
        isDone: () => _cursor >= _chunks.length,
        nextChunk: () {
          pulls++;
          if (_cursor >= _chunks.length) return const <String>[];
          return _chunks[_cursor++];
        },
      );
}

void main() {
  group('轮次仲裁（代数计数器）', () {
    test('beginRound 每次自增并返回新代号', () {
      final c = ReaderPaginationCoordinator();
      expect(c.beginRound(), 1);
      expect(c.beginRound(), 2);
      expect(c.generation, 2);
    });

    test('beginRound 会掐断在跑的旧轮', () {
      final c = ReaderPaginationCoordinator();
      c.armBackgroundRound();
      expect(c.isCancelled, isFalse);

      c.beginRound();
      // 新一轮开启的瞬间必须把取消标志举起来，否则旧轮会继续跑到收尾，
      // 和新轮抢着写 _textPages
      expect(c.isCancelled, isTrue);
    });

    test('只有最新代号被认为 current', () {
      final c = ReaderPaginationCoordinator();
      final first = c.beginRound();
      final second = c.beginRound();

      expect(c.isCurrent(first), isFalse);
      expect(c.isCurrent(second), isTrue);
    });

    test('isStale 三个条件各自独立生效', () {
      final c = ReaderPaginationCoordinator();
      final gen = c.beginRound();
      c.armBackgroundRound();

      // 正常在跑
      expect(c.isStale(gen, mounted: true), isFalse);
      // 调用方已销毁
      expect(c.isStale(gen, mounted: false), isTrue);
      // 被显式取消
      c.cancel();
      expect(c.isStale(gen, mounted: true), isTrue);
      // 被新一轮顶替
      final c2 = ReaderPaginationCoordinator();
      final old = c2.beginRound();
      c2.beginRound();
      c2.armBackgroundRound();
      expect(c2.isStale(old, mounted: true), isTrue);
    });

    test('armBackgroundRound 放开取消标志，否则本轮自己判死', () {
      final c = ReaderPaginationCoordinator();
      final gen = c.beginRound();
      // beginRound 举了标志，此时本轮如果直接跑会立刻 stale
      expect(c.isStale(gen, mounted: true), isTrue);

      c.armBackgroundRound();
      expect(c.isStale(gen, mounted: true), isFalse);
    });
  });

  group('drain 刷新节奏', () {
    test('每 flushEveryChunks 个 chunk 刷一次，收尾补齐余量', () {
      fakeAsync((async) {
        final c = ReaderPaginationCoordinator(flushEveryChunks: 2);
        // 3 个 chunk：第 2 个触发一次 flush，第 3 个是余量
        final fake = _FakeSource([
          ['p1', 'p2'],
          ['p3'],
          ['p4'],
        ]);
        final flushes = <List<String>>[];
        List<String>? completed;

        final gen = c.beginRound();
        c.armBackgroundRound();
        c.drain(
          source: fake.source,
          generation: gen,
          initialPages: const ['p0'],
          mounted: () => true,
          onFlush: flushes.add,
          onComplete: (pages) => completed = pages,
        );
        async.elapse(const Duration(seconds: 1));

        expect(flushes.length, 1);
        expect(flushes.single, ['p0', 'p1', 'p2', 'p3']);
        // 关键回归：最后那个未满批的 chunk 必须出现在收尾结果里，
        // 漏掉的话本章最后几页会丢，用户翻不到章末
        expect(completed, ['p0', 'p1', 'p2', 'p3', 'p4']);
      });
    });

    test('chunk 数刚好整除时仍然收尾（页数已全但状态要关）', () {
      fakeAsync((async) {
        final c = ReaderPaginationCoordinator(flushEveryChunks: 2);
        final fake = _FakeSource([
          ['p1'],
          ['p2'],
        ]);
        final flushes = <List<String>>[];
        List<String>? completed;

        final gen = c.beginRound();
        c.armBackgroundRound();
        c.drain(
          source: fake.source,
          generation: gen,
          initialPages: const [],
          mounted: () => true,
          onFlush: flushes.add,
          onComplete: (pages) => completed = pages,
        );
        async.elapse(const Duration(seconds: 1));

        expect(flushes.length, 1);
        // 即使 flush 刚发生过、没有余量，onComplete 也必须触发：
        // 「排版中」角标要靠它关掉
        expect(completed, ['p1', 'p2']);
      });
    });

    test('累积是递增的，每次 flush 都带全量页', () {
      fakeAsync((async) {
        final c = ReaderPaginationCoordinator(flushEveryChunks: 1);
        final fake = _FakeSource([
          ['a'],
          ['b'],
          ['c'],
        ]);
        final flushes = <List<String>>[];

        final gen = c.beginRound();
        c.armBackgroundRound();
        c.drain(
          source: fake.source,
          generation: gen,
          initialPages: const [],
          mounted: () => true,
          onFlush: flushes.add,
          onComplete: (_) {},
        );
        async.elapse(const Duration(seconds: 1));

        expect(flushes.map((f) => f.toList()), [
          ['a'],
          ['a', 'b'],
          ['a', 'b', 'c'],
        ]);
      });
    });

    test('flush 出去的列表不可变，调用方改不动内部累积', () {
      fakeAsync((async) {
        final c = ReaderPaginationCoordinator(flushEveryChunks: 1);
        final fake = _FakeSource([
          ['a'],
        ]);
        final flushes = <List<String>>[];

        final gen = c.beginRound();
        c.armBackgroundRound();
        c.drain(
          source: fake.source,
          generation: gen,
          initialPages: const [],
          mounted: () => true,
          onFlush: flushes.add,
          onComplete: (_) {},
        );
        async.elapse(const Duration(seconds: 1));

        // 之前踩过「回滚快照同引用」的坑，这里把不可变性钉死
        expect(() => flushes.single.add('x'), throwsUnsupportedError);
      });
    });

    test('空 chunk 立即终止循环，不死循环', () {
      fakeAsync((async) {
        final c = ReaderPaginationCoordinator(flushEveryChunks: 2);
        // isDone 永远 false，但 nextChunk 吐空 —— 模拟边界条件不一致
        var pulls = 0;
        final source = ReaderChunkSource(
          isDone: () => false,
          nextChunk: () {
            pulls++;
            return const <String>[];
          },
        );
        List<String>? completed;

        final gen = c.beginRound();
        c.armBackgroundRound();
        c.drain(
          source: source,
          generation: gen,
          initialPages: const ['p0'],
          mounted: () => true,
          onFlush: (_) {},
          onComplete: (pages) => completed = pages,
        );
        async.elapse(const Duration(seconds: 1));

        expect(pulls, 1);
        expect(completed, ['p0']);
      });
    });

    test('每个 chunk 之间让出事件循环，不阻塞 UI', () {
      fakeAsync((async) {
        final c = ReaderPaginationCoordinator(
          flushEveryChunks: 1,
          yieldDelay: const Duration(milliseconds: 10),
        );
        final fake = _FakeSource([
          ['a'],
          ['b'],
        ]);
        final flushes = <List<String>>[];

        final gen = c.beginRound();
        c.armBackgroundRound();
        c.drain(
          source: fake.source,
          generation: gen,
          initialPages: const [],
          mounted: () => true,
          onFlush: flushes.add,
          onComplete: (_) {},
        );

        // 还没到 10ms，一个 chunk 都不该算
        async.elapse(const Duration(milliseconds: 5));
        expect(flushes, isEmpty);

        async.elapse(const Duration(milliseconds: 10));
        expect(flushes.length, 1);

        async.elapse(const Duration(milliseconds: 10));
        expect(flushes.length, 2);
      });
    });
  });

  group('drain 过期退出（历史 bug 回归）', () {
    test('被新一轮顶替后立即停止，且不做收尾', () {
      fakeAsync((async) {
        final c = ReaderPaginationCoordinator(flushEveryChunks: 1);
        // 给足 chunk，确保这一轮在被顶替前不可能自然跑完 ——
        // 否则测的就不是「过期退出」而是「正常完成」了
        final fake = _FakeSource(
          List.generate(20, (i) => ['p$i']),
        );
        final flushes = <List<String>>[];
        var completedCalls = 0;

        final gen = c.beginRound();
        c.armBackgroundRound();
        c.drain(
          source: fake.source,
          generation: gen,
          initialPages: const [],
          mounted: () => true,
          onFlush: flushes.add,
          onComplete: (_) => completedCalls++,
        );

        // 默认 yieldDelay 1ms，走一格恰好出一个 chunk
        async.elapse(const Duration(milliseconds: 1));
        expect(flushes.length, 1);

        // LayoutBuilder 第二次触发，开新一轮
        c.beginRound();
        async.elapse(const Duration(seconds: 1));

        // 旧轮停在原地，没有继续刷
        expect(flushes.length, 1);
        // 关键回归：过期轮**绝不能**替新轮做收尾。
        // 旧实现里它会走到末尾去恢复阅读位置，把新轮的状态覆盖掉。
        expect(completedCalls, 0);
      });
    });

    test('mounted 变 false 后停止，不再拉取 chunk', () {
      fakeAsync((async) {
        final c = ReaderPaginationCoordinator(flushEveryChunks: 1);
        final fake = _FakeSource([
          ['a'],
          ['b'],
          ['c'],
        ]);
        var mounted = true;
        var completedCalls = 0;

        final gen = c.beginRound();
        c.armBackgroundRound();
        c.drain(
          source: fake.source,
          generation: gen,
          initialPages: const [],
          mounted: () => mounted,
          onFlush: (_) {},
          onComplete: (_) => completedCalls++,
        );

        async.elapse(const Duration(milliseconds: 2));
        final pullsBeforeDispose = fake.pulls;

        mounted = false;
        async.elapse(const Duration(seconds: 1));

        // dispose 之后一次都不该再拉 —— 否则就是 setState after dispose
        expect(fake.pulls, pullsBeforeDispose);
        expect(completedCalls, 0);
      });
    });

    test('显式 cancel 后停止且不收尾', () {
      fakeAsync((async) {
        final c = ReaderPaginationCoordinator(flushEveryChunks: 1);
        final fake = _FakeSource([
          ['a'],
          ['b'],
          ['c'],
        ]);
        var completedCalls = 0;

        final gen = c.beginRound();
        c.armBackgroundRound();
        c.drain(
          source: fake.source,
          generation: gen,
          initialPages: const [],
          mounted: () => true,
          onFlush: (_) {},
          onComplete: (_) => completedCalls++,
        );

        async.elapse(const Duration(milliseconds: 2));
        c.cancel();
        async.elapse(const Duration(seconds: 1));

        expect(completedCalls, 0);
      });
    });

    test('两轮连开：只有第二轮跑到收尾，恢复位置只做一次', () {
      fakeAsync((async) {
        // 这正是首帧 fitWidth==0 + 稳定帧的真实场景
        final c = ReaderPaginationCoordinator(flushEveryChunks: 1);
        final restores = <int>[];

        // 第一轮（首帧 fitWidth==0，页多、跑不完就被顶替）
        final gen1 = c.beginRound();
        c.armBackgroundRound();
        c.drain(
          source: _FakeSource(
            List.generate(20, (i) => ['stale$i']),
          ).source,
          generation: gen1,
          initialPages: const [],
          mounted: () => true,
          onFlush: (_) {},
          onComplete: (_) => restores.add(gen1),
        );

        async.elapse(const Duration(milliseconds: 1));

        // 第二轮（稳定帧）
        final gen2 = c.beginRound();
        c.armBackgroundRound();
        c.drain(
          source: _FakeSource([
            ['real1'],
            ['real2'],
          ]).source,
          generation: gen2,
          initialPages: const [],
          mounted: () => true,
          onFlush: (_) {},
          onComplete: (_) => restores.add(gen2),
        );

        async.elapse(const Duration(seconds: 1));

        // 恢复阅读位置必须恰好发生一次，且属于最新一轮。
        // 历史 bug 是「一次都不发生」（用户停在第 1 页）。
        expect(restores, [gen2]);
      });
    });
  });

  group('构造约束', () {
    test('flushEveryChunks 必须为正', () {
      expect(
        () => ReaderPaginationCoordinator(flushEveryChunks: 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('yieldDelay 不能为负', () {
      expect(
        () => ReaderPaginationCoordinator(
          yieldDelay: const Duration(milliseconds: -1),
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
