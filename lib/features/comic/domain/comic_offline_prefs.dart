// 离线下载的偏好（目前只有一项：仅 Wi-Fi 下载）。
//
// 为什么**默认开**：「下载整本」一开就是几百兆到几个 GB，闷头在移动网络上跑掉的
// 是真金白银。宁可让用户在 5G 上多点一次"这次也用流量"，也不要让他月底才发现。
// 为什么单独一个存储：这是**这台设备/这个用户**的习惯，不是某本书的属性。
library;

import 'package:box/core/storage/cache_store.dart';

/// 离线下载偏好。
class ComicOfflinePrefs {
  ComicOfflinePrefs({CacheStore? cacheStore})
      : _cache = cacheStore ?? CacheStore(namespace: 'comic_offline_prefs');

  final CacheStore _cache;

  static const String _keyWifiOnly = 'wifi_only';

  /// 只在 Wi-Fi 下下载（**默认 true**）。
  ///
  /// 读不出来也当 true：读不到设置时按"省流量"那一档走，最坏是让用户多点一次确认。
  Future<bool> wifiOnly() async {
    final raw = await _cache.read(_keyWifiOnly);
    if (raw == null) return true;
    return raw == true;
  }

  Future<void> setWifiOnly(bool value) async {
    await _cache.write(_keyWifiOnly, value);
  }
}
