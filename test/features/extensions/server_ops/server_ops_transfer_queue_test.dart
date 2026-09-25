// 服务器运维插件：串行传输队列的用例（A2/A3 的队列语义，纯 Dart 不依赖 widget）。
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_transfer_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('并发恒为 1：前一项 await 结束才发起下一项', () async {
    var active = 0;
    var maxActive = 0;
    final started = <int>[];
    final cancel = TransferCancelToken();

    final result = await runOpsSerialQueue(
      total: 5,
      cancel: cancel,
      task: (i) async {
        started.add(i);
        active += 1;
        if (active > maxActive) maxActive = active;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        active -= 1;
      },
    );

    expect(started, [0, 1, 2, 3, 4]);
    expect(maxActive, 1, reason: '并发必须恒为 1（手机上行带宽有限）');
    expect(result.succeeded, 5);
    expect(result.allSucceeded, isTrue);
  });

  test('取消后不再发起后续项', () async {
    final cancel = TransferCancelToken();
    final started = <int>[];

    final result = await runOpsSerialQueue(
      total: 4,
      cancel: cancel,
      task: (i) async {
        started.add(i);
        if (i == 1) cancel.cancel();
      },
    );

    expect(started, [0, 1], reason: '取消后第 3、4 项不能再发起');
    expect(result.canceled, isTrue);
    expect(result.failures, isEmpty, reason: '取消是用户意愿，不算失败');
  });

  test('在途项被取消抛出的取消异常算作取消，不算失败', () async {
    final cancel = TransferCancelToken();
    final result = await runOpsSerialQueue(
      total: 3,
      cancel: cancel,
      task: (i) async {
        cancel.cancel();
        throw const TransferCanceledException();
      },
    );

    expect(result.canceled, isTrue);
    expect(result.failedCount, 0);
  });

  test('中间某项失败不打断整批，失败项按下标记入 failures', () async {
    final cancel = TransferCancelToken();
    final started = <int>[];

    final result = await runOpsSerialQueue(
      total: 3,
      cancel: cancel,
      task: (i) async {
        started.add(i);
        if (i == 1) throw StateError('boom');
      },
    );

    expect(started, [0, 1, 2], reason: '第 2 项失败后仍要继续第 3 项');
    expect(result.succeeded, 2);
    expect(result.failedCount, 1);
    expect(result.failures.single.index, 1);
    expect(result.allSucceeded, isFalse);
  });

  test('onStart 每项各回调一次；summary 文案区分成功/失败/取消', () async {
    final starts = <int>[];
    final cancel = TransferCancelToken();

    final ok = await runOpsSerialQueue(
      total: 2,
      cancel: cancel,
      onStart: starts.add,
      task: (i) async {},
    );
    expect(starts, [0, 1]);
    expect(ok.summary('上传'), '上传完成：共 2 项');

    final partial = await runOpsSerialQueue(
      total: 2,
      cancel: TransferCancelToken(),
      task: (i) async {
        if (i == 0) throw StateError('boom');
      },
    );
    expect(partial.summary('上传'), '上传完成 1/2 项，失败 1 项');

    final canceled = await runOpsSerialQueue(
      total: 2,
      cancel: TransferCancelToken(),
      task: (i) async => throw const TransferCanceledException(),
    );
    expect(canceled.summary('上传'), '已取消上传：完成 0/2 项');
  });
}
