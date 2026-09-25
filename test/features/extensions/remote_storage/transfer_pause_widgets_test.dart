// 传输面板：暂停/继续/限速（285 P2）的界面行为。
//
// 断言的重点是"按钮真的接到了队列/服务上"，不是配色：
//   * 活动任务有「暂停」，点完状态变 paused 且原位出现「继续」；
//   * 暂停的条目仍显示进度（用户要知道传到哪了）+ 「已暂停」；
//   * 限速档位：选了之后服务与偏好都被写入。
import 'dart:async';

import 'package:box/features/extensions/plugins/remote_storage/application/remote_storage_service.dart';
import 'package:box/features/extensions/plugins/remote_storage/application/transfer_queue.dart';
import 'package:box/features/extensions/plugins/remote_storage/presentation/remote_storage_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeService extends RemoteStorageService {}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<TransferQueue> pumpSheet(
    WidgetTester tester, {
    required RemoteStorageService service,
    required TransferQueue queue,
    required void Function(TransferQueue queue) seed,
  }) async {
    debugSetRemoteStorageRuntime(service: service, queue: queue);
    seed(queue);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TransferQueueSheet())),
    );
    await tester.pump();
    return queue;
  }

  testWidgets('活动任务有「暂停」：点了变 paused，原位出现「继续」', (tester) async {
    // 只开一路并发：第二条才会真的排在后面（否则它自己就开跑了、立刻完成）。
    final queue = TransferQueue(maxConcurrent: 1);
    // 一个占住并发位的任务（用 Completer 而不是 delay：widget 测试里
    // 别留定时器，否则结尾会报 "Timer is still pending"）。
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    await pumpSheet(
      tester,
      service: _FakeService(),
      queue: queue,
      seed: (q) {
        q.enqueue(
          kind: TransferKind.download,
          title: 'blocker.bin',
          subtitle: '账户 · 下载',
          runner: (cancel, onProgress) async {
            await gate.future;
            return 'ok';
          },
        );
        q.enqueue(
          kind: TransferKind.download,
          title: 'queued.bin',
          subtitle: '账户 · 下载',
          runner: (cancel, onProgress) async => 'ok',
        );
      },
    );

    expect(find.text('暂停'), findsNWidgets(2), reason: '在跑的 + 排队中的都能暂停');
    // 点第二条（排队中的那条，确定性更好）
    await tester.tap(find.text('暂停').last);
    await tester.pump();

    expect(queue.tasks.last.status, TransferStatus.paused);
    expect(find.text('继续'), findsOneWidget);
    expect(find.textContaining('已暂停'), findsWidgets);

    // 继续 → 回到队列 → 跑完
    await tester.tap(find.text('继续'));
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(queue.tasks.last.status, TransferStatus.done);
  });

  testWidgets('暂停的条目仍显示进度（用户要知道传到哪了）', (tester) async {
    final queue = TransferQueue();
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    await pumpSheet(
      tester,
      service: _FakeService(),
      queue: queue,
      seed: (q) {
        q.enqueue(
          kind: TransferKind.download,
          title: 'big.bin',
          subtitle: '账户 · 下载',
          runner: (cancel, onProgress) async {
            onProgress(30, 100);
            await gate.future;
            return 'ok';
          },
        );
      },
    );
    // 等进度上报
    await tester.pump();

    await tester.tap(find.text('暂停'));
    await tester.pump();

    expect(queue.tasks.single.status, TransferStatus.paused);
    expect(find.byType(LinearProgressIndicator), findsOneWidget,
        reason: '暂停也要看得见进度条');
    expect(find.textContaining('已暂停'), findsWidgets);
  });

  testWidgets('「全部暂停」出现在有活动任务时，点了提示条数', (tester) async {
    final queue = TransferQueue();
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    await pumpSheet(
      tester,
      service: _FakeService(),
      queue: queue,
      seed: (q) {
        q.enqueue(
          kind: TransferKind.download,
          title: 'a.bin',
          subtitle: 's',
          runner: (cancel, onProgress) async {
            await gate.future;
            return 'ok';
          },
        );
      },
    );

    expect(find.text('全部暂停'), findsOneWidget);
    await tester.tap(find.text('全部暂停'));
    await tester.pump();

    expect(find.textContaining('已暂停 1 个传输任务'), findsOneWidget);
    expect(find.text('全部继续'), findsOneWidget);
  });

  testWidgets('限速：菜单选中档位后写入服务与偏好', (tester) async {
    final service = _FakeService();
    final queue = TransferQueue();
    await pumpSheet(
      tester,
      service: service,
      queue: queue,
      seed: (q) {},
    );

    expect(service.transferRateLimitBytesPerSecond, 0, reason: '默认不限速');

    await tester.tap(find.byIcon(Icons.speed_rounded));
    await tester.pumpAndSettle();
    expect(find.text('不限速'), findsOneWidget);

    await tester.tap(find.text('限速 512 KB/s'));
    await tester.pumpAndSettle();

    expect(service.transferRateLimitBytesPerSecond, 524288);
    expect(find.textContaining('限速 512 KB/s'), findsWidgets);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('remoteStorage.transferRateLimit'), 524288,
        reason: '偏好要落盘，重启后仍生效');
  });

  testWidgets('限速：重新载入偏好（新服务）能读到上次选的档位', (tester) async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{'remoteStorage.transferRateLimit': 1048576},
    );
    final service = _FakeService();
    await service.loadTransferRateLimit();
    expect(service.transferRateLimitBytesPerSecond, 1048576);
  });
}
