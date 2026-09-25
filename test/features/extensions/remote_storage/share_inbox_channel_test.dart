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
    final batch = await ch.takePending();
    expect(batch.files, hasLength(1));
    expect(batch.files.single.name, 'a.jpg');
    expect(batch.total, 1, reason: '老形状（裸列表）时 total == received');
    expect(batch.skipped, isEmpty);
    expect(calls.single.method, 'takePending');
    await ch.dispose();
  });

  test('onSharedFiles：热启动推送过来进流', () async {
    mock((call) async => true);
    final ch = ShareInboxChannel();
    await ch.markReady();

    final received = <ShareInboxBatch>[];
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
    expect(received.single.files.single.name, 'b.mp4');
    expect(received.single.total, 1);
    await sub.cancel();
    await ch.dispose();
  });

  test('新形状：files + total + skipped 一起解析，跳过记录进得来（287 P2）', () async {
    mock((call) async => true);
    final ch = ShareInboxChannel();
    await ch.markReady();
    final received = <ShareInboxBatch>[];
    final sub = ch.onSharedFiles.listen(received.add);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      ShareInboxChannel.channelName,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onSharedFiles', <Object?, Object?>{
          'files': <Object?>[
            <Object?, Object?>{
              'path': '/data/cache/shared_inbox/1_a.jpg',
              'name': 'a.jpg',
              'sizeBytes': 10,
              'mimeType': 'image/jpeg',
            },
          ],
          'total': 3,
          'received': 1,
          'skipped': <Object?>[
            <Object?, Object?>{'name': 'big.mov', 'reason': 'tooLarge'},
            <Object?, Object?>{'name': 'c.png', 'reason': 'tooMany'},
          ],
        }),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));
    final batch = received.single;
    expect(batch.files.single.name, 'a.jpg');
    expect(batch.total, 3);
    expect(batch.skipped.map((s) => s.reason), <String>['tooLarge', 'tooMany']);
    expect(batch.hasLosses, isTrue);
    await sub.cancel();
    await ch.dispose();
  });

  test('一个文件都没收到、但有跳过记录：也要推给界面（287 P2）', () async {
    mock((call) async => true);
    final ch = ShareInboxChannel();
    await ch.markReady();
    final received = <ShareInboxBatch>[];
    final sub = ch.onSharedFiles.listen(received.add);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      ShareInboxChannel.channelName,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onSharedFiles', <Object?, Object?>{
          'files': <Object?>[],
          'total': 1,
          'received': 0,
          'skipped': <Object?>[
            <Object?, Object?>{'name': 'huge.mov', 'reason': 'tooLarge'},
          ],
        }),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1),
        reason: '全被跳过也不能静默：否则用户以为分享成功了');
    expect(received.single.files, isEmpty);
    expect(received.single.hasLosses, isTrue);
    await sub.cancel();
    await ch.dispose();
  });

  test('onSharedFiles 收到空列表/坏数据：不推给界面', () async {
    mock((call) async => true);
    final ch = ShareInboxChannel();
    await ch.markReady();
    final received = <ShareInboxBatch>[];
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
