// 分享接收通道（286 P3）：用假 MethodChannel 验证
// ready / takePending / onSharedFiles 三条路径 + 非 Android 的静默降级。
import 'package:box/features/extensions/plugins/remote_storage/data/share_inbox_channel.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/share_inbox_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(ShareInboxChannel.channelName);
  final calls = <MethodCall>[];

  void mock(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  setUp(() => calls.clear());
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('markReady 调 ready；重复调用不重复注册 handler', () async {
    mock((call) async {
      calls.add(call);
      return true;
    });
    final ch = ShareInboxChannel();
    await ch.markReady();
    await ch.markReady();
    expect(calls.map((c) => c.method), <String>['ready', 'ready']);
    await ch.dispose();
  });

  test('takePending 解析原生列表；坏条目跳过', () async {
    mock((call) async {
      calls.add(call);
      return <Object?>[
        <Object?, Object?>{
          'path': '/data/cache/shared_inbox/1_a.jpg',
          'name': 'a.jpg',
          'sizeBytes': 100,
          'mimeType': 'image/jpeg',
        },
        'bad',
      ];
    });
    final ch = ShareInboxChannel();
    final files = await ch.takePending();
    expect(files, hasLength(1));
    expect(files.single.name, 'a.jpg');
    expect(calls.single.method, 'takePending');
    await ch.dispose();
  });

  test('onSharedFiles：热启动推送过来进流', () async {
    mock((call) async => true);
    final ch = ShareInboxChannel();
    await ch.markReady();

    final received = <List<SharedInboxFile>>[];
    final sub = ch.onSharedFiles.listen(received.add);

    // 模拟原生侧主动推
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      ShareInboxChannel.channelName,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onSharedFiles', <Object?>[
          <Object?, Object?>{
            'path': '/data/cache/shared_inbox/2_b.mp4',
            'name': 'b.mp4',
            'sizeBytes': 9,
            'mimeType': 'video/mp4',
          },
        ]),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));
    expect(received.single.single.name, 'b.mp4');
    await sub.cancel();
    await ch.dispose();
  });

  test('onSharedFiles 收到空列表/坏数据：不推给界面', () async {
    mock((call) async => true);
    final ch = ShareInboxChannel();
    await ch.markReady();
    final received = <List<SharedInboxFile>>[];
    final sub = ch.onSharedFiles.listen(received.add);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      ShareInboxChannel.channelName,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onSharedFiles', <Object?>['bad']),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
    expect(received, isEmpty);
    await sub.cancel();
    await ch.dispose();
  });

  test('通道不存在（非 Android）：takePending 返回空、markReady 不抛', () async {
    // 不注册 mock handler → MissingPluginException
    final ch = ShareInboxChannel();
    await expectLater(ch.markReady(), completes);
    expect(await ch.takePending(), isEmpty);
    await ch.dispose();
  });
}
