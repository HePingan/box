// TransferQueue 单测：并发度、重试、取消（排队中/运行中）、进度、清理。

import 'dart:async';

import 'package:box/features/extensions/plugins/remote_storage/application/transfer_queue.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TransferQueue newQueue({int? maxConcurrent}) =>
      TransferQueue(retryDelay: Duration.zero, maxConcurrent: maxConcurrent);

  test('并发执行：最多 maxConcurrent 个同时在跑，先入先出', () async {
    final queue = newQueue(maxConcurrent: 2);
    final gate = Completer<void>();
    final log = <String>[];
    var concurrent = 0;
    var maxConcurrent = 0;

    // 1、2 号都卡在同一个门上：真正占住两个名额（谁先返回谁先让位）
    Future<void> blocker(String tag) async {
      concurrent += 1;
      maxConcurrent = concurrent > maxConcurrent ? concurrent : maxConcurrent;
      log.add('start-$tag');
      await gate.future;
      log.add('end-$tag');
      concurrent -= 1;
    }

    final first = queue.enqueue(
      kind: TransferKind.download,
      title: 'a.bin',
      subtitle: 'acct',
      runner: (cancel, onProgress) => blocker('1'),
    );
    final second = queue.enqueue(
      kind: TransferKind.upload,
      title: 'b.bin',
      subtitle: 'acct',
      runner: (cancel, onProgress) => blocker('2'),
    );

    // 第三个：名额满了，必须等有人结束
    var thirdStarted = false;
    final third = queue.enqueue(
      kind: TransferKind.download,
      title: 'c.bin',
      subtitle: 'acct',
      runner: (cancel, onProgress) async {
        thirdStarted = true;
        log.add('start-3');
        return 'r3';
      },
    );

    await pumpEventQueue();
    expect(log, ['start-1', 'start-2']);
    expect(thirdStarted, isFalse, reason: '名额没空出来，第三个不能启动');
    expect(first.status, TransferStatus.running);
    expect(second.status, TransferStatus.running);
    expect(third.status, TransferStatus.queued);
    expect(maxConcurrent, 2);
    expect(queue.activeCount, 3); // 2 在跑 + 1 排队

    gate.complete();
    await pumpEventQueue();

    // 顺序：两个先起 → 1 号结束腾位 → 3 号才起（end-2 与 start-3 的先后取决于
    // 事件循环里谁先跑完收尾，都算对）
    expect(log, containsAllInOrder(['start-1', 'start-2', 'end-1', 'start-3']));
    expect(log, contains('end-2'));
    expect(maxConcurrent, 2, reason: '同时最多 2 个，不能因为空位就无限并发');
    expect(first.status, TransferStatus.done);
    expect(second.status, TransferStatus.done);
    expect(third.result, 'r3');
    expect(queue.activeCount, 0);
  });

  test('默认并发度来自 kMaxConcurrentTransfers（防止常量与队列脱钩）', () {
    expect(TransferQueue().maxConcurrent, kMaxConcurrentTransfers);
    expect(kMaxConcurrentTransfers, greaterThan(1),
        reason: 'C7：常量若被改回 1，批量传输会退回串行');
  });

  test('失败自动重试：2 次失败后成功（共 3 次尝试）', () async {
    final queue = newQueue();
    var attempts = 0;
    final task = queue.enqueue(
      kind: TransferKind.download,
      title: 'a.bin',
      subtitle: '',
      runner: (cancel, onProgress) async {
        attempts += 1;
        if (attempts <= kTransferRetries) {
          throw const RemoteStorageException(
            RemoteStorageError.http,
            '服务器返回 HTTP 500',
          );
        }
        return 'ok';
      },
    );
    await pumpEventQueue();

    expect(attempts, kTransferRetries + 1);
    expect(task.status, TransferStatus.done);
    expect(task.result, 'ok');
  });

  test('持续失败：状态 failed 且错误文案来自异常', () async {
    final queue = newQueue();
    final task = queue.enqueue(
      kind: TransferKind.download,
      title: 'a.bin',
      subtitle: '',
      runner: (cancel, onProgress) async {
        throw const RemoteStorageException(
          RemoteStorageError.http,
          '服务器返回 HTTP 500',
        );
      },
    );
    await pumpEventQueue();

    expect(task.status, TransferStatus.failed);
    expect(task.errorMessage, '服务器返回 HTTP 500');
    expect(task.isActive, isFalse);
  });

  test('非 RemoteStorageException 错误 → errorMessage 为字符串化异常', () async {
    final queue = newQueue();
    final task = queue.enqueue(
      kind: TransferKind.download,
      title: 'a.bin',
      subtitle: '',
      runner: (cancel, onProgress) async => throw Exception('boom'),
    );
    await pumpEventQueue();
    expect(task.status, TransferStatus.failed);
    expect(task.errorMessage, 'Exception: boom');
  });

  test('排队中取消：不执行 runner，状态 canceled，onFinished 被调用', () async {
    // "排队中"只有在名额被占满时才存在：并发度设 1 造出这个状态
    final queue = newQueue(maxConcurrent: 1);
    final gate = Completer<void>();
    var secondCalls = 0;
    TransferTask? finished;

    queue.enqueue(
      kind: TransferKind.download,
      title: 'a.bin',
      subtitle: '',
      runner: (cancel, onProgress) async {
        await gate.future;
        return null;
      },
    );
    final second = queue.enqueue(
      kind: TransferKind.download,
      title: 'b.bin',
      subtitle: '',
      runner: (cancel, onProgress) async {
        secondCalls += 1;
        return null;
      },
      onFinished: (task) => finished = task,
    );

    await pumpEventQueue();
    second.requestCancel();
    expect(second.status, TransferStatus.queued);

    gate.complete();
    await pumpEventQueue();

    expect(secondCalls, 0);
    expect(second.status, TransferStatus.canceled);
    expect(finished, same(second));
  });

  test('运行中取消：runner 内检查取消令牌后终止', () async {
    final queue = newQueue();
    final task = queue.enqueue(
      kind: TransferKind.download,
      title: 'a.bin',
      subtitle: '',
      runner: (cancel, onProgress) async {
        for (var i = 0; i < 3; i++) {
          await Future<void>.delayed(Duration.zero);
          cancel.throwIfCanceled();
        }
        return 'never';
      },
    );

    await Future<void>.delayed(Duration.zero);
    task.requestCancel();
    await pumpEventQueue();

    expect(task.status, TransferStatus.canceled);
    expect(task.result, isNull);
  });

  test('进度：received/total 更新，progress 归一且 clamp', () async {
    final queue = newQueue();
    final task = queue.enqueue(
      kind: TransferKind.download,
      title: 'a.bin',
      subtitle: '',
      runner: (cancel, onProgress) async {
        onProgress(5, 10);
        onProgress(30, -1);
        onProgress(10, 10);
        return null;
      },
    );
    await pumpEventQueue();

    expect(task.receivedBytes, 10);
    expect(task.totalBytes, 10);
    expect(task.progress, 1.0);

    // 未知总长 → progress 0，不崩。
    final unknown = queue.enqueue(
      kind: TransferKind.download,
      title: 'b.bin',
      subtitle: '',
      runner: (cancel, onProgress) async {
        onProgress(7, -1);
        return null;
      },
    );
    await pumpEventQueue();
    expect(unknown.receivedBytes, 7);
    expect(unknown.totalBytes, -1);
    expect(unknown.progress, 0.0);
  });

  test('tasks 新的在前；clearFinished 仅清非活动任务', () async {
    final queue = newQueue();
    final gate = Completer<void>();
    queue.enqueue(
      kind: TransferKind.download,
      title: 'a.bin',
      subtitle: '',
      runner: (cancel, onProgress) async => null,
    );
    queue.enqueue(
      kind: TransferKind.download,
      title: 'b.bin',
      subtitle: '',
      runner: (cancel, onProgress) async {
        await gate.future;
        return null;
      },
    );
    await pumpEventQueue();

    // 新的在前；此时 a 已完成、b 运行中。
    expect(queue.tasks.map((t) => t.title).toList(), ['b.bin', 'a.bin']);
    expect(queue.tasks[1].status, TransferStatus.done);

    queue.clearFinished();
    expect(queue.tasks.map((t) => t.title).toList(), ['b.bin']);

    gate.complete();
    await pumpEventQueue();
    queue.clearFinished();
    expect(queue.tasks, isEmpty);
  });

  group('重试分类（O2：重试是否会得到不同结果）', () {
    Future<({int attempts, TransferTask task})> runWith(
      TransferQueue queue,
      Object Function(int attempt) errorFor,
    ) async {
      var attempts = 0;
      final task = queue.enqueue(
        kind: TransferKind.download,
        title: 'a.bin',
        subtitle: '',
        runner: (cancel, onProgress) async {
          attempts += 1;
          throw errorFor(attempts);
        },
      );
      await pumpEventQueue();
      return (attempts: attempts, task: task);
    }

    test('401 凭证错：只尝试一次（不为密码错白等退避）', () async {
      final r = await runWith(newQueue(), (_) => remoteStorageExceptionForStatus(401));
      expect(r.attempts, 1);
      expect(r.task.status, TransferStatus.failed);
      expect(r.task.errorMessage, contains('应用密码'));
    });

    test('403 / 404 / 405 / 507 同样不重试', () async {
      for (final status in [403, 404, 405, 507]) {
        final r = await runWith(
          newQueue(),
          (_) => remoteStorageExceptionForStatus(status),
        );
        expect(r.attempts, 1, reason: 'HTTP $status 不应重试');
        expect(r.task.status, TransferStatus.failed);
      }
    });

    test('500 / 429 / 超时 仍重试到上限', () async {
      final cases = <Object>[
        remoteStorageExceptionForStatus(500),
        remoteStorageExceptionForStatus(429),
        const RemoteStorageException(RemoteStorageError.timeout, '连接超时'),
      ];
      for (final error in cases) {
        final r = await runWith(newQueue(), (_) => error);
        expect(r.attempts, kTransferRetries + 1, reason: '$error 应重试');
        expect(r.task.status, TransferStatus.failed);
      }
    });

    test('重试期间 retryAttempt 被通知（UI 可显示「重试中 n/2」）', () async {
      final queue = newQueue();
      var attempts = 0;
      final task = queue.enqueue(
        kind: TransferKind.download,
        title: 'a.bin',
        subtitle: '',
        runner: (cancel, onProgress) async {
          attempts += 1;
          if (attempts == 1) throw remoteStorageExceptionForStatus(503);
          return 'ok';
        },
      );
      final seenRetryAttempts = <int>[];
      queue.addListener(() => seenRetryAttempts.add(task.retryAttempt));

      await pumpEventQueue();

      expect(seenRetryAttempts, contains(1), reason: '重试等待期应通知一次');
      expect(task.status, TransferStatus.done);
      expect(task.retryAttempt, 0, reason: '结束后必须归零，避免 UI 停留在重试态');
    });
  });
  group('失败任务重试（283 D4）', () {
    test('失败后 retry → 重新跑起来并成功', () async {
      final queue = newQueue();
      var attempts = 0;
      final task = queue.enqueue(
        kind: TransferKind.download,
        title: 'a.bin',
        subtitle: 'acct',
        runner: (cancel, onProgress) async {
          attempts += 1;
          throw const RemoteStorageException(
            RemoteStorageError.http,
            '服务器返回 HTTP 500',
            statusCode: 500,
          );
        },
      );

      await pumpEventQueue();
      expect(task.status, TransferStatus.failed);
      expect(attempts, kTransferRetries + 1, reason: '自动重试已用尽');

      // 换一个能成功的 runner（模拟服务器恢复）后手动重试
      task.runner = (cancel, onProgress) async => '/tmp/a.bin';
      expect(queue.retry(task), isTrue);
      await pumpEventQueue();

      expect(task.status, TransferStatus.done);
      expect(task.result, '/tmp/a.bin');
      expect(task.errorMessage, isNull, reason: '重试前要清掉上次的错误');
      expect(task.receivedBytes, 0);
    });

    test('重试会复位进度与错误信息（不是接着失败态往上叠）', () async {
      final queue = newQueue();
      final gate = Completer<void>();
      final task = queue.enqueue(
        kind: TransferKind.upload,
        title: 'b.bin',
        subtitle: 'acct',
        totalBytes: 100,
        runner: (cancel, onProgress) async {
          onProgress(40, 100);
          throw const RemoteStorageException(RemoteStorageError.timeout, '连接超时');
        },
      );

      await pumpEventQueue();
      expect(task.status, TransferStatus.failed);

      // 先卡在门上再上报进度：这样"复位为 0"能被观察到一个确定的时刻
      // （runner 会同步跑到第一个 await，若先上报就看不到 0 了）。
      task.runner = (cancel, onProgress) async {
        await gate.future;
        onProgress(50, 100);
        return null;
      };
      expect(queue.retry(task), isTrue);

      expect(task.receivedBytes, 0, reason: '重试从 0 开始');
      expect(task.errorMessage, isNull);
      expect(task.status, TransferStatus.running);

      gate.complete();
      await pumpEventQueue();
      expect(task.status, TransferStatus.done);
    });

    test('只有"失败"能给重试：跑着的/成功的/已取消的都拒绝', () async {
      final queue = newQueue();
      final gate = Completer<void>();
      final running = queue.enqueue(
        kind: TransferKind.download,
        title: 'running.bin',
        subtitle: 'acct',
        runner: (cancel, onProgress) => gate.future,
      );
      final done = queue.enqueue(
        kind: TransferKind.download,
        title: 'done.bin',
        subtitle: 'acct',
        runner: (cancel, onProgress) async => '/tmp/done',
      );

      await pumpEventQueue();
      expect(running.status, TransferStatus.running);
      expect(done.status, TransferStatus.done);

      expect(queue.retry(running), isFalse, reason: '跑着的应该用取消');
      expect(queue.retry(done), isFalse, reason: '已完成的结果有效，别覆盖');
      expect(running.status, TransferStatus.running);

      gate.complete();
      await pumpEventQueue();
    });

    test('已取消的任务不给重试（用户主动放弃过）', () async {
      final queue = newQueue();
      final gate = Completer<void>();
      final task = queue.enqueue(
        kind: TransferKind.download,
        title: 'c.bin',
        subtitle: 'acct',
        runner: (cancel, onProgress) async {
          await gate.future;
          cancel.throwIfCanceled();
          return null;
        },
      );

      await pumpEventQueue();
      task.requestCancel();
      gate.complete();
      await pumpEventQueue();
      expect(task.status, TransferStatus.canceled);

      expect(queue.retry(task), isFalse);
    });

    test('取消过的 token 复位：重试不会被误判成取消', () async {
      final queue = newQueue();
      // 直接构造"失败但 token 已被取消过"的场景：失败回调里取消（用户点了取消
      // 但任务已失败）——不复位 token 的话重试会立刻抛取消异常。
      final task = queue.enqueue(
        kind: TransferKind.download,
        title: 'd.bin',
        subtitle: 'acct',
        runner: (cancel, onProgress) async {
          throw const RemoteStorageException(RemoteStorageError.http, '服务器返回 HTTP 500', statusCode: 500);
        },
      );

      await pumpEventQueue();
      expect(task.status, TransferStatus.failed);
      task.cancelToken.cancel(); // 用户放弃，但任务已是失败态

      var ranAgain = false;
      task.runner = (cancel, onProgress) async {
        cancel.throwIfCanceled();
        ranAgain = true;
        return '/tmp/d.bin';
      };
      expect(queue.retry(task), isTrue);
      await pumpEventQueue();

      expect(ranAgain, isTrue);
      expect(task.status, TransferStatus.done);
    });

    test('不属于本队列的任务 → 拒绝', () async {
      final queue = newQueue();
      final other = TransferQueue(retryDelay: Duration.zero);
      final task = other.enqueue(
        kind: TransferKind.download,
        title: 'x.bin',
        subtitle: 'acct',
        runner: (cancel, onProgress) async => null,
      );
      await pumpEventQueue();

      expect(queue.retry(task), isFalse);
    });

    test('重试后并发上限仍被遵守', () async {
      final queue = newQueue(maxConcurrent: 1);
      final gate = Completer<void>();
      final failing = queue.enqueue(
        kind: TransferKind.download,
        title: 'f.bin',
        subtitle: 'acct',
        runner: (cancel, onProgress) async => throw const RemoteStorageException(
          RemoteStorageError.http,
          '服务器返回 HTTP 500',
          statusCode: 500,
        ),
      );
      await pumpEventQueue();
      expect(failing.status, TransferStatus.failed);

      var secondStarted = false;
      queue.enqueue(
        kind: TransferKind.download,
        title: 'blocker.bin',
        subtitle: 'acct',
        runner: (cancel, onProgress) async {
          secondStarted = true;
          await gate.future;
          return null;
        },
      );
      await pumpEventQueue();
      expect(secondStarted, isTrue);

      failing.runner = (cancel, onProgress) async => '/tmp/f.bin';
      expect(queue.retry(failing), isTrue);
      await pumpEventQueue();
      expect(
        failing.status,
        TransferStatus.queued,
        reason: '名额被占着，重试的任务要排队而不是越过并发上限',
      );

      gate.complete();
      await pumpEventQueue();
      expect(failing.status, TransferStatus.done);
    });
  });
}
