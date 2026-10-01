// 截图"永不回包"必须自己收尾（2026-10-01 真机事故回归）。
//
// 事故形状：用户点 AI 读屏后界面一直停在「读屏中」，超过 45s 只显示
// 「等待超时，可重新点击 AI 读屏重试」，再点也没反应；服务端**零请求**
// （说明流程根本没走到发请求那一步）。
//
// 根因：截图是 `invokeMethod` 等原生回包，而原生侧只在「自己仍是最新请求」时
// 才回包（`QuizAccessibilityService.currentRequestId`）—— 被更新的请求顶掉、
// 或框架回调异常没到时，**回包被静默丢弃**，Dart 侧又没有超时 ⇒ await 永不返回，
// 整个读屏流程永久悬挂。
//
// 修法两层（本文件锁 Dart 这一层）：
//   1) Dart：三处截图都给 `captureTimeout`（本用例把超时调小到 60ms）；
//   2) Kotlin：恰好完成一次回调 + 6s 看门狗（真机侧，Dart 测不到）。
//
// 判据是**时间**：超时用例必须"很快就返回 null"，而不是断言 null 就完事
// —— 一个永不返回的 await 会让用例自己挂死（这也正是它在真机上的症状）。
import 'dart:async';

import 'package:box/features/quiz_plugin/presentation/quiz_plugin_entry.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('top.hpa888.box/quiz_plugin');

/// 假原生侧：[reply] 为 false 时**永不回包**（模拟真机事故）。
void _mockNative({required bool reply}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        if (!reply) return Completer<Object?>().future;
        switch (call.method) {
          case 'captureRegionScreenshot':
            return <String, Object?>{
              'bytes': Uint8List.fromList(List<int>.filled(16, 7)),
              'dHash': 'abcdef01',
            };
          case 'captureImageRegionScreenshot':
            return <String, Object?>{'dHash': 'abcdef01'};
          default:
            return null;
        }
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // 真等 8s 太慢；超时口径本身不变。
    QuizPluginEntry.captureTimeout = const Duration(milliseconds: 60);
  });

  tearDown(() {
    QuizPluginEntry.captureTimeout = const Duration(seconds: 8);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('原生永不回包 → 截图按超时收尾，不再无限等', () async {
    _mockNative(reply: false);
    final sw = Stopwatch()..start();

    final bytes = await QuizPluginEntry.captureRegionScreenshot();

    expect(bytes, isNull, reason: '超时按「没拿到截图」处理');
    expect(
      sw.elapsed,
      lessThan(const Duration(seconds: 2)),
      reason: '必须在超时附近收尾：永不返回的 await 会让整个读屏流程悬挂',
    );
  });

  test('题图区域 dHash 同样受超时保护', () async {
    _mockNative(reply: false);
    final sw = Stopwatch()..start();

    final hash = await QuizPluginEntry.captureImageRegionHash();

    expect(hash, isNull);
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('原生正常回包 → 字节照旧返回（超时没破坏正常路径）', () async {
    _mockNative(reply: true);

    final bytes = await QuizPluginEntry.captureRegionScreenshot();

    expect(bytes, isNotNull);
    expect(bytes!.length, 16);
  });

  test('手动路径：首答快速回空（疑似被顶掉）→ 自动补一次', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method != 'captureRegionScreenshot') return null;
          calls++;
          if (calls == 1) return null; // 被更新的请求顶掉：很快回空
          return <String, Object?>{
            'bytes': Uint8List.fromList(List<int>.filled(16, 9)),
            'dHash': 'abcdef01',
          };
        });

    final bytes = await QuizPluginEntry.captureRegionScreenshot(
      retryIfQuickNull: true,
    );

    expect(bytes, isNotNull, reason: '补一次应能拿到字节');
    expect(calls, 2);
  });

  test('超时（原生不回包）不补：不额外再等一个超时', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls++;
          return Completer<Object?>().future;
        });

    final bytes = await QuizPluginEntry.captureRegionScreenshot(
      retryIfQuickNull: true,
    );

    expect(bytes, isNull);
    expect(calls, 1, reason: '超时后再补一次只会让用户多等 8 秒');
  });

  test('手动读屏拿不到截图 → 给可行动原因，而不是「未搜到答案」', () {
    final hint = QuizPluginEntry.visionCaptureFailureHint();

    expect(hint, contains('无障碍'), reason: '要指出去哪里检查');
    expect(hint, contains('截图'));
    expect(
      hint,
      isNot(contains('未搜到答案')),
      reason: '不能说成「未搜到答案，点右上角紫色 AI 按钮」——那是让用户点必然再失败的按钮',
    );
  });
}
