// 传输面板：网络条件档位与「等待 Wi-Fi」横幅（287 P1）。
//
// 断言"按钮真的接到了队列/服务上"，不看配色：
//   * 菜单里三档都在，选了之后服务与偏好都被写入；
//   * 被网络拦下时横幅说清"几个任务在等、当前是什么网"；
//   * 「仍要传一次」真的放行（任务开始跑、横幅消失）；
//   * 「仅 Wi-Fi」档不给这条路（用户选的就是"不要在移动网络上传"）。
import 'dart:async';

import 'package:box/features/extensions/plugins/remote_storage/application/remote_storage_service.dart';
import 'package:box/features/extensions/plugins/remote_storage/application/transfer_queue.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/network_policy.dart';
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
    void Function(TransferQueue queue)? seed,
  }) async {
    debugSetRemoteStorageRuntime(service: service, queue: queue);
    seed?.call(queue);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TransferQueueSheet())),
    );
    await tester.pump();
    return queue;
  }

  /// 被网络拦下的任务：runner 用 Completer 卡住，别在 widget 测试里留定时器。
  ({List<int> ran, Completer<void> gate}) enqueueBlocked(
    TransferQueue queue, {
    String title = 'blocked.bin',
  }) {
    final ran = <int>[];
    final gate = Completer<void>();
    queue.enqueue(
      kind: TransferKind.download,
      title: title,
      subtitle: '账户 · 下载',
      runner: (cancel, onProgress) async {
        ran.add(1);
        await gate.future;
        return 'ok';
      },
    );
    return (ran: ran, gate: gate);
  }

  testWidgets('网络条件菜单：三档都在，选中后写入服务与偏好', (tester) async {
    final service = _FakeService();
    final queue = TransferQueue();
    await pumpSheet(tester, service: service, queue: queue);

    expect(service.transferNetworkPolicy, TransferNetworkPolicy.wifiOnly,
        reason: '默认仅 Wi-Fi');

    await tester.tap(find.byIcon(Icons.wifi_tethering_rounded));
    await tester.pumpAndSettle();

    expect(find.text('仅 Wi-Fi'), findsOneWidget);
    expect(find.text('移动网络先询问'), findsOneWidget);
    expect(find.text('不限网络'), findsOneWidget);

    await tester.tap(find.text('移动网络先询问'));
    await tester.pumpAndSettle();

    expect(service.transferNetworkPolicy, TransferNetworkPolicy.askEachTime);
    expect(queue.networkPolicy, TransferNetworkPolicy.askEachTime,
        reason: '队列这一侧也要跟着换档');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('remoteStorage.transferNetworkPolicy'), 'askEachTime',
        reason: '偏好要落盘，重启后仍生效');
  });

  testWidgets('偏好重新载入：新服务能读回上次选的档位，并灌进队列', (tester) async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{'remoteStorage.transferNetworkPolicy': 'allowAll'},
    );
    final service = _FakeService();
    final queue = TransferQueue();
    await pumpSheet(tester, service: service, queue: queue);

    await service.loadTransferNetworkPolicy();

    expect(service.transferNetworkPolicy, TransferNetworkPolicy.allowAll);
    expect(queue.networkPolicy, TransferNetworkPolicy.allowAll);
  });

  testWidgets('被拦下时横幅说清"几个任务在等、当前什么网"；「仍要传一次」真的放行', (tester) async {
    final service = _FakeService();
    final queue = TransferQueue(maxConcurrent: 1);
    // 顺序要紧：**先**把网络状态设成移动网络，再入队 —— 反过来的话任务在"还没有
    // 情报"时就已经开跑了，队列里就没有"等待网络"的项，横幅自然是空的。
    queue.setNetworkState(NetworkKind.mobile);
    queue.setNetworkPolicy(TransferNetworkPolicy.askEachTime);
    final ctx = enqueueBlocked(queue);
    addTearDown(() {
      if (!ctx.gate.isCompleted) ctx.gate.complete();
    });

    await pumpSheet(tester, service: service, queue: queue);
    await tester.pump();

    expect(find.textContaining('1 个任务'), findsOneWidget);
    expect(find.textContaining('当前：移动网络'), findsOneWidget);
    expect(ctx.ran, isEmpty, reason: '先询问档不该自动开跑');

    await tester.tap(find.text('仍要传一次'));
    await tester.pump();

    expect(ctx.ran.length, 1, reason: '点了放行就该真的开始跑');
    expect(queue.networkBlocked, isFalse);
    await tester.pump();
    expect(find.textContaining('个任务'), findsNothing, reason: '放行后横幅该消失');
  });

  testWidgets('「仅 Wi-Fi」档：横幅提示等待 Wi-Fi，且不给「仍要传一次」', (tester) async {
    final service = _FakeService();
    final queue = TransferQueue(maxConcurrent: 1);
    queue.setNetworkState(NetworkKind.mobile); // 先设网络再入队（同上）
    final ctx = enqueueBlocked(queue);
    addTearDown(() {
      if (!ctx.gate.isCompleted) ctx.gate.complete();
    });

    await pumpSheet(tester, service: service, queue: queue);
    await tester.pump();

    expect(find.textContaining('等待 Wi-Fi'), findsOneWidget);
    expect(find.text('仍要传一次'), findsNothing,
        reason: '用户选的就是"不在移动网络上传"，不该给这条路');
  });

  testWidgets('无网络时横幅说"等待网络"，切回 Wi-Fi 后自动开跑（无需点任何按钮）', (tester) async {
    final service = _FakeService();
    final queue = TransferQueue(maxConcurrent: 1);
    queue.setNetworkState(NetworkKind.none); // 先设网络再入队（同上）
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final ran = <int>[];
    queue.enqueue(
      kind: TransferKind.download,
      title: 'offline.bin',
      subtitle: '账户 · 下载',
      runner: (cancel, onProgress) async {
        ran.add(1);
        await gate.future;
        return 'ok';
      },
    );

    await pumpSheet(tester, service: service, queue: queue);
    await tester.pump();
    expect(find.textContaining('等待网络'), findsOneWidget);

    // 网络恢复（模拟原生推送）→ 应当自动接上，不用点任何东西。
    queue.setNetworkState(NetworkKind.wifi);
    await tester.pump();
    expect(ran.length, 1, reason: '恢复 Wi-Fi 后应自动开始');
    await tester.pump();
    expect(find.textContaining('个任务'), findsNothing);
  });
}
