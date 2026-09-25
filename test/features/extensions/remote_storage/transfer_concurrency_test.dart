// 传输并发档位（287 D2）：队列侧的状态机 + 面板档位菜单。
//
// 规矩：调**大**立刻多起几路；调**小**不打断已在跑的（半路掐掉只会白费已传的字节）。
import 'dart:async';

import 'package:box/features/extensions/plugins/remote_storage/application/remote_storage_service.dart';
import 'package:box/features/extensions/plugins/remote_storage/application/transfer_queue.dart';
import 'package:box/features/extensions/plugins/remote_storage/data/transfer_queue_store.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/remote_storage/presentation/remote_storage_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class _FakeService extends RemoteStorageService {}

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
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('队列', () {
    test('调大并发：立刻多起几路（不用等前面跑完）', () async {
      final queue = TransferQueue(maxConcurrent: 1, store: _FakeStore());
      final gates = <Completer<void>>[];
      void enqueueOne(String title) {
        final gate = Completer<void>();
        gates.add(gate);
        queue.enqueue(
          kind: TransferKind.download,
          title: title,
          subtitle: 's',
          runner: (cancel, onProgress) async {
            await gate.future;
            return 'ok';
          },
        );
      }

      enqueueOne('a');
      enqueueOne('b');
      enqueueOne('c');
      await waitFor(() => queue.activeCount == 3, reason: '三条都应在队列里');
      await waitFor(
        () => queue.tasks.where((t) => t.status == TransferStatus.running).length == 1,
        reason: '并发 1 时只有一条在跑',
      );

      queue.setMaxConcurrent(3);
      await waitFor(
        () => queue.tasks.where((t) => t.status == TransferStatus.running).length == 3,
        reason: '调大后应立刻多起两路',
      );
      for (final gate in gates) {
        if (!gate.isCompleted) gate.complete();
      }
      await waitFor(() => queue.tasks.every((t) => t.status == TransferStatus.done));
    });

    test('调小并发：不打断正在跑的任务，等它们自己结束', () async {
      final queue = TransferQueue(maxConcurrent: 3, store: _FakeStore());
      final gates = <Completer<void>>[];
      for (var i = 0; i < 2; i++) {
        final gate = Completer<void>();
        gates.add(gate);
        queue.enqueue(
          kind: TransferKind.download,
          title: 't$i',
          subtitle: 's',
          runner: (cancel, onProgress) async {
            await gate.future;
            return 'ok';
          },
        );
      }
      await waitFor(
        () => queue.tasks.where((t) => t.status == TransferStatus.running).length == 2,
      );

      queue.setMaxConcurrent(1);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(
        queue.tasks.where((t) => t.status == TransferStatus.running).length,
        2,
        reason: '在跑的不该被掐掉（半路停只会白费已传的字节）',
      );

      for (final gate in gates) {
        if (!gate.isCompleted) gate.complete();
      }
      await waitFor(() => queue.tasks.every((t) => t.status == TransferStatus.done));
    });

    test('档位夹到合法范围（落盘脏值也不怕）', () {
      final queue = TransferQueue(maxConcurrent: 3, store: _FakeStore());
      queue.setMaxConcurrent(0);
      expect(queue.maxConcurrent, 1);
      queue.setMaxConcurrent(99);
      expect(queue.maxConcurrent, 6);
      expect(clampTransferConcurrency(-5), 1);
      expect(clampTransferConcurrency(100), 6);
      expect(clampTransferConcurrency(4), 4);
    });
  });

  group('面板与服务', () {
    // 注意：**必须把同一个 service 实例注册进运行时**，否则断言的那个 service
    // 和面板实际用的不是同一个对象（这个坑在自己写替身时很容易踩）。
    Future<void> pumpSheet(
      WidgetTester tester,
      TransferQueue queue, {
      RemoteStorageService? service,
    }) async {
      debugSetRemoteStorageRuntime(
        service: service ?? _FakeService(),
        queue: queue,
      );
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: TransferQueueSheet())),
      );
      await tester.pump();
    }

    testWidgets('档位菜单：六个档都在，选中后写进服务、偏好与队列', (tester) async {
      final service = _FakeService();
      final queue = TransferQueue();
      await pumpSheet(tester, queue, service: service);
      expect(queue.maxConcurrent, kMaxConcurrentTransfers, reason: '默认 3');

      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
      for (final option in kTransferConcurrencyOptions) {
        expect(find.text('同时传 $option 个'), findsOneWidget);
      }

      // 刻意点**最后一个**档位：项目多的时候，靠后的会落在弹层可点区域之外
      // （tap 的坐标 hit test 不到）—— 这个用例就是用来防这种回归的。
      await tester.tap(find.text('同时传 6 个'), warnIfMissed: true);
      await tester.pumpAndSettle();

      expect(service.transferConcurrency, 6);
      expect(queue.maxConcurrent, 6, reason: '队列这一侧也要跟着换');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('remoteStorage.transferConcurrency'), 6);
    });

    testWidgets('偏好重新载入：新服务读回档位并灌进队列', (tester) async {
      SharedPreferences.setMockInitialValues(
        <String, Object>{'remoteStorage.transferConcurrency': 6},
      );
      final service = _FakeService();
      final queue = TransferQueue();
      await pumpSheet(tester, queue, service: service);

      await service.loadTransferConcurrency();

      expect(service.transferConcurrency, 6);
      expect(queue.maxConcurrent, 6);
    });

    testWidgets('落盘脏值（0 / 999）载入时被夹到合法档位', (tester) async {
      SharedPreferences.setMockInitialValues(
        <String, Object>{'remoteStorage.transferConcurrency': 999},
      );
      final service = _FakeService();
      final queue = TransferQueue();
      await pumpSheet(tester, queue, service: service);
      await service.loadTransferConcurrency();
      expect(service.transferConcurrency, 6);
      expect(queue.maxConcurrent, 6);
    });
  });
}
