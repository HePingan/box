// 传输暂停/继续（285 P2）：状态机、落盘与恢复。
//
// 同步点一律"等信号"（不用 pumpEventQueue 数轮数）—— 285 P4 的教训：
// IO 线程池上的活在机器忙时比固定轮数慢，靠轮数同步会偶发红。
import 'dart:async';

import 'package:box/features/extensions/plugins/remote_storage/application/transfer_queue.dart';
import 'package:box/features/extensions/plugins/remote_storage/data/transfer_queue_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStore extends TransferQueueStore {
  _FakeStore({List<Map<String, Object?>>? initial})
      : _records = List.of(initial ?? const []);

  List<Map<String, Object?>> _records;

  List<Map<String, Object?>> get records => List.unmodifiable(_records);

  @override
  Future<List<Map<String, Object?>>> load() async => List.of(_records);

  @override
  Future<void> save(List<Map<String, Object?>> records) async {
    _records = List.of(records);
  }

  @override
  Future<void> clear() async {
    _records = const [];
  }
}

/// 带 deadline 的轮询等待：不靠固定轮数猜。
Future<void> waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 8),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('等待超时${reason == null ? '' : '：$reason'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 一个"进了传送带就等信号"的任务：用来精确制造"正在传"的时刻。
  ({
    TransferTask task,
    Completer<void> started,
    List<int> invocations,
  }) enqueueSlow(
    TransferQueue queue, {
    String title = 'a.bin',
    TransferRestoreSpec? spec,
  }) {
    final started = Completer<void>();
    final invocations = <int>[];
    final task = queue.enqueue(
      kind: TransferKind.download,
      title: title,
      subtitle: 'account · /dir',
      spec: spec,
      runner: (cancel, onProgress) async {
        invocations.add(invocations.length + 1);
        onProgress(10, 100);
        if (!started.isCompleted) started.complete();
        // 停在这里直到被取消（暂停）或跑满上限。
        for (var i = 0; i < 400; i++) {
          cancel.throwIfCanceled();
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        return 'done';
      },
    );
    return (task: task, started: started, invocations: invocations);
  }

  test('暂停正在跑的任务：状态是 paused（不是 canceled），也不自动重跑', () async {
    final queue = TransferQueue(maxConcurrent: 1, store: _FakeStore());
    final ctx = enqueueSlow(queue);

    await ctx.started.future.timeout(const Duration(seconds: 5));
    expect(ctx.task.status, TransferStatus.running);

    expect(queue.pause(ctx.task), isTrue);
    await waitFor(() => ctx.task.status == TransferStatus.paused,
        reason: '取消应该被认成暂停');

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(ctx.task.status, TransferStatus.paused);
    expect(ctx.invocations.length, 1, reason: '暂停不该偷偷再拉起来');
    expect(queue.pausedCount, 1);
  });

  test('暂停排队中的任务：不会进入 running，继续后正常跑完', () async {
    final queue = TransferQueue(maxConcurrent: 1, store: _FakeStore());
    final ctx = enqueueSlow(queue, title: 'blocker');
    await ctx.started.future.timeout(const Duration(seconds: 5));

    var ran = 0;
    final queued = queue.enqueue(
      kind: TransferKind.download,
      title: 'b.bin',
      subtitle: 's',
      runner: (cancel, onProgress) async {
        ran += 1;
        return 'ok';
      },
    );
    expect(queued.status, TransferStatus.queued);

    queue.pause(queued);
    expect(queued.status, TransferStatus.paused);
    queue.pause(ctx.task); // 让出并发位
    await waitFor(() => ctx.task.status == TransferStatus.paused);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(ran, 0, reason: '暂停的任务不该在并发位空出来后自动开跑');

    queue.resume(queued);
    await waitFor(() => queued.status == TransferStatus.done,
        reason: '继续后应跑完');
    expect(ran, 1);
  });

  test('暂停过又继续：token 复位（否则一进去就被判成取消）', () async {
    final queue = TransferQueue(maxConcurrent: 1, store: _FakeStore());
    final ctx = enqueueSlow(queue);
    await ctx.started.future.timeout(const Duration(seconds: 5));

    queue.pause(ctx.task);
    await waitFor(() => ctx.task.status == TransferStatus.paused);
    // 等"暂停真的收尾"再继续：pause 立刻改状态，但在跑的那次传输要自己抛取消
    // 才结束；紧接着继续的话 token 会被复位、原来那次会继续跑（其实是好事，
    // 但这条用例要验的是"真停过再继续"）。
    await waitFor(() => queue.debugRunningCount == 0,
        reason: '在跑的那次应该已经收尾');
    queue.resume(ctx.task);
    await waitFor(() => ctx.task.status == TransferStatus.done,
        reason: '继续后应该真的跑起来（说明 token 复位了）');
    expect(ctx.invocations.length, 2, reason: '第二趟是继续后重跑的');
  });

  test('全部暂停 / 全部继续', () async {
    final queue = TransferQueue(maxConcurrent: 1, store: _FakeStore());
    final ctx = enqueueSlow(queue, title: 'a');
    await ctx.started.future.timeout(const Duration(seconds: 5));
    final b = queue.enqueue(
      kind: TransferKind.upload,
      title: 'b',
      subtitle: 's',
      runner: (cancel, onProgress) async => 'ok',
    );

    expect(queue.pauseAll(), 2, reason: '在跑的 + 排队中的都能暂停');
    expect(queue.pausedCount, 2);
    expect(queue.activeCount, 0);

    expect(queue.resumeAll(), 2);
    b.status = TransferStatus.done; // b 的 runner 会立刻完成
    await waitFor(() => queue.pausedCount == 0);
  });

  test('暂停态落盘，恢复回来仍是暂停（不会自动开跑）', () async {
    final store = _FakeStore();
    final queue = TransferQueue(maxConcurrent: 1, store: store);
    // 只有带 spec 的任务才落盘（真实现里由 service 提供）。
    final ctx = enqueueSlow(
      queue,
      title: 'p.bin',
      spec: const TransferRestoreSpec(
        kind: TransferKind.download,
        accountId: 'acc1',
        remotePath: '/dir/p.bin',
        fileName: 'p.bin',
        title: 'p.bin',
        subtitle: 'account · /dir',
      ),
    );
    await ctx.started.future.timeout(const Duration(seconds: 5));
    queue.pause(ctx.task);
    await waitFor(() => ctx.task.status == TransferStatus.paused);
    await queue.debugAwaitPersistence();
    expect(store.records.single['paused'], isTrue,
        reason: '暂停态要落盘成 paused，恢复时才不会自动开跑');
    expect(store.records.single['failed'], isFalse);
  });

  test('恢复：暂停的记录回来仍是 paused，并重建了 runner', () async {
    final store = _FakeStore(initial: [
      {
        'kind': 'download',
        'accountId': 'acc1',
        'remotePath': '/dir/p.bin',
        'fileName': 'p.bin',
        'title': 'p.bin',
        'subtitle': 'account · /dir',
        'totalBytes': 100,
        'overwrite': false,
        'paused': true,
      },
    ]);
    final queue = TransferQueue(maxConcurrent: 1, store: store);
    var factoryCalls = 0;
    final restored = await queue.restorePending(
      factory: (spec) {
        factoryCalls += 1;
        return (cancel, onProgress) async => 'ok';
      },
    );
    expect(restored, 1);
    expect(queue.tasks.single.status, TransferStatus.paused);
    expect(queue.tasks.single.restored, isTrue);
    expect(factoryCalls, 1, reason: '要重建 runner，用户点继续时才能跑');
    expect(queue.activeCount, 0, reason: '暂停的不算活跃，不许自动开跑');
  });

  test('清空已完成不动暂停的任务', () async {
    final queue = TransferQueue(maxConcurrent: 2, store: _FakeStore());
    final ctx = enqueueSlow(queue, title: 'paused.bin');
    await ctx.started.future.timeout(const Duration(seconds: 5));
    queue.pause(ctx.task);
    await waitFor(() => ctx.task.status == TransferStatus.paused);

    final done = queue.enqueue(
      kind: TransferKind.download,
      title: 'done.bin',
      subtitle: 's',
      runner: (cancel, onProgress) async {
        onProgress(1, 1);
        return 'ok';
      },
    );
    await waitFor(() => done.status == TransferStatus.done);

    queue.clearFinished();
    expect(queue.tasks.map((t) => t.title), ['paused.bin']);
  });

  test('暂停/继续对已结束的任务返回 false', () async {
    final queue = TransferQueue(maxConcurrent: 1, store: _FakeStore());
    final done = queue.enqueue(
      kind: TransferKind.download,
      title: 'x',
      subtitle: 's',
      runner: (cancel, onProgress) async => 'ok',
    );
    await waitFor(() => done.status == TransferStatus.done);
    expect(queue.pause(done), isFalse);
    expect(queue.resume(done), isFalse);
  });
}
