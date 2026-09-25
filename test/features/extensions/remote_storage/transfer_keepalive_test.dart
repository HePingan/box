// 传输保活通道（284 P1）：三个方法各自打到原生、参数对、异常与"没实现"都降级。

import 'package:box/features/extensions/plugins/remote_storage/data/transfer_keepalive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(TransferKeepAlive.channelName);
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

  test('start/update/stop 打到原生，文案按约定传下去', () async {
    mock((call) async {
      calls.add(call);
      return null;
    });
    final keepAlive = TransferKeepAlive();

    await keepAlive.start(title: 'Box 传输中', text: '正在传输 2 项');
    await keepAlive.update(text: '正在传输 1 项 · 50%');
    await keepAlive.stop();

    expect(calls.map((c) => c.method), ['start', 'update', 'stop']);
    expect((calls[0].arguments as Map)['title'], 'Box 传输中');
    expect((calls[0].arguments as Map)['text'], '正在传输 2 项');
    expect((calls[1].arguments as Map)['text'], '正在传输 1 项 · 50%');
  });

  test('原生抛 PlatformException：吞掉（不影响传输本身）', () async {
    mock((_) async => throw PlatformException(code: 'foreground_denied'));

    await expectLater(
      TransferKeepAlive().start(title: 't', text: 'x'),
      completes,
    );
  });

  test('通道不存在（非 Android / 单测环境）：静默降级', () async {
    // 不注册 handler → MissingPluginException
    await expectLater(TransferKeepAlive().stop(), completes);
  });
}
