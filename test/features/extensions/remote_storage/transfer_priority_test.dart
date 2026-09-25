// 传输队列「优先」（287 P4）：排队规则与"不碰暂停态"。
//
// 同步点一律"等信号/等条件"，不数事件循环轮数。
import 'dart:async';

import 'package:box/features/extensions/plugins/remote_storage/application/transfer_queue.dart';
import 'package:box/features/extensions/plugins/remote_storage/data/transfer_queue_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStore extends TransferQueueStore {
  List<Map<String, Object?>> _records = const [];

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

  test('优先：排队的任务提到最前（下一个开跑），顺序真的变了', () async {
    // 只开一路并发：第一条占住位子，后面两条才会真的排队。
    final queue = TransferQueue(maxConcurrent: 1, store: _FakeStore());
    final gate = Completer<void>();
    final order = <String>[];

    queue.enqueue(
      kind: TransferKind.download,
      title: 'blocker.bin',
      subtitle: 's',
      runner: (cancel, onProgress) async {
        order.add('blocker.bin');
        await gate.future;
        return 'ok';
      },
    );
    await waitFor(() => order.length == 1, reason: 'blocker 应先进 running');

    TransferTask enqueueOne(String title) => queue.enqueue(
          kind: TransferKind.download,
          title: title,
          subtitle: 's',
          runner: (cancel, onProgress) async {
            order.add(title);
            return 'ok';
          },
        );

    final b = enqueueOne('b.bin');
    final c = enqueueOne('c.bin');
    expect(<String>[b.title, c.title], <String>['b.bin', 'c.bin']);

    expect(queue.prioritize(c), isTrue);
    // 顺序：新的在前 → 提到最前就是列表末尾。
    expect(queue.tasks.last.title, 'c.bin', reason: 'c 应排到最前');

    gate.complete();
    await waitFor(() => order.length == 3, reason: '三条都应跑完');
    expect(order, <String>['blocker.bin', 'c.bin', 'b.bin'],
        reason: 'c 插到 b 前面');
  });

  test('正在跑的任务不能插队（返回 false）', () async {
    final queue = TransferQueue(maxConcurrent: 1, store: _FakeStore());
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final running = queue.enqueue(
      kind: TransferKind.download,
      title: 'running.bin',
      subtitle: 's',
      runner: (cancel, onProgress) async {
        await gate.future;
        return 'ok';
      },
    );
    await waitFor(() => running.status == TransferStatus.running);
    expect(queue.prioritize(running), isFalse);
  });

  test('已暂停的任务不能借"优先"被拉起来（状态仍是 paused）', () async {
    final queue = TransferQueue(maxConcurrent: 1, store: _FakeStore());
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    queue.enqueue(
      kind: TransferKind.download,
      title: 'blocker.bin',
      subtitle: 's',
      runner: (cancel, onProgress) async {
        await gate.future;
        return 'ok';
      },
    );
    var ran = 0;
    final paused = queue.enqueue(
      kind: TransferKind.download,
      title: 'paused.bin',
      subtitle: 's',
      runner: (cancel, onProgress) async {
        ran += 1;
        return 'ok';
      },
    );
    queue.pause(paused);
    expect(paused.status, TransferStatus.paused);

    expect(queue.prioritize(paused), isFalse);
    expect(paused.status, TransferStatus.paused, reason: '暂停就是暂停');

    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(ran, 0, reason: '优先不该把它拉起来');
  });

  test('已完成的任务不能插队', () async {
    final queue = TransferQueue(maxConcurrent: 1, store: _FakeStore());
    final done = queue.enqueue(
      kind: TransferKind.download,
      title: 'done.bin',
      subtitle: 's',
      runner: (cancel, onProgress) async => 'ok',
    );
    await waitFor(() => done.status == TransferStatus.done);
    expect(queue.prioritize(done), isFalse);
  });
}
