import 'package:flutter/services.dart';

/// 亮度 / 音量手势的落点（④）。
///
/// 原生侧见 `android/app/src/main/kotlin/top/hpa888/box/PlayerGestureChannel.kt`：
///   - 亮度只改**当前窗口**（不改系统设置，免授权；跟随系统时读到 -1）；
///   - 音量走媒体流（STREAM_MUSIC）。
///
/// 约定：任何失败都返回 null / false，调用方静默降级 —— 手势是锦上添花，
/// 拿不到亮度或音量绝不能让播放器崩掉（桌面/测试环境本来就没有这个通道）。
class PlayerGestureChannel {
  PlayerGestureChannel({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  /// 与原生约定的通道名。
  static const String channelName = 'top.hpa888.box/player_gesture';

  static final PlayerGestureChannel instance = PlayerGestureChannel();

  final MethodChannel _channel;

  /// 当前窗口亮度 0..1；-1 = 跟随系统；取不到是 null。
  Future<double?> getBrightness() async {
    final value = await _invokeDouble('getBrightness');
    return value;
  }

  /// 设定窗口亮度 0..1。传负数 = 交还系统（用于退出播放器时还原）。
  Future<bool> setBrightness(double value) => _invokeBool(
        'setBrightness',
        <String, Object?>{'value': value},
      );

  /// 媒体音量 0..1；取不到是 null。
  Future<double?> getVolume() async {
    try {
      final map = await _channel.invokeMapMethod<String, Object?>('getVolume');
      final current = map?['current'];
      if (current is num && current >= 0) return current.toDouble();
      return null;
    } catch (_) {
      // MissingPluginException / PlatformException / 其它：一律当"没有这个能力"。
      return null;
    }
  }

  /// 设定媒体音量 0..1。
  Future<bool> setVolume(double value) => _invokeBool(
        'setVolume',
        <String, Object?>{'value': value},
      );

  Future<double?> _invokeDouble(String method) async {
    try {
      return await _channel.invokeMethod<double>(method);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _invokeBool(
    String method,
    Map<String, Object?> args,
  ) async {
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// 手势数值换算（纯逻辑，单独放出来是为了能单测）。
class PlayerGestureMath {
  /// 拖动距离换算成量程的比例：拖 0.8 屏 ≈ 走满 100%（1:1 一屏太钝，
  /// 0.8 屏手感更跟手，同时也留得住细调）。
  static const double travelRatio = 0.8;

  /// 亮度读到 -1（跟随系统）时的起手值 —— 不取 0 也不取 1，避免一碰就极端。
  static const double fallbackBrightness = 0.5;

  /// 上下拖 → 新数值（向上拖 = 变大）。结果恒在 0..1。
  ///
  /// [deltaY] 是本次移动的纵向增量（向下为正，与 Flutter 一致）。
  static double applyDelta({
    required double current,
    required double deltaY,
    required double trackHeight,
  }) {
    if (trackHeight <= 0 || !deltaY.isFinite) {
      return current.clamp(0.0, 1.0);
    }
    final travel = trackHeight * travelRatio;
    return (current - deltaY / travel).clamp(0.0, 1.0);
  }

  /// 把原生读回的亮度规整成可用的起手值（-1 / null → [fallbackBrightness]）。
  static double normalizeBrightness(double? raw) {
    if (raw == null || raw < 0) return fallbackBrightness;
    return raw.clamp(0.0, 1.0);
  }

  /// 0..1 → 百分比文案（用于浮层）。
  static String percentText(double value) =>
      '${(value.clamp(0.0, 1.0) * 100).round()}%';

  /// 手势落在哪一侧：左半屏调亮度，右半屏调音量。
  /// 单独抽出来是为了让「哪半边管什么」有测试盯着，不靠肉眼。
  static bool isBrightnessSide({required double dx, required double width}) {
    if (width <= 0) return true;
    return dx < width / 2;
  }
}
