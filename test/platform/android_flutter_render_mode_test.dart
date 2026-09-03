import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const mainActivityPath =
      'android/app/src/main/kotlin/top/hpa888/box/MainActivity.kt';

  test('K80 自由小窗强制使用 TextureView，避免 SurfaceView resize 后丢帧', () {
    final source = File(mainActivityPath).readAsStringSync();

    expect(
      source,
      contains('import io.flutter.embedding.android.RenderMode'),
      reason: '必须能显式选择 Flutter 渲染承载 View，不能继续依赖默认 SurfaceView。',
    );
    expect(
      source,
      contains('override fun getRenderMode(): RenderMode = RenderMode.texture'),
      reason: 'HyperOS 自由小窗缩放后 SurfaceView 可能失去绘制层；必须走 TextureView。',
    );
  });

  test('诊断日志双出口：logcat 之外必须推给 Dart，用户才能免 adb 取证', () {
    final diagnostics = File(
      'android/app/src/main/kotlin/top/hpa888/box/FlutterWindowDiagnostics.kt',
    ).readAsStringSync();

    expect(
      diagnostics,
      contains('Log.i(tag, message)'),
      reason: 'Dart 侧卡死时 logcat 是唯一还能出数的通道，不能被替换掉。',
    );
    expect(
      diagnostics,
      contains('top.hpa888.box/window_diagnostics'),
      reason: '需要独立通道把事件送进 App 内「调试日志」页。',
    );
    expect(
      diagnostics,
      allOf(contains('pending'), contains('onDartReady')),
      reason: 'onResume/焦点变化早于引擎就绪，必须缓冲并在 Dart ready 后回放。',
    );
    expect(
      diagnostics,
      contains('MAX_BUFFERED'),
      reason: '缓冲要有上限，诊断日志不值得为它 OOM。',
    );

    final mainActivity = File(mainActivityPath).readAsStringSync();
    expect(
      mainActivity,
      contains('FlutterWindowDiagnostics.record('),
      reason: '窗口事件必须走统一出口，绕过它就只剩 logcat 一份。',
    );
    expect(
      mainActivity,
      contains('FlutterWindowDiagnostics.detachChannel()'),
      reason: 'Activity 销毁必须解绑，否则重建后事件投向失效 channel 静默丢失。',
    );
  });

  test('小窗异常时记录真实窗口尺寸、multi-window 状态与焦点，便于下次取证', () {
    final source = File(mainActivityPath).readAsStringSync();

    expect(
      source,
      contains('FlutterWindowDiagnostics'),
      reason: '需要把 ROM 小窗的真实窗口状态写入 logcat，不能只凭截图继续猜。',
    );
    expect(
      source,
      contains('onMultiWindowModeChanged'),
      reason: '拖拽/切换 HyperOS 小窗时必须采集 multi-window 回调。',
    );
    expect(
      source,
      contains('onWindowFocusChanged'),
      reason: '白屏时必须能区分窗口失焦与 Flutter 绘制层未恢复。',
    );
    expect(
      source,
      contains('onConfigurationChanged'),
      reason: '自由小窗拖拽缩放会分发配置变化，必须记录这个真实事件。',
    );
  });
}
