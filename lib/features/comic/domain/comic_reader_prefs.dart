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
  static const String _keyChapterDescending = 'chapter_descending';

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

  /// 目录是否"倒序"（最新一话在最上面）。
  ///
  /// 为什么值得记（2026-10-02 用户提"目录要能正序/倒序"）：漫画目录动辄几百话，
  /// "最新在最前"和"从头往后"是两种用法 —— 追更的人想看最新，补番的人要从头翻；
  /// 记不住则每次开目录都要再切一次。
  /// **默认正序**：打开目录会自动滚到"正在读"那一话，正序下那个位置稳定、
  /// 上下文也顺着读的方向。
  Future<bool> chapterDescending() async {
    final raw = await _cache.read(_keyChapterDescending);
    return raw == true;
  }

  Future<void> setChapterDescending(bool value) async {
    await _cache.write(_keyChapterDescending, value);
  }
}
