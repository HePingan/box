import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 画中画（⑥A）的 Dart 侧落点。
///
/// 原生侧见 `android/app/src/main/kotlin/top/hpa888/box/PlayerPipChannel.kt`：
///   - `enter` 进小窗（API 26+）；
///   - `setAutoEnter` 播放中上滑回桌面自动进小窗（API 31+，老系统返回 false）；
///   - 原生推 `pipModeChanged` 告诉我们「现在在小窗里」。
///
/// 为什么只在**全屏播放态**用：PiP 缩的是整个 Activity —— 内嵌在详情页里进小窗，
/// 用户看到的是整个详情页被压扁，没有意义。
///
/// 失败一律 false / 静默：桌面与测试环境没有这个通道，画中画不该影响播放。
class PlayerPipChannel {
  PlayerPipChannel({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_onPlatformCall);
  }

  /// 与原生约定的通道名。
  static const String channelName = 'top.hpa888.box/player_pip';

  static final PlayerPipChannel instance = PlayerPipChannel();

  final MethodChannel _channel;

  /// 现在是不是小窗态（由原生推上来）。控件据此收起顶栏/底栏，
  /// 容器据此**不要**因为 lifecycle=paused 就把播放暂停。
  final ValueNotifier<bool> isInPip = ValueNotifier<bool>(false);

  /// 这台机器/这个系统支持画中画吗（API 26+ 且声明了 supportsPictureInPicture）。
  Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 进小窗。[width]/[height] 是期望的宽高比（默认 16:9）。
  Future<bool> enter({int width = 16, int height = 9}) async {
    try {
      return await _channel.invokeMethod<bool>(
            'enter',
            <String, Object?>{'width': width, 'height': height},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// 播放中自动进小窗（API 31+ 才真的生效，返回值说明有没有设上）。
  Future<bool> setAutoEnter({
    required bool enabled,
    int width = 16,
    int height = 9,
  }) async {
    try {
      return await _channel.invokeMethod<bool>(
            'setAutoEnter',
            <String, Object?>{
              'enabled': enabled,
              'width': width,
              'height': height,
            },
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  Future<dynamic> handlePlatformCall(MethodCall call) => _onPlatformCall(call);

  Future<dynamic> _onPlatformCall(MethodCall call) async {
    if (call.method == 'pipModeChanged') {
      isInPip.value = call.arguments == true;
    }
    return null;
  }

  @visibleForTesting
  void resetForTest() {
    isInPip.value = false;
  }
}
