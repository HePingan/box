import 'package:box/video/widgets/player/player_pip_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PlayerPipChannel.channelName);
  final calls = <MethodCall>[];

  PlayerPipChannel newApi() => PlayerPipChannel(channel: channel);

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

  test('isSupported：原生说支持就支持', () async {
    mock((call) async => true);
    expect(await newApi().isSupported(), isTrue);
    expect(calls.single.method, 'isSupported');
  });

  test('enter：按约定的宽高比参数进小窗', () async {
    mock((call) async => true);
    final api = newApi();

    expect(await api.enter(), isTrue);
    expect(calls.single.method, 'enter');
    expect(calls.single.arguments, <String, Object?>{'width': 16, 'height': 9});
  });

  test('setAutoEnter：开关与宽高比都带上；老系统返回 false 不报错', () async {
    mock((call) async => false);
    final api = newApi();

    expect(await api.setAutoEnter(enabled: true), isFalse);
    expect(calls.single.method, 'setAutoEnter');
    expect(calls.single.arguments, <String, Object?>{
      'enabled': true,
      'width': 16,
      'height': 9,
    });
  });

  test('原生推 pipModeChanged：isInPip 跟着变（进出都认）', () async {
    final api = newApi();
    var notified = 0;
    api.isInPip.addListener(() => notified++);

    await api.handlePlatformCall(
      const MethodCall('pipModeChanged', true),
    );
    expect(api.isInPip.value, isTrue);

    await api.handlePlatformCall(
      const MethodCall('pipModeChanged', false),
    );
    expect(api.isInPip.value, isFalse);
    expect(notified, 2);
  });

  test('陌生方法不抛（通道将来加方法不该把播放器带崩）', () async {
    final api = newApi();
    await api.handlePlatformCall(const MethodCall('somethingElse', 1));
    expect(api.isInPip.value, isFalse);
  });

  test('没有原生实现（桌面/测试环境）：读回 false、进小窗 false，不抛', () async {
    unmock(); // 不装 handler
    final api = newApi();

    expect(await api.isSupported(), isFalse);
    expect(await api.enter(), isFalse);
    expect(await api.setAutoEnter(enabled: true), isFalse);
  });

  test('原生抛异常：同样静默降级', () async {
    mock((call) async => throw PlatformException(code: 'pip_failed'));
    final api = newApi();

    expect(await api.enter(), isFalse);
    expect(await api.setAutoEnter(enabled: true), isFalse);
  });

  test('原生返回 null：当成不支持', () async {
    mock((call) async => null);
    final api = newApi();

    expect(await api.isSupported(), isFalse);
    expect(await api.enter(), isFalse);
  });
}
