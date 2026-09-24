// TransferQueue 单测：串行、重试、取消（排队中/运行中）、进度、清理。

import 'dart:async';

import 'package:box/features/extensions/plugins/remote_storage/application/transfer_queue.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TransferQueue newQueue() =>
      TransferQueue(retryDelay: Duration.zero);

  test('串行执行：前一个完成前不启动下一个，顺序与并发数正确', () async {
    final queue = newQueue();
    final gate = Completer<void>();
    final log = <String>[];
    var concurrent = 0;
    var maxConcurrent = 0;

    final first = queue.enqueue(
      kind: TransferKind.download,
      title: 'a.bin',
      subtitle: 'acct',
      runner: (cancel, onProgress) async {
        concurrent += 1;
        maxConcurrent = concurrent > maxConcurrent ? concurrent : maxConcurrent;
        log.add('start-1');
        await gate.future;
        log.add('end-1');
        concurrent -= 1;
        return 'r1';
      },
    );
    final second = queue.enqueue(
      kind: TransferKind.upload,
      title: 'b.bin',
      subtitle: 'acct',
      runner: (cancel, onProgress) async {
        concurrent += 1;
        maxConcurrent = concurrent > maxConcurrent ? concurrent : maxConcurrent;
        log.add('start-2');
        concurrent -= 1;
        return 'r2';
      },
    );

    await pumpEventQueue();
    expect(log, ['start-1']);
    expect(first.status, TransferStatus.running);
    expect(second.status, TransferStatus.queued);
    expect(queue.activeCount, 2);

    gate.complete();
    await pumpEventQueue();

    expect(log, ['start-1', 'end-1', 'start-2']);
    expect(maxConcurrent, 1);
    expect(first.status, TransferStatus.done);
    expect(second.status, TransferStatus.done);
    expect(first.result, 'r1');
    expect(second.result, 'r2');
    expect(queue.activeCount, 0);
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
    final queue = newQueue();
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
}
