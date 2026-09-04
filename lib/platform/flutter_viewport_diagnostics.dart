import 'package:flutter/widgets.dart';

import '../utils/app_logger.dart';

/// Flutter 侧视口诊断：把 `didChangeMetrics` 的真实尺寸落进「调试日志」。
///
/// 为什么需要它：原生 [FlutterWindowDiagnostics] 只能证明 **Android 窗口** 的
/// 尺寸变化。朋友机 K80 退出分屏的日志显示原生 24ms 内就从 1080x1728 恢复到
/// 1080x2400、也没有 `after_layout_timeout`——原生这层是好的。但 Flutter 的
/// `physicalSize` 有没有跟着回来，日志里此前是**完全空白**的。
///
/// 「原生窗口恢复了、Flutter 视口没跟上」表现给用户同样是「退出分屏后界面还是
/// 小窗那么高」。少了这一层日志就没法区分这两种情况，只能靠猜。
///
/// 记 `logicalSize` 是因为布局真正用的是逻辑尺寸（physicalSize / dpr），
/// 与原生的 `configDp` 可以直接对照：错位就说明 Flutter 侧没同步。
class FlutterViewportDiagnostics with WidgetsBindingObserver {
  /// 与原生 tag（`BoxFlutterWindow`）并列的独立 tag：
  /// 用户一次复制就能拿到两层，前缀不同便于分辨是哪层报的。
  static const String logTag = 'BoxFlutterViewport';

  final AppLogger _logger;

  FlutterViewportDiagnostics({AppLogger? logger})
    : _logger = logger ?? AppLogger.instance;

  bool _attached = false;
  Size? _lastPhysicalSize;
  double? _lastDevicePixelRatio;

  bool get attached => _attached;

  void attach() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);

    // 记一条初始基线：没有它就无法判断第一次变化是「从多少变过来的」。
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view != null) {
      _record(view.physicalSize, view.devicePixelRatio, reason: 'attach');
    }
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeMetrics() {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null) return;
    _record(view.physicalSize, view.devicePixelRatio, reason: 'metrics');
  }

  /// 供测试直接投喂尺寸——测试环境改不动真实 view 的 physicalSize。
  @visibleForTesting
  void debugRecordMetrics(Size physicalSize, double devicePixelRatio) {
    _record(physicalSize, devicePixelRatio, reason: 'metrics');
  }

  void _record(Size physicalSize, double devicePixelRatio, {
    required String reason,
  }) {
    if (!_attached) return;

    // 小窗拖拽会高频触发 didChangeMetrics。AppLogger 只有 1000 行环形缓冲，
    // 不去重会把白屏/高度异常的现场上下文顶掉。
    if (_lastPhysicalSize == physicalSize &&
        _lastDevicePixelRatio == devicePixelRatio) {
      return;
    }
    _lastPhysicalSize = physicalSize;
    _lastDevicePixelRatio = devicePixelRatio;

    final logicalW = (physicalSize.width / devicePixelRatio).round();
    final logicalH = (physicalSize.height / devicePixelRatio).round();

    _logger.log(
      'event=$reason '
      'physicalSize=${physicalSize.width.round()}x${physicalSize.height.round()} '
      'logicalSize=${logicalW}x$logicalH '
      'dpr=$devicePixelRatio',
      tag: logTag,
    );
  }
}
