// 视频首帧通道（284 D8）：用假 MethodChannel 验证四条路径
// （拿到字节 / 空字节 / PlatformException / 通道不存在）+ 参数是否正确传下去。

import 'package:box/features/extensions/plugins/remote_storage/data/video_frame_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(VideoFrameChannel.channelName);
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

  test('拿到字节：原样返回，参数按约定传下去', () async {
    final bytes = Uint8List.fromList(<int>[1, 2, 3]);
    mock((call) async {
      calls.add(call);
      return bytes;
    });

    final got = await VideoFrameChannel().frameAt(
      url: 'https://dav.example.com/a.mp4',
      headers: const <String, String>{'authorization': 'Basic xxx'},
      maxWidth: 256,
    );

    expect(got, bytes);
    expect(calls.single.method, 'frameAt');
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(args['url'], 'https://dav.example.com/a.mp4');
    expect(args['headers'], <String, String>{'authorization': 'Basic xxx'});
    expect(args['positionMs'], 0);
    expect(args['maxWidth'], 256);
  });

  test('空字节/null 都当拿不到（不把空图塞进列表）', () async {
    mock((_) async => Uint8List(0));
    expect(await VideoFrameChannel().frameAt(url: 'https://x/a.mp4'), isNull);

    mock((_) async => null);
    expect(await VideoFrameChannel().frameAt(url: 'https://x/a.mp4'), isNull);
  });

  test('原生抛 PlatformException：吞掉返回 null（列表回退图标）', () async {
    mock((_) async => throw PlatformException(code: 'decode_failed'));

    expect(await VideoFrameChannel().frameAt(url: 'https://x/a.mp4'), isNull);
  });

  test('通道不存在（非 Android / 测试环境）：静默降级', () async {
    // 不注册任何 handler → MissingPluginException
    expect(await VideoFrameChannel().frameAt(url: 'https://x/a.mp4'), isNull);
  });

  test('空 url 直接返回 null，不打原生（避免原生侧报 IllegalArgumentException）', () async {
    mock((call) async {
      calls.add(call);
      return null;
    });

    expect(await VideoFrameChannel().frameAt(url: ''), isNull);
    expect(calls, isEmpty);
  });
}
