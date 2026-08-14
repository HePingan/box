import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/novel/pages/reader/reader_volume_key_controller.dart';

/// 记录发往原生的 setVolumeKeyNavEnabled 调用序列，
/// 并允许测试反向注入 onVolumeKey 回调。
class _FakeKeyChannel {
  _FakeKeyChannel({this.throwOnSend = false});

  static const String name = 'com.example.box/reader_keys';

  final bool throwOnSend;
  final List<bool> sent = <bool>[];
  Future<dynamic> Function(MethodCall)? _handler;

  MethodChannel build() {
    final channel = MethodChannel(name);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setVolumeKeyNavEnabled') {
        if (throwOnSend) {
          throw PlatformException(code: 'BOOM', message: 'channel down');
        }
        sent.add((call.arguments as Map)['enabled'] as bool);
        return true;
      }
      return null;
    });
    // 拦截 Dart 侧 setMethodCallHandler，以便测试直接触发原生回调
    return _RecordingChannel(name, this);
  }

  set handler(Future<dynamic> Function(MethodCall)? h) => _handler = h;

  /// 模拟原生按下音量键。
  Future<void> pressKey(String direction) async {
    final h = _handler;
    if (h == null) return;
    await h(MethodCall('onVolumeKey', {'direction': direction}));
  }
}

/// 转发真实调用到 mock，同时捕获 Dart 侧注册的 handler。
class _RecordingChannel extends MethodChannel {
  _RecordingChannel(super.name, this._fake);

  final _FakeKeyChannel _fake;

  @override
  void setMethodCallHandler(Future<dynamic> Function(MethodCall)? handler) {
    _fake.handler = handler;
    super.setMethodCallHandler(handler);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReaderVolumeKeyController 生命周期', () {
    test('设置里开启时进入阅读页会打开原生拦截', () async {
      final fake = _FakeKeyChannel();
      final controller = ReaderVolumeKeyController(
        channel: fake.build(),
        onNavigate: (_) {},
      );

      await controller.attach(enabled: true);

      expect(fake.sent, [true], reason: '应下发一次 enable');
      expect(controller.enabled, isTrue);
    });

    test('设置里关闭时进入阅读页不产生多余的原生调用', () async {
      final fake = _FakeKeyChannel();
      final controller = ReaderVolumeKeyController(
        channel: fake.build(),
        onNavigate: (_) {},
      );

      await controller.attach(enabled: false);

      expect(fake.sent, isEmpty, reason: '默认已是 false，无需下发');
      expect(controller.enabled, isFalse);
    });

    test('离开阅读页必须解除拦截，否则全 App 调不了音量', () async {
      final fake = _FakeKeyChannel();
      final controller = ReaderVolumeKeyController(
        channel: fake.build(),
        onNavigate: (_) {},
      );

      await controller.attach(enabled: true);
      await controller.release();

      expect(fake.sent, [true, false]);
      expect(controller.released, isTrue);
    });

    test('未开启也要在 release 时显式下发 false（防原生状态不同步）', () async {
      final fake = _FakeKeyChannel();
      final controller = ReaderVolumeKeyController(
        channel: fake.build(),
        onNavigate: (_) {},
      );

      await controller.attach(enabled: false);
      await controller.release();

      expect(fake.sent, [false]);
    });

    test('同值重复 apply 只打一次平台通道', () async {
      final fake = _FakeKeyChannel();
      final controller = ReaderVolumeKeyController(
        channel: fake.build(),
        onNavigate: (_) {},
      );

      await controller.attach(enabled: true);
      await controller.apply(true);
      await controller.apply(true);

      expect(fake.sent, [true]);
    });

    test('开关往复按顺序下发', () async {
      final fake = _FakeKeyChannel();
      final controller = ReaderVolumeKeyController(
        channel: fake.build(),
        onNavigate: (_) {},
      );

      await controller.attach(enabled: false);
      await controller.apply(true);
      await controller.apply(false);
      await controller.apply(true);

      expect(fake.sent, [true, false, true]);
    });

    test('release 后 apply 不再重新打开拦截', () async {
      final fake = _FakeKeyChannel();
      final controller = ReaderVolumeKeyController(
        channel: fake.build(),
        onNavigate: (_) {},
      );

      await controller.attach(enabled: true);
      await controller.release();
      fake.sent.clear();

      await controller.apply(true);

      expect(fake.sent, isEmpty, reason: 'dispose 后的残留回调不得复活拦截');
      expect(controller.enabled, isFalse);
    });

    test('平台通道抛异常不冒泡到调用方', () async {
      final fake = _FakeKeyChannel(throwOnSend: true);
      final controller = ReaderVolumeKeyController(
        channel: fake.build(),
        onNavigate: (_) {},
      );

      await expectLater(controller.attach(enabled: true), completes);
      await expectLater(controller.release(), completes);
    });
  });

  group('ReaderVolumeKeyController 按键派发', () {
    test('音量上键映射为上一页，下键为下一页', () async {
      final fake = _FakeKeyChannel();
      final events = <ReaderVolumeKeyDirection>[];
      final controller = ReaderVolumeKeyController(
        channel: fake.build(),
        onNavigate: events.add,
      );

      await controller.attach(enabled: true);
      await fake.pressKey('previous');
      await fake.pressKey('next');

      expect(events, [
        ReaderVolumeKeyDirection.previous,
        ReaderVolumeKeyDirection.next,
      ]);
    });

    test('未知方向被忽略，不误翻页', () async {
      final fake = _FakeKeyChannel();
      final events = <ReaderVolumeKeyDirection>[];
      final controller = ReaderVolumeKeyController(
        channel: fake.build(),
        onNavigate: events.add,
      );

      await controller.attach(enabled: true);
      await fake.pressKey('sideways');
      await fake.pressKey('');

      expect(events, isEmpty);
    });

    test('release 后到达的按键回调不再触发翻页', () async {
      final fake = _FakeKeyChannel();
      final events = <ReaderVolumeKeyDirection>[];
      final controller = ReaderVolumeKeyController(
        channel: fake.build(),
        onNavigate: events.add,
      );

      await controller.attach(enabled: true);
      await controller.release();
      await fake.pressKey('next');

      expect(events, isEmpty, reason: '已离开阅读页，翻页目标已失效');
    });
  });
}
