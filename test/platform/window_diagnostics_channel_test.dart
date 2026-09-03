import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/platform/window_diagnostics_channel.dart';
import 'package:box/utils/app_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(WindowDiagnosticsChannel.channelName);
  final binding = TestDefaultBinaryMessengerBinding.instance;

  setUp(() async {
    await AppLogger.instance.clear();
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('attach 后必须回 ready，否则原生缓冲的早期事件永远不会回放', () async {
    final calls = <String>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      return null;
    });

    final sut = WindowDiagnosticsChannel();
    await sut.attach();

    expect(
      calls,
      contains('ready'),
      reason: 'onResume/焦点变化早于 Dart 注册，不回 ready 就拿不到白屏最初那几条。',
    );
    expect(sut.attached, isTrue);
  });

  test('原生推来的窗口事件落进 AppLogger，用户可在调试日志页复制', () async {
    final sut = WindowDiagnosticsChannel();
    await sut.attach();

    await binding.defaultBinaryMessenger.handlePlatformMessage(
      WindowDiagnosticsChannel.channelName,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onWindowEvent', {
          'message':
              'event=multi_window:true renderMode=texture size=1080x1320 '
              'multiWindow=true orientation=1',
        }),
      ),
      (_) {},
    );

    final text = await AppLogger.instance.exportText();
    expect(
      text,
      contains('renderMode=texture'),
      reason: '原生诊断必须能在 App 内被看到，这是免 adb 取证的唯一通道。',
    );
    expect(text, contains('multiWindow=true'));
    expect(
      text,
      contains(WindowDiagnosticsChannel.logTag),
      reason: 'tag 要与原生 logcat 一致，便于两边交叉比对。',
    );
  });

  test('空消息被忽略，不污染只有 1000 行的日志缓冲', () async {
    final sut = WindowDiagnosticsChannel();
    await sut.attach();

    for (final bad in <Object?>[null, '', '   ']) {
      await binding.defaultBinaryMessenger.handlePlatformMessage(
        WindowDiagnosticsChannel.channelName,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('onWindowEvent', {'message': bad}),
        ),
        (_) {},
      );
    }

    final text = await AppLogger.instance.exportText();
    expect(text.contains(WindowDiagnosticsChannel.logTag), isFalse);
  });

  test('通道不可用时 attach 不抛，诊断失败不能拖垮启动', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      throw MissingPluginException('no impl');
    });

    final sut = WindowDiagnosticsChannel();
    await expectLater(sut.attach(), completes);
  });
}
