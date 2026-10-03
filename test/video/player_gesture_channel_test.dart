import 'package:box/video/widgets/player/player_gesture_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PlayerGestureChannel.channelName);
  final calls = <MethodCall>[];
  final api = PlayerGestureChannel();

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

  test('setBrightness：参数按约定传 value，成功返回 true', () async {
    mock((call) async => true);

    expect(await api.setBrightness(0.35), isTrue);
    expect(calls.single.method, 'setBrightness');
    expect(calls.single.arguments, <String, Object?>{'value': 0.35});
  });

  test('setBrightness：传负数 = 交还系统（退出播放器时还原）', () async {
    mock((call) async => true);

    await api.setBrightness(-1);
    expect(calls.single.arguments, <String, Object?>{'value': -1.0});
  });

  test('getBrightness：-1（跟随系统）原样返回，规整交给 PlayerGestureMath', () async {
    mock((call) async => -1.0);
    expect(await api.getBrightness(), -1.0);

    unmock();
    mock((call) async => 0.42);
    expect(await api.getBrightness(), closeTo(0.42, 1e-9));
  });

  test('getVolume：取 map 里的 current；current 为 -1 视为拿不到', () async {
    mock((call) async => <String, Object?>{'current': 0.6, 'max': 15});
    expect(await api.getVolume(), closeTo(0.6, 1e-9));

    unmock();
    mock((call) async => <String, Object?>{'current': -1.0, 'max': 0});
    expect(await api.getVolume(), isNull);
  });

  test('setVolume：参数按约定传 value', () async {
    mock((call) async => true);

    expect(await api.setVolume(0.8), isTrue);
    expect(calls.single.method, 'setVolume');
    expect(calls.single.arguments, <String, Object?>{'value': 0.8});
  });

  test('没有原生实现（MissingPluginException）：读回 null、写入 false，不抛', () async {
    unmock(); // 不装 handler = 桌面/测试环境那种"没有这个通道"

    expect(await api.getBrightness(), isNull);
    expect(await api.getVolume(), isNull);
    expect(await api.setBrightness(0.5), isFalse);
    expect(await api.setVolume(0.5), isFalse);
  });

  test('原生抛 PlatformException（厂商 ROM 缺权限等）：同样静默降级', () async {
    mock((call) async => throw PlatformException(code: 'no_permission'));

    expect(await api.getBrightness(), isNull);
    expect(await api.setBrightness(0.5), isFalse);
  });

  test('原生返回 null：当成拿不到/没写成功', () async {
    mock((call) async => null);

    expect(await api.getBrightness(), isNull);
    expect(await api.setBrightness(0.5), isFalse);
  });
}
