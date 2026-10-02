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

  /// 「要不要换成竖向连续」那句提示看过没有（只提示一次）。
  ///
  /// 为什么值得记（2026-10-02 用户：「我还是喜欢上下滑动，现在上下滑动变成亮度调节了」）：
  /// 翻页方式是个图标按钮，靠 tooltip 在手机上根本看不见；他喜欢上下滑（竖向连续），
  /// 却因为当前是左右翻页而滑不动 —— 提示一次、点一下就能切，比让他去猜图标强。
  static const String _keyPageTurnHint = 'page_turn_hint_seen';

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

  /// 读过那句「换成竖向连续」的提示没有（读不出来当没读过 —— 提示一次不算打扰）。
  Future<bool> pageTurnHintSeen() async {
    final raw = await _cache.read(_keyPageTurnHint);
    return raw == true;
  }

  Future<void> setPageTurnHintSeen() async {
    await _cache.write(_keyPageTurnHint, true);
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

  static const String _keyDim = 'dim_level';

  /// 阅读器的**调暗**档位（0 = 不压暗，最大 [_maxDim]）。
  ///
  /// 为什么是"压暗一层黑"而不是改系统亮度：夜里看漫画嫌亮，是"看的内容太亮"，
  /// 压暗就够了；改系统亮度要引平台插件（还要处理权限/恢复），而这一层是纯 UI，
  /// 亮暗实时可见、退出阅读器自动恢复。**代价**：只能往暗里压，不能超过系统亮度。
  static const double maxDim = 0.8;

  /// 读不出来就当 0（不变暗）—— "什么都没发生"比"一进阅读器就黑一截"安全。
  Future<double> dimLevel() async {
    final raw = await _cache.read(_keyDim);
    final v = raw is num ? raw.toDouble() : 0.0;
    return v.clamp(0.0, maxDim).toDouble();
  }

  Future<void> setDimLevel(double value) async {
    await _cache.write(_keyDim, value.clamp(0.0, maxDim).toDouble());
  }
}
