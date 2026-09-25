// 传输队列的网络闸门（287 P1）。
//
// 关心四件事：
//  1) 有情报且不允许 → 任务**留在队列里**（不 running、不挂保活、runner 不调用）；
//  2) 网络变成 Wi-Fi → 自动开跑，不需要用户再点一次；
//  3) "先询问"档 + 用户点"仍要传一次" → 开跑；**换了网络就清掉放行**；
//  4) 完全没有情报（通道不存在）→ **不拦**（否则 web/桌面会被静默停死）。
//
// 同步点一律"等信号/等条件"，不数事件循环轮数（285 P4 的教训）。
import 'dart:async';

import 'package:box/features/extensions/plugins/remote_storage/application/transfer_queue.dart';
import 'package:box/features/extensions/plugins/remote_storage/data/transfer_keepalive.dart';
import 'package:box/features/extensions/plugins/remote_storage/data/transfer_queue_store.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/network_policy.dart';
import 'package:flutter/services.dart';
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

/// 记录前台保活调用的替身通道：用来证明"被网络拦下的任务不会挂前台服务"。
class _KeepAliveRecorder {
  final List<String> calls = <String>[];

  TransferKeepAlive build() {
    const channel = MethodChannel(TransferKeepAlive.channelName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    return TransferKeepAlive(channel: channel);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 建一个"立刻跑完"的任务，返回任务本身与调用计数。
  ({TransferTask task, List<int> ran}) enqueueQuick(
    TransferQueue queue, {
    String title = 'a.bin',
  }) {
    final ran = <int>[];
    final task = queue.enqueue(
      kind: TransferKind.download,
      title: title,
      subtitle: 'account · /dir',
      runner: (cancel, onProgress) async {
        ran.add(1);
        return 'ok';
      },
    );
    return (task: task, ran: ran);
  }

  test('有情报且是移动网络 + 仅 Wi-Fi：任务留在队列里，runner 不跑，也不挂保活', () async {
    final keepAlive = _KeepAliveRecorder();
    final queue = TransferQueue(
      maxConcurrent: 1,
      store: _FakeStore(),
      keepAlive: keepAlive.build(),
    );
    queue.setNetworkState(NetworkKind.mobile);

    final ctx = enqueueQuick(queue);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(ctx.task.status, TransferStatus.queued);
    expect(ctx.ran, isEmpty, reason: '被拦下就不该调用 runner');
    expect(keepAlive.calls, isEmpty, reason: '没进 running 就不该起前台保活');
    expect(queue.networkBlocked, isTrue);
    expect(queue.waitingForNetworkCount, 1);

    // 放到 Wi-Fi 上：既开跑，也把前台保活挂上（证明闸门就是唯一的差别）。
    queue.setNetworkState(NetworkKind.wifi);
    await waitFor(() => ctx.task.status == TransferStatus.done);
    expect(keepAlive.calls, contains('start'));
  });

  test('网络切到 Wi-Fi：自动开跑，不用用户再点', () async {
    final queue = TransferQueue(maxConcurrent: 1, store: _FakeStore());
    queue.setNetworkState(NetworkKind.mobile);
    final ctx = enqueueQuick(queue);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(ctx.ran, isEmpty);

    queue.setNetworkState(NetworkKind.wifi);
    await waitFor(() => ctx.task.status == TransferStatus.done,
        reason: '换成 Wi-Fi 应自动接上');
    expect(ctx.ran.length, 1);
    expect(queue.waitingForNetworkCount, 0);
  });

  test('「不限网络」档：移动网络上直接开跑', () async {
    final queue = TransferQueue(maxConcurrent: 1, store: _FakeStore());
    queue.setNetworkState(NetworkKind.mobile);
    queue.setNetworkPolicy(TransferNetworkPolicy.allowAll);

    final ctx = enqueueQuick(queue);
    await waitFor(() => ctx.task.status == TransferStatus.done);
    expect(ctx.ran.length, 1);
  });

  test('「先询问」档：点"仍要传一次"后开跑；换了网络则重新拦', () async {
    final queue = TransferQueue(maxConcurrent: 1, store: _FakeStore());
    queue.setNetworkPolicy(TransferNetworkPolicy.askEachTime);
    queue.setNetworkState(NetworkKind.mobile);

    final first = enqueueQuick(queue, title: 'first.bin');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(first.ran, isEmpty, reason: '先询问档不该自动开跑');

    queue.allowMobileOnce();
    await waitFor(() => first.task.status == TransferStatus.done,
        reason: '用户确认后应开跑');
    expect(first.ran.length, 1);

    // 网络变过一次（Wi-Fi → 又回移动网络）：放行应该被清掉，重新拦。
    queue.setNetworkState(NetworkKind.wifi);
    queue.setNetworkState(NetworkKind.mobile);
    final second = enqueueQuick(queue, title: 'second.bin');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(second.ran, isEmpty, reason: '"这次"只对当时那次网络有效');
    expect(queue.networkBlocked, isTrue);
  });

  test('完全没情报（通道不存在/读不出来）：不拦，任务照跑', () async {
    final queue = TransferQueue(maxConcurrent: 1, store: _FakeStore());
    // 刻意不调 setNetworkState：模拟 read 不到网络类型。
    final ctx = enqueueQuick(queue);
    await waitFor(() => ctx.task.status == TransferStatus.done,
        reason: '没有情报时不能把传输停死');
    expect(ctx.ran.length, 1);
    expect(queue.networkBlocked, isFalse);
  });

  test('读到"未知网络"（VPN 等）：按移动网络保守拦下', () async {
    final queue = TransferQueue(maxConcurrent: 1, store: _FakeStore());
    queue.setNetworkState(NetworkKind.other);
    final ctx = enqueueQuick(queue);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(ctx.ran, isEmpty);
    expect(queue.waitingForNetworkCount, 1);
  });

  test('没网：连「不限网络」也不开跑，恢复网络后自动接上', () async {
    final queue = TransferQueue(maxConcurrent: 1, store: _FakeStore());
    queue.setNetworkPolicy(TransferNetworkPolicy.allowAll);
    queue.setNetworkState(NetworkKind.none);

    final ctx = enqueueQuick(queue);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(ctx.ran, isEmpty, reason: '没网时把任务标成在跑只会立刻失败');

    queue.setNetworkState(NetworkKind.wifi);
    await waitFor(() => ctx.task.status == TransferStatus.done);
  });

  test('先入队后被网络拦下：暂停态不参与网络判定（暂停就是暂停）', () async {
    final queue = TransferQueue(maxConcurrent: 1, store: _FakeStore());
    queue.setNetworkState(NetworkKind.mobile);
    final ctx = enqueueQuick(queue);

    queue.pause(ctx.task);
    expect(ctx.task.status, TransferStatus.paused);
    expect(queue.waitingForNetworkCount, 0, reason: '暂停的不是"等待网络"');

    queue.setNetworkState(NetworkKind.wifi);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(ctx.task.status, TransferStatus.paused,
        reason: '换 Wi-Fi 不该把用户暂停的任务拉起来');
  });
}
