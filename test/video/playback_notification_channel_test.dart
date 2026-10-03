import 'package:box/video/widgets/player/playback_notification_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PlaybackNotificationChannel.channelName);
  final calls = <MethodCall>[];

  PlaybackNotificationChannel newApi() =>
      PlaybackNotificationChannel(channel: channel);

  void mock(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  void unmock() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    calls.clear();
  }

  tearDown(unmock);

  test('start：标题/副标题/播放态按约定传给原生', () async {
    mock((call) async => true);
    final api = newApi();

    expect(
      await api.start(title: '某剧 第3集', text: '正在后台播放', playing: true),
      isTrue,
    );
    expect(calls.single.method, 'start');
    expect(calls.single.arguments, <String, Object?>{
      'title': '某剧 第3集',
      'text': '正在后台播放',
      'playing': true,
    });
    api.disposeForTest();
  });

  test('update / stop：方法名与参数', () async {
    mock((call) async => true);
    final api = newApi();

    await api.update(title: 't', text: 's', playing: false);
    expect(calls.last.method, 'update');
    expect(calls.last.arguments, <String, Object?>{
      'title': 't',
      'text': 's',
      'playing': false,
    });

    await api.stop();
    expect(calls.last.method, 'stop');
    api.disposeForTest();
  });

  test('通知按钮事件通过 onCommand 推过来，顺序不丢、重复也到', () async {
    final api = newApi();
    final received = <String>[];
    final sub = api.commands.listen(received.add);

    await api.handlePlatformCall(
      const MethodCall('onCommand', PlaybackNotificationChannel.commandToggle),
    );
    await api.handlePlatformCall(
      const MethodCall('onCommand', PlaybackNotificationChannel.commandNext),
    );
    await api.handlePlatformCall(
      const MethodCall('onCommand', PlaybackNotificationChannel.commandToggle),
    );
    await Future<void>.delayed(Duration.zero);

    expect(received, <String>['toggle', 'next', 'toggle']);
    await sub.cancel();
    api.disposeForTest();
  });

  test('音频焦点被抢也算一条命令（来电/别的 App 放音）', () async {
    final api = newApi();
    final received = <String>[];
    final sub = api.commands.listen(received.add);

    await api.handlePlatformCall(
      const MethodCall(
        'onCommand',
        PlaybackNotificationChannel.commandAudioFocusLost,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(received, <String>['audioFocusLost']);
    await sub.cancel();
    api.disposeForTest();
  });

  test('陌生方法 / 非字符串参数：忽略，不抛', () async {
    final api = newApi();
    final received = <String>[];
    final sub = api.commands.listen(received.add);

    await api.handlePlatformCall(const MethodCall('somethingElse', 1));
    await api.handlePlatformCall(const MethodCall('onCommand', 42));
    await Future<void>.delayed(Duration.zero);

    expect(received, isEmpty);
    await sub.cancel();
    api.disposeForTest();
  });

  test('没有原生实现（桌面/测试环境）：start/update/stop 都返回 false，不抛', () async {
    unmock();
    final api = newApi();

    expect(await api.start(title: 't', text: 's', playing: true), isFalse);
    expect(await api.update(title: 't', text: 's', playing: true), isFalse);
    expect(await api.stop(), isFalse);
    api.disposeForTest();
  });

  test('原生抛异常：静默降级', () async {
    mock((call) async => throw PlatformException(code: 'no_notification'));
    final api = newApi();

    expect(await api.start(title: 't', text: 's', playing: true), isFalse);
    api.disposeForTest();
  });
}
