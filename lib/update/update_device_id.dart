import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// 更新检查用的设备标识（灰度发布靠它认人）。
///
/// ## 为什么需要它
///
/// 服务端的灰度发布是**白名单制**：名单里的 `device_id` 会拿到 beta 渠道的版本，
/// 其余设备照常拿到 release。没有这个标识，服务端就无从区分两台手机。
///
/// ## 为什么不复用答题插件的 `quizVision.deviceId`
///
/// 那个 key 属于答题模块，语义是"答题功能的设备标识"。复用它会让两件事强绑定：
/// 哪天答题模块重置了自己的 id，灰度名单就跟着失效，而且从名字上看不出关联。
/// 这里开一个独立的 key，语义干净、互不影响。
///
/// ## 隐私边界（刻意如此）
///
/// - 只在**检查更新时**随请求发出，不用于其它任何接口；
/// - 是随机 32 位十六进制串，**不含** IMEI / Android ID / 硬件序列号；
/// - 不出现在日志里，不写进备份导出。
/// - 用户可以靠"卸载重装"换一个新 id（等于退出灰度名单）。
class UpdateDeviceId {
  const UpdateDeviceId._();

  /// 存储键。改这个字符串会让已加入灰度的设备「变成陌生设备」——故不复用别的 key。
  static const String prefsKey = 'box.updateDeviceId.v1';

  /// 缓存，避免每次检查更新都读一次 prefs。
  static String? _cached;

  /// 取（必要时生成）本机的更新设备标识。
  ///
  /// 失败一律返回空串：调用方把空串当成"没有标识"处理（服务端据此走 release）。
  /// 更新检查不该因为读不到偏好设置而失败。
  static Future<String> get() async {
    final cached = _cached;
    if (cached != null && cached.isNotEmpty) return cached;

    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(prefsKey);
      if (existing != null && existing.trim().isNotEmpty) {
        _cached = existing.trim();
        return _cached!;
      }

      final generated = generate();
      await prefs.setString(prefsKey, generated);
      _cached = generated;
      return generated;
    } catch (_) {
      // 读/写失败：这次不带标识。服务端会按 release 渠道返回，行为与老版本一致。
      return '';
    }
  }

  /// 生成一个新的标识：32 位小写十六进制（16 字节随机）。
  ///
  /// 用 `Random.secure()`：非安全随机会让多台设备在同一次启动里撞到同一个种子，
  /// 灰度名单就会出现"加了一台、生效了一片"的怪事。
  static String generate() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// 测试用：清掉进程内缓存（不删已落盘的 id）。
  static void resetCacheForTest() {
    _cached = null;
  }
}
