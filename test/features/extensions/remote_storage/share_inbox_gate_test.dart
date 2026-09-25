// 分享接收闸门（286 P3）：冷启动取暂存、热启动听推送、没分享不打扰。
import 'package:box/features/extensions/plugins/remote_storage/application/remote_storage_service.dart';
import 'package:box/features/extensions/plugins/remote_storage/application/transfer_queue.dart';
import 'package:box/features/extensions/plugins/remote_storage/data/share_inbox_channel.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/remote_storage/presentation/share_inbox_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoAccountService extends RemoteStorageService {
  @override
  Future<List<RemoteStorageAccount>> loadAccounts() async =>
      const <RemoteStorageAccount>[];
}

Future<void> boundedPump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Map<Object?, Object?> _file(String name) => <Object?, Object?>{
      'path': '/data/cache/shared_inbox/1_$name',
      'name': name,
      'sizeBytes': 10,
      'mimeType': 'image/jpeg',
    };

void main() {
  const channel = MethodChannel(ShareInboxChannel.channelName);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    debugSetRemoteStorageRuntime(
      service: _NoAccountService(),
      queue: TransferQueue(),
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void mock(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  Future<void> pumpGate(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ShareInboxGate(child: const Scaffold(body: Text('主页'))),
      ),
    );
    await boundedPump(tester);
  }

  testWidgets('冷启动：先 ready 再 takePending，有文件就弹面板', (tester) async {
    final calls = <String>[];
    mock((call) async {
      calls.add(call.method);
      if (call.method == 'takePending') return <Object?>[_file('a.jpg')];
      return true;
    });

    await pumpGate(tester);

    expect(calls.first, 'ready', reason: '必须先告诉原生 handler 挂了');
    expect(calls, contains('takePending'));
    expect(find.text('收到 1 个分享文件'), findsOneWidget);
    expect(find.text('a.jpg'), findsWidgets);
  });

  testWidgets('冷启动：暂存为空 → 不弹任何面板', (tester) async {
    mock((call) async {
      if (call.method == 'takePending') return const <Object?>[];
      return true;
    });

    await pumpGate(tester);

    expect(find.textContaining('收到'), findsNothing);
    expect(find.text('主页'), findsOneWidget);
  });

  testWidgets('热启动：原生推过来就弹面板', (tester) async {
    mock((call) async => true);
    await pumpGate(tester);
    expect(find.textContaining('收到'), findsNothing);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      ShareInboxChannel.channelName,
      const StandardMethodCodec()
          .encodeMethodCall(MethodCall('onSharedFiles', <Object?>[_file('b.mp4')])),
      (_) {},
    );
    await boundedPump(tester);

    expect(find.text('收到 1 个分享文件'), findsOneWidget);
    expect(find.text('b.mp4'), findsWidgets);
  });

  testWidgets('推送里全是坏数据 → 不弹空面板', (tester) async {
    mock((call) async => true);
    await pumpGate(tester);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      ShareInboxChannel.channelName,
      const StandardMethodCodec()
          .encodeMethodCall(const MethodCall('onSharedFiles', <Object?>['bad'])),
      (_) {},
    );
    await boundedPump(tester);

    expect(find.textContaining('收到'), findsNothing);
  });
}
