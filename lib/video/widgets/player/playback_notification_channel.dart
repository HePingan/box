import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// ⑥B 媒体通知 + 后台保活的 Dart 侧落点。
///
/// 原生侧见 `android/app/src/main/kotlin/top/hpa888/box/PlaybackNotificationChannel.kt`
/// 与 `PlaybackKeepAliveService.kt`：Dart 只说「现在播的是谁、在不在播」，
/// 通知长什么样、点一下怎么走，全在原生那侧（它才是被系统杀进程时唯一还活着的一层）。
///
/// 原生往这边推两类事件：
///   - 通知上的按钮：`toggle` / `previous` / `next`
///   - 音频焦点被抢（来电、别的 App 放音）：`audioFocusLost`
///
/// 失败一律 false / 静默：桌面与测试环境没有这个通道。
class PlaybackNotificationChannel {
  PlaybackNotificationChannel({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_onPlatformCall);
  }

  /// 与原生约定的通道名。
  static const String channelName = 'top.hpa888.box/video_playback';

  static final PlaybackNotificationChannel instance =
      PlaybackNotificationChannel();

  static const String commandToggle = 'toggle';
  static const String commandPrevious = 'previous';
  static const String commandNext = 'next';
  static const String commandAudioFocusLost = 'audioFocusLost';

  final MethodChannel _channel;
  final StreamController<String> _commands = StreamController<String>.broadcast();

  /// 通知按钮与音频焦点事件。用广播流是因为同一条命令可能连续来两次
  /// （用户连点两下暂停/播放），ValueNotifier 会漏掉重复值。
  Stream<String> get commands => _commands.stream;

  /// 起前台服务 + 常驻媒体通知（已在跑则只更新文案）。
  Future<bool> start({
    required String title,
    required String text,
    required bool playing,
  }) =>
      _invokeBool('start', <String, Object?>{
        'title': title,
        'text': text,
        'playing': playing,
      });

  /// 更新通知（换集、播放/暂停、缓冲状态）。
  Future<bool> update({
    required String title,
    required String text,
    required bool playing,
  }) =>
      _invokeBool('update', <String, Object?>{
        'title': title,
        'text': text,
        'playing': playing,
      });

  /// 收工并撤掉通知（回到前台、或用户关掉后台播放）。
  Future<bool> stop() => _invokeBool('stop', const <String, Object?>{});

  Future<bool> _invokeBool(String method, Map<String, Object?> args) async {
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  Future<dynamic> handlePlatformCall(MethodCall call) => _onPlatformCall(call);

  @visibleForTesting
  void disposeForTest() {
    _commands.close();
  }

  Future<dynamic> _onPlatformCall(MethodCall call) async {
    if (call.method != 'onCommand') return null;
    final command = call.arguments;
    if (command is String && !_commands.isClosed) {
      _commands.add(command);
    }
    return null;
  }
}
