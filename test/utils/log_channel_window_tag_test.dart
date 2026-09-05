import 'package:flutter_test/flutter_test.dart';

import 'package:box/platform/flutter_viewport_diagnostics.dart';
import 'package:box/platform/window_diagnostics_channel.dart';
import 'package:box/utils/log_channels.dart';

/// 回归：小窗/分屏诊断日志必须落进「窗口」频道。
///
/// 背景：`LogChannel.window` 在生产代码里曾经**零使用**——枚举里定义了、
/// 筛选器里露出了「窗口」这个选项，但两个真正写小窗诊断的 tag
/// （原生 `BoxFlutterWindow`、Flutter 侧 `BoxFlutterViewport`）都没登记进
/// `fromTag()`，双双走 default 落进「系统」。
///
/// 后果有两层：
/// 1. 用户按「窗口」筛选，看到的是空列表 —— 恰好是分屏问题唯一该看的频道；
/// 2. 排障时只能让用户复制「系统」频道，而那里混着启动、生命周期等大量噪声。
///
/// 这两条测试直接用生产常量而不是硬编码字符串，这样以后有人改 tag 名
/// 却忘了同步 `fromTag()`，红灯会立刻出现。
void main() {
  group('小窗诊断 tag 归入窗口频道', () {
    test('原生层 BoxFlutterWindow → window', () {
      expect(
        LogChannel.fromTag(WindowDiagnosticsChannel.logTag),
        LogChannel.window,
        reason: '原生窗口诊断是分屏排障的主要证据，必须能被「窗口」频道筛到',
      );
    });

    test('Flutter 层 BoxFlutterViewport → window', () {
      expect(
        LogChannel.fromTag(FlutterViewportDiagnostics.logTag),
        LogChannel.window,
        reason: 'Flutter 视口尺寸用于区分「原生恢复了但 Flutter 没跟上」',
      );
    });

    test('大小写与空格不敏感', () {
      expect(LogChannel.fromTag('  boxflutterwindow '), LogChannel.window);
      expect(LogChannel.fromTag('BOXFLUTTERVIEWPORT'), LogChannel.window);
    });

    test('窗口频道在生产中确实有来源（不是空壳选项）', () {
      // 若将来两个 tag 都被改走别的频道，「窗口」筛选器就又变成空壳，
      // 那种情况下应当一并把筛选器选项移除，而不是留着骗用户。
      final sources = <String>[
        WindowDiagnosticsChannel.logTag,
        FlutterViewportDiagnostics.logTag,
      ];
      expect(
        sources.map(LogChannel.fromTag).where((c) => c == LogChannel.window),
        isNotEmpty,
        reason: '「窗口」频道必须至少有一个真实写入来源',
      );
    });
  });
}
