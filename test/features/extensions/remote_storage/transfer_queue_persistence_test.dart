// 传输队列的落盘与恢复 + 前台保活（284 P1）。
//
// 这组用例的重点不是"JSON 能不能写"（store 自己有测试），而是三件容易做错的语义：
//  1. 什么该落盘（未完成的落、完成的/取消的不落）、失败原因要跟着落；
//  2. 恢复出来的任务必须**真的能跑**（runner 由 factory 重建），且不重复入队；
//  3. 前台保活只在"有在跑的任务"期间起，收工必须撤掉。

import 'dart:async';

import 'package:box/features/extensions/plugins/remote_storage/application/transfer_queue.dart';
import 'package:box/features/extensions/plugins/remote_storage/data/transfer_keepalive.dart';
import 'package:box/features/extensions/plugins/remote_storage/data/transfer_queue_store.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStore extends TransferQueueStore {
  _FakeStore({List<Map<String, Object?>>? initial})
      : _records = List.of(initial ?? const []);

  List<Map<String, Object?>> _records;
  int saveCalls = 0;

  List<Map<String, Object?>> get records => List.unmodifiable(_records);

  @override
  Future<List<Map<String, Object?>>> load() async => List.of(_records);

  @override
  Future<void> save(List<Map<String, Object?>> records) async {
    saveCalls += 1;
    _records = List.of(records);
  }

  @override
  Future<void> clear() async {
    _records = const [];
  }
}

class _FakeKeepAlive extends TransferKeepAlive {
  final List<String> calls = <String>[];
  String? lastText;

  @override
  Future<void> start({required String title, required String text}) async {
    calls.add('start');
    lastText = text;
  }

  @override
  Future<void> update({required String text}) async {
    calls.add('update');
    lastText = text;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
  }
}

TransferRestoreSpec downloadSpec({
  String accountId = 'acct',
  String remotePath = '/a.mp4',
  String fileName = 'a.mp4',
}) =>
    TransferRestoreSpec(
      kind: TransferKind.download,
      accountId: accountId,
      remotePath: remotePath,
      fileName: fileName,
      title: fileName,
      subtitle: 'acct',
      totalBytes: 100,
    );

void main() {
  late _FakeStore store;
  late _FakeKeepAlive keepAlive;

  TransferQueue newQueue({int? maxConcurrent}) => TransferQueue(
        retryDelay: Duration.zero,
        maxConcurrent: maxConcurrent,
        store: store,
        keepAlive: keepAlive,
      );

  setUp(() {
    store = _FakeStore();
    keepAlive = _FakeKeepAlive();
  });

  group('落盘（284 P1）', () {
    test('入队就落盘：未完成的任务带着 spec 写下去', () async {
      final queue = newQueue();
      queue.enqueue(
        kind: TransferKind.download,
        title: 'a.mp4',
        subtitle: 'acct',
        spec: downloadSpec(),
        runner: (cancel, onProgress) async {
          onProgress(50, 100);
          return '/local/a.mp4';
        },
      );
      // 入队那一刻就写下去了（不然紧接着被杀就丢这一条）
      expect(store.records, hasLength(1));
      expect(store.records.single['kind'], 'download');

      // 跑完就不该再留着了（结果有效，重开不该再下一次）
      await Future<void>.delayed(Duration.zero);
      await queue.debugAwaitPersistence();
      expect(store.records, isEmpty, reason: '完成的条目不该留在盘里');
    });

    test('没 spec 的任务不落盘（临时/一次性传输）', () async {
      final queue = newQueue();
      final gate = Completer<void>();
      queue.enqueue(
        kind: TransferKind.download,
        title: '临时',
        subtitle: 'acct',
        runner: (cancel, onProgress) => gate.future,
      );
      await queue.debugAwaitPersistence();
      expect(store.records, isEmpty);
      gate.complete();
    });

    test('落盘内容够重建：账户/远端路径/文件名/覆盖选择都在', () async {
      final queue = newQueue();
      final gate = Completer<void>();
      queue.enqueue(
        kind: TransferKind.upload,
        title: 'f.bin',
        subtitle: 'acct',
        spec: const TransferRestoreSpec(
          kind: TransferKind.upload,
          accountId: 'acct',
          remotePath: '/dir',
          localPath: '/tmp/f.bin',
          fileName: 'f.bin',
          overwrite: true,
          title: 'f.bin',
          totalBytes: 42,
        ),
        runner: (cancel, onProgress) => gate.future,
      );
      await queue.debugAwaitPersistence();

      final record = store.records.single;
      expect(record['kind'], 'upload');
      expect(record['accountId'], 'acct');
      expect(record['remotePath'], '/dir');
      expect(record['localPath'], '/tmp/f.bin');
      expect(record['overwrite'], isTrue, reason: '覆盖选择必须原样恢复，不能替用户改主意');
      gate.complete();
    });

    test('失败任务落盘带 failed 与失败原因', () async {
      final queue = newQueue();
      final task = queue.enqueue(
        kind: TransferKind.download,
        title: 'a.mp4',
        subtitle: 'acct',
        spec: downloadSpec(),
        runner: (cancel, onProgress) async =>
            throw const RemoteStorageException(
              RemoteStorageError.unauthorized,
              '用户名或密码不正确',
            ),
      );
      await Future<void>.delayed(Duration.zero);
      await queue.debugAwaitPersistence();

      expect(task.status, TransferStatus.failed);
      final record = store.records.single;
      expect(record['failed'], isTrue);
      expect(record['errorMessage'], contains('用户名或密码不正确'));
    });
  });

  group('恢复（284 P1）', () {
    test('上次排队中的任务：重新排队并真的跑起来，标记 restored', () async {
      store = _FakeStore(initial: [downloadSpec().toJson()]);
      final queue = newQueue();
      var ran = 0;

      final restored = await queue.restorePending(
        factory: (spec) => (cancel, onProgress) async {
          ran += 1;
          onProgress(100, 100);
          return '/local/${spec.fileName}';
        },
      );

      expect(restored, 1);
      expect(ran, 1, reason: '恢复出来的任务必须真的能跑');
      await Future<void>.delayed(Duration.zero);
      final task = queue.tasks.single;
      expect(task.restored, isTrue, reason: 'UI 靠这个标「已恢复」');
      expect(task.status, TransferStatus.done);
      expect(task.title, 'a.mp4');
    });

    test('上次失败的任务：恢复成失败态且不自动重跑（等用户点重试）', () async {
      store = _FakeStore(initial: [
        {...downloadSpec().toJson(), 'failed': true, 'errorMessage': '连接超时'},
      ]);
      final queue = newQueue();
      var ran = 0;

      final restored = await queue.restorePending(
        factory: (spec) => (cancel, onProgress) async {
          ran += 1;
          return null;
        },
      );

      expect(restored, 1);
      expect(ran, 0, reason: '必然失败的任务不该每次启动都白跑一遍网络');
      final task = queue.tasks.single;
      expect(task.status, TransferStatus.failed);
      expect(task.errorMessage, '连接超时');

      // 用户点重试后才跑
      expect(queue.retry(task), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(ran, 1);
    });

    test('队列里已有同一件事：不重复入队', () async {
      store = _FakeStore(initial: [downloadSpec().toJson()]);
      final queue = newQueue();
      final gate = Completer<void>();
      queue.enqueue(
        kind: TransferKind.download,
        title: 'a.mp4',
        subtitle: 'acct',
        spec: downloadSpec(),
        runner: (cancel, onProgress) => gate.future,
      );

      final restored = await queue.restorePending(
        factory: (spec) => (cancel, onProgress) async => null,
      );

      expect(restored, 0);
      expect(queue.tasks, hasLength(1));
      gate.complete();
    });

    test('canRestore 说不能跑（账户删了/源文件没了）：丢弃并把它从盘里抹掉', () async {
      store = _FakeStore(initial: [
        downloadSpec(accountId: 'gone').toJson(),
        downloadSpec(remotePath: '/keep.mp4', fileName: 'keep.mp4').toJson(),
      ]);
      final queue = newQueue();

      final restored = await queue.restorePending(
        factory: (spec) => (cancel, onProgress) async => null,
        canRestore: (spec) async => spec.accountId != 'gone',
      );

      expect(restored, 1);
      expect(queue.tasks.single.spec!.remotePath, '/keep.mp4');
      expect(
        store.records.map((r) => r['accountId']),
        isNot(contains('gone')),
        reason: '过滤掉的记录不能永远躺在盘里',
      );
    });

    test('坏记录（缺字段/类型不对）跳过，正常记录照常恢复', () async {
      store = _FakeStore(initial: [
        {'kind': 'download'}, // 缺 accountId/remotePath
        {'kind': '不认识的类型', 'accountId': 'a', 'remotePath': '/x'},
        downloadSpec().toJson(),
      ]);
      final queue = newQueue();

      final restored = await queue.restorePending(
        factory: (spec) => (cancel, onProgress) async => null,
      );

      expect(restored, 1);
      expect(queue.tasks, hasLength(1));
    });

    test('盘里空 → 恢复 0 条且不惊动队列', () async {
      final queue = newQueue();
      expect(
        await queue.restorePending(
          factory: (spec) => (cancel, onProgress) async => null,
        ),
        0,
      );
      expect(queue.tasks, isEmpty);
    });
  });

  group('前台保活（284 P1）', () {
    test('有任务在跑 → 起前台服务；全部结束 → 撤掉', () async {
      final queue = newQueue();
      final gate = Completer<void>();
      queue.enqueue(
        kind: TransferKind.download,
        title: 'a.mp4',
        subtitle: 'acct',
        spec: downloadSpec(),
        runner: (cancel, onProgress) => gate.future,
      );
      await Future<void>.delayed(Duration.zero);
      expect(keepAlive.calls, contains('start'));

      gate.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(keepAlive.calls.last, 'stop', reason: '收工必须撤通知，不能留常驻通知');
    });

    test('空队列不打扰前台服务', () async {
      newQueue();
      await Future<void>.delayed(Duration.zero);
      expect(keepAlive.calls, isEmpty);
    });

    test('只起一次（并发多个任务不重复 start）', () async {
      final queue = newQueue(maxConcurrent: 2);
      final gate = Completer<void>();
      for (var i = 0; i < 2; i++) {
        queue.enqueue(
          kind: TransferKind.download,
          title: 'f$i.mp4',
          subtitle: 'acct',
          spec: downloadSpec(remotePath: '/f$i.mp4', fileName: 'f$i.mp4'),
          runner: (cancel, onProgress) => gate.future,
        );
      }
      await Future<void>.delayed(Duration.zero);
      expect(keepAlive.calls.where((c) => c == 'start'), hasLength(1));
      gate.complete();
    });
  });
}
