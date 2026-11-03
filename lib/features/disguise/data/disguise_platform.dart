import 'package:flutter/services.dart';

/// 伪装功能在原生侧的能力：桌面图标/名称切换、最近任务缩略图遮挡、分身检测。
///
/// 全部调用都**吞掉异常并返回安全默认值**：伪装是一个可选外观功能，
/// 原生通道因为 ROM 差异挂了，绝不能让应用起不来或者卡在这里。
/// 真正失败时返回 false，由设置页告诉用户「没切成」。
class DisguisePlatform {
  DisguisePlatform({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// 可注入实现，供测试替换。
  static DisguisePlatform instance = DisguisePlatform();

  static const String channelName = 'top.hpa888.box/disguise';

  final MethodChannel _channel;

  /// 当前桌面图标是不是「计算器」。
  ///
  /// 原生侧读的是 PackageManager 里 component 的真实状态，不是本地偏好 ——
  /// OTA 覆盖安装会把 alias 状态重置成 manifest 默认值，只有问系统才知道真相。
  Future<bool> isDisguised() async {
    try {
      final result = await _channel.invokeMethod<bool>('isDisguised');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 切换桌面图标与名称。返回切换后的真实状态。
  Future<bool> setDisguised(bool enabled) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'setDisguised',
        <String, dynamic>{'enabled': enabled},
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 启动自愈：期望值与系统真实状态不一致时重新应用一次。
  ///
  /// 调用点只有一处 —— App 启动。它解决的是「每次更新完图标自己变回极客匣」
  /// 这个必然会发生、且用户一定会当成 bug 的现象。
  Future<bool> heal(bool expected) async {
    final actual = await isDisguised();
    if (actual == expected) return true;
    return setDisguised(expected);
  }

  /// 是否运行在分身 / 多用户身份下（userId != 0）。
  ///
  /// 分身里是**另一份应用数据**：图标、口令、解锁状态都与主身份无关，
  /// 所以设置页要如实说明，别让用户以为伪装失效了。
  Future<bool> isDuplicateApp() async {
    try {
      final result = await _channel.invokeMethod<bool>('isDuplicateApp');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 用 FLAG_SECURE 遮住最近任务里的缩略图。
  ///
  /// 代价是**同时禁用截屏**（系统层面同一条 flag），所以这是个可关的选项，
  /// 默认开启只是因为「多任务卡片里露出真应用」比「截不了屏」更致命。
  Future<void> setSecureRecents(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setSecureFlag', <String, dynamic>{
        'enabled': enabled,
      });
    } catch (_) {
      // 遮不住缩略图不影响功能，静默失败。
    }
  }
}
