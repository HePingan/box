// 阅读器的偏好（目前只有一项：竖向连续 / 左右翻页）。
//
// 为什么单独一个存储、而且是"全 App 一份"：翻页方式是**看的人的习惯**，
// 不是某本书的属性 —— 在一本页漫里调成左右翻页，切到另一本还要再调一次就很烦。
library;

import 'package:box/core/storage/cache_store.dart';

/// 阅读器偏好（CacheStore 存，清数据时和书架一起清掉）。
class ComicReaderPrefs {
  ComicReaderPrefs({CacheStore? cacheStore})
      : _cache = cacheStore ?? CacheStore(namespace: 'comic_reader_prefs');

  final CacheStore _cache;

  static const String _keyPageTurn = 'page_turn';

  /// 是否用「左右翻页」（false = 竖向连续长条，适合条漫）。
  ///
  /// 读不出来就当 false（竖向连续）：默认值要选"不会让人误以为卡住"的那个。
  Future<bool> pageTurn() async {
    final raw = await _cache.read(_keyPageTurn);
    return raw == true;
  }

  Future<void> setPageTurn(bool value) async {
    await _cache.write(_keyPageTurn, value);
  }
}
