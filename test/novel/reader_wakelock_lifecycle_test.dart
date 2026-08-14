import 'package:flutter_test/flutter_test.dart';

import 'package:box/novel/pages/reader/reader_wakelock_controller.dart';

void main() {
  late List<bool> calls;
  late ReaderWakelockController controller;

  setUp(() {
    calls = <bool>[];
    controller = ReaderWakelockController(
      toggle: (v) async => calls.add(v),
    );
  });

  test('按持久化设置开启常亮（回归：以前进入阅读页不应用已保存的开关）', () async {
    await controller.apply(true);
    expect(calls, [true]);
    expect(controller.enabled, isTrue);
  });

  test('持久化设置为关时不多打平台通道', () async {
    await controller.apply(false);
    expect(calls, isEmpty, reason: '初始即为未持有状态，无需下发 disable');
  });

  test('离开阅读页释放常亮（回归：以前从不 disable，App 后续页面持续不息屏）', () async {
    await controller.apply(true);
    calls.clear();
    await controller.release();
    expect(calls, [false]);
    expect(controller.enabled, isFalse);
  });

  test('未开启常亮时释放不产生多余调用', () async {
    await controller.release();
    expect(calls, isEmpty);
  });

  test('重复同值调用被去重，避免拖动亮度条时刷平台通道', () async {
    await controller.apply(true);
    await controller.apply(true);
    await controller.apply(true);
    expect(calls, [true]);
  });

  test('开关往复各只下发一次', () async {
    await controller.apply(true);
    await controller.apply(false);
    await controller.apply(true);
    expect(calls, [true, false, true]);
  });

  test('release 之后不再响应 apply，防止 dispose 后异步回调重新点亮', () async {
    await controller.release();
    calls.clear();
    await controller.apply(true);
    expect(calls, isEmpty);
    expect(controller.enabled, isFalse);
  });

  test('底层插件抛异常不冒泡，阅读流程不受影响', () async {
    final throwing = ReaderWakelockController(
      toggle: (_) async => throw StateError('plugin unavailable'),
    );
    await expectLater(throwing.apply(true), completes);
    await expectLater(throwing.release(), completes);
  });
}
