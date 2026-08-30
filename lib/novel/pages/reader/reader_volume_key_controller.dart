import 'dart:async';

import 'package:flutter/services.dart';

/// 音量键翻页方向。
enum ReaderVolumeKeyDirection { previous, next }

/// 音量键翻页控制器。
///
/// 原生侧 [MainActivity.dispatchKeyEvent] 只在 `volumeKeyNavEnabled == true`
/// 时拦截音量键，其余情况放行给系统。这个开关的生命周期由本类负责：
///
///   - 进入阅读页 + 设置里开了 volumeKeyNav → [attach] 打开拦截
///   - 用户在设置面板拨动开关 → [apply] 跟随
///   - 离开阅读页 → [release] 必须关掉拦截
///
/// 最后一条是硬约束：拦截标志位活在 Activity 上而不是页面上，
/// 忘记释放的话用户离开阅读页后整个 App 都调不了系统音量，
/// 只能杀进程恢复。和 wakelock 一样采用「终态不可逆」设计，
/// 防止 dispose 后残留的异步回调重新打开拦截。
class ReaderVolumeKeyController {
  ReaderVolumeKeyController({
    MethodChannel? channel,
    required this.onNavigate,
  }) : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'top.hpa888.box/reader_keys';

  final MethodChannel _channel;

  /// 收到音量键时的翻页回调。
  final void Function(ReaderVolumeKeyDirection direction) onNavigate;

  bool _enabled = false;
  bool _released = false;
  bool _listening = false;

  /// 当前原生侧是否处于拦截状态（仅用于测试与诊断）。
  bool get enabled => _enabled;

  bool get released => _released;

  /// 开始监听原生回调，并按 [enabled] 应用初始拦截状态。
  Future<void> attach({required bool enabled}) async {
    if (_released) return;
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler(_handleCall);
    }
    await apply(enabled);
  }

  /// 跟随设置变化开/关拦截。同值去重，避免拖动设置项时反复打平台通道。
  Future<void> apply(bool enabled) async {
    if (_released) return;
    if (_enabled == enabled) return;
    _enabled = enabled;
    await _send(enabled);
  }

  /// 离开阅读页：解除拦截并进入终态。
  Future<void> release() async {
    if (_released) return;
    _released = true;
    if (_listening) {
      _listening = false;
      _channel.setMethodCallHandler(null);
    }
    // 无论本地标志位如何，都显式下发一次 false——
    // 本地状态有可能与原生不同步（例如首次 apply 抛异常），
    // 宁可多发一次也不能留下一个吞掉音量键的 Activity。
    _enabled = false;
    await _send(false);
  }

  Future<void> _handleCall(MethodCall call) async {
    if (_released) return;
    if (call.method != 'onVolumeKey') return;
    final raw = (call.arguments as Map?)?['direction'] as String?;
    switch (raw) {
      case 'previous':
        onNavigate(ReaderVolumeKeyDirection.previous);
        break;
      case 'next':
        onNavigate(ReaderVolumeKeyDirection.next);
        break;
      default:
        break;
    }
  }

  Future<void> _send(bool enabled) async {
    try {
      await _channel.invokeMethod<void>(
        'setVolumeKeyNavEnabled',
        {'enabled': enabled},
      );
    } catch (_) {
      // 通道不可用（iOS/桌面/测试环境）时静默降级：
      // 音量键翻页是增强功能，不能因此打断阅读。
    }
  }
}
