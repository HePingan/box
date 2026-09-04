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

  test('退出分屏必须采 layout 后尺寸：朋友机日志最后停在 layout 前的 1728', () {
    // 红米 K80 / HyperOS，2026-09-04T18:33:22 现场（用户原文，未改字）：
    //   window_focus:false  size=1080x2400  multiWindow=false
    //   multi_window:true   size=1080x2400  multiWindow=true   ← layout 前
    //   configuration_changed size=1080x2400 multiWindow=true  ← layout 前
    //   window_focus:true   size=1080x1728  multiWindow=true   ← 进入分屏后才更新
    //   ... 分屏内两次失焦/回焦，尺寸一直 1728 ...
    //   multi_window:false  size=1080x1728  multiWindow=false  ← 退出仍是旧高
    //   configuration_changed size=1080x1728 multiWindow=false ← 之后再无采样
    // 同步读 decorView 不能当「高度卡住」的证据；必须另记 Configuration
    // 的 dp，并在 layout 后（或超时未 layout）再采一次。
    final source = File(mainActivityPath).readAsStringSync();

    expect(
      source,
      contains('configDp='),
      reason: 'lifecycle 回调里 decorView 还是旧像素；'
          'Configuration.screenWidthDp/HeightDp 是新配置，必须写进同一条。',
    );
    expect(
      source,
      contains('after_layout'),
      reason: '退出分屏那两行是 layout 前采样。没有 after_layout，'
          '1080x1728 无法区分「日志采早了」和「窗口真卡住」。',
    );
    expect(
      source,
      contains('after_layout_timeout'),
      reason: '高度若真卡住，OnLayoutChangeListener 根本不响；'
          '必须有超时采样，才能在 App 内日志里看到「layout 没来」。',
    );
    expect(
      source,
      contains('AFTER_LAYOUT_LOG_TIMEOUT_MS'),
      reason: '超时是启发式，必须是命名常量，不能写死魔法数字。',
    );
    expect(
      source.contains('scheduleAfterLayoutLog') &&
          !RegExp(r'scheduleAfterLayoutLog\(\s*"resume"').hasMatch(source) &&
          !RegExp(r'scheduleAfterLayoutLog\(\s*"window_focus').hasMatch(source),
      isTrue,
      reason: 'resume/焦点变化本身常发生在 layout 后，再预约会把 1000 行环刷满。'
          '只在 multi_window 与 configuration_changed 两条 layout 前回调里预约。',
    );
  });
}
