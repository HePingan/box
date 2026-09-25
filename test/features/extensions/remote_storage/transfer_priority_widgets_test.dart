// 传输面板「优先」按钮（287 P4）：排队中才有，点了真的改变顺序。
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

  Future<void> pumpSheet(WidgetTester tester, TransferQueue queue) async {
    debugSetRemoteStorageRuntime(service: _FakeService(), queue: queue);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TransferQueueSheet())),
    );
    await tester.pump();
  }

  testWidgets('排队中的任务有「优先」，点了排到最前；在跑的没有这个按钮', (tester) async {
    final queue = TransferQueue(maxConcurrent: 1);
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });

    queue.enqueue(
      kind: TransferKind.download,
      title: 'running.bin',
      subtitle: '账户 · 下载',
      runner: (cancel, onProgress) async {
        await gate.future;
        return 'ok';
      },
    );
    queue.enqueue(
      kind: TransferKind.download,
      title: 'queued.bin',
      subtitle: '账户 · 下载',
      runner: (cancel, onProgress) async => 'ok',
    );
    await pumpSheet(tester, queue);

    // 只有排队那条有「优先」——在跑的那条没有（它已经在传了，插队没有意义）。
    expect(find.text('优先'), findsOneWidget);
    // 两条都是 isActive（queued 也算），所以暂停/取消各有两份 —— 这不是本用例的重点。
    expect(find.text('暂停'), findsWidgets);
    expect(find.text('queued.bin'), findsOneWidget);
  });

  testWidgets('点「优先」：提示 + 顺序前移（新入队的那条排到它后面）', (tester) async {
    final queue = TransferQueue(maxConcurrent: 1);
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    queue.enqueue(
      kind: TransferKind.download,
      title: 'running.bin',
      subtitle: '账户 · 下载',
      runner: (cancel, onProgress) async {
        await gate.future;
        return 'ok';
      },
    );
    final order = <String>[];
    queue.enqueue(
      kind: TransferKind.download,
      title: 'first.bin',
      subtitle: '账户 · 下载',
      runner: (cancel, onProgress) async {
        order.add('first.bin');
        return 'ok';
      },
    );
    await pumpSheet(tester, queue);

    // 又来一条：不插队的话它会排在 first 后面（先入先出）。
    queue.enqueue(
      kind: TransferKind.download,
      title: 'newer.bin',
      subtitle: '账户 · 下载',
      runner: (cancel, onProgress) async {
        order.add('newer.bin');
        return 'ok';
      },
    );
    await tester.pump();

    // 点 newer.bin 那一行的「优先」→ 它应当插到 first.bin 前面先跑。
    final row = find.ancestor(
      of: find.text('newer.bin'),
      matching: find.byType(Row),
    );
    await tester.tap(find.descendant(of: row.first, matching: find.text('优先')));
    await tester.pump();
    expect(find.textContaining('提到最前'), findsOneWidget);

    // 放行占位任务，看真实执行顺序（有界等待，不数轮数）。
    gate.complete();
    for (var i = 0; i < 40 && order.length < 2; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(order, <String>['newer.bin', 'first.bin'],
        reason: '点了优先的那条应当先跑');
  });
}
