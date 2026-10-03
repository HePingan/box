import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ⑥B 后台播放相关设置（目前只有一项开关）。
///
/// 默认**开**：影视 App 里「息屏/切后台继续出声」是预期行为，
/// 但用户在播放器菜单里可以关掉（关掉就退回老行为：切后台即暂停）。
class VideoPlaybackSettings {
  VideoPlaybackSettings({Future<SharedPreferences> Function()? prefs})
      : _prefs = prefs ?? SharedPreferences.getInstance;

  static const String backgroundPlaybackKey = 'video.background_playback';

  final Future<SharedPreferences> Function() _prefs;

  Future<bool> backgroundPlaybackEnabled() async {
    try {
      final prefs = await _prefs();
      return prefs.getBool(backgroundPlaybackKey) ?? true;
    } catch (_) {
      // 存储坏了也不能让播放卡住：按默认值走。
      return true;
    }
  }

  Future<void> setBackgroundPlaybackEnabled(bool value) async {
    try {
      final prefs = await _prefs();
      await prefs.setBool(backgroundPlaybackKey, value);
    } catch (_) {
      // 写不进去只影响下次启动的默认值，不值得报错。
    }
  }

  @visibleForTesting
  static void resetForTest() {}
}
