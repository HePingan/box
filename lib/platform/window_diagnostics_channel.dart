import 'dart:async';

import 'package:flutter/services.dart';

import '../utils/app_logger.dart';

/// 原生自由小窗/多窗口诊断事件的接收端。
///
/// 原生 [FlutterWindowDiagnostics] 会把窗口生命周期事件同时写 logcat 和这个
/// 通道。这里把它落进 [AppLogger]，用户就能在「调试日志」页直接复制现场，
/// 不必接电脑用 adb。
///
/// 时序要点：`onResume` / `onWindowFocusChanged` 早于 Dart 注册 handler 触发，
/// 原生侧会缓冲这些早期事件。因此 [attach] 必须在注册 handler **之后**回一次
/// `ready`，触发回放——白屏现场最有价值的恰恰是最早那几条。
class WindowDiagnosticsChannel {
  WindowDiagnosticsChannel({MethodChannel? channel, AppLogger? logger})
    : _channel = channel ?? const MethodChannel(channelName),
      _logger = logger ?? AppLogger.instance;

  static const String channelName = 'top.hpa888.box/window_diagnostics';

  /// 落到 AppLogger 的日志 tag，与原生 logcat tag 保持一致，便于交叉比对。
  static const String logTag = 'BoxFlutterWindow';

  final MethodChannel _channel;
  final AppLogger _logger;

  bool _attached = false;

  bool get attached => _attached;

  /// 注册 handler 并让原生回放缓冲事件。重复调用是安全的。
  Future<void> attach() async {
    if (_attached) return;
    _attached = true;

    _channel.setMethodCallHandler(_handleCall);

    try {
      await _channel.invokeMethod<void>('ready');
    } catch (_) {
      // 非 Android 平台或测试环境没有这个通道：诊断是增强能力，
      // 不能因为它不可用就打断启动流程。
    }
  }

  Future<void> _handleCall(MethodCall call) async {
    if (call.method != 'onWindowEvent') return;

    final message = (call.arguments as Map?)?['message'] as String?;
    if (message == null || message.trim().isEmpty) return;

    _logger.log(message, tag: logTag);
  }

  /// 停止接收（当前仅测试用；生产侧随进程存活）。
  void detach() {
    if (!_attached) return;
    _attached = false;
    _channel.setMethodCallHandler(null);
  }
}
