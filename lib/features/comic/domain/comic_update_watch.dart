// 「追更」：记住"我看到的目录"，之后只比对**最新一话有没有变**。
//
// 为什么这么做（2026-10-02 用户提的下一步）：收藏里的书哪本更了，现在只能一本本打开看。
// 这件事本身不难，难在两处：
//   * **别一进页面就发 N 个请求** —— 收藏十几本时那是十几次站点取数。所以：限流
//     （默认 6 小时）+ 每次只查少数几本 + 只查"该查的"；
//   * **别误报** —— 取不到 HTML、规则解析不出目录、站点抽风，一律当"没有消息"（保持原样）。
//     一次网络抖动就把所有书标成"有新话"，这个标记就没人信了。**宁可漏报，不可误报。**
//
// 另一条边界：收藏里没记"来自哪个书源"，解析统一用**内置那份源的规则**。所以别的站的
// 书多半解析不出来 —— 结果是"没有新话"，不是错报。这条写在这里，免得以后有人以为
// "怎么老是不提示"。
library;

import 'dart:convert';

import 'package:box/core/storage/cache_store.dart';

import 'comic_fetcher.dart';
import 'comic_html_engine.dart';
import 'comic_relay.dart';
import 'sources/seed_comic_source.dart';
import 'comic_source.dart'
    show
        ComicSource,
        firstSelectorRule,
        firstSelectorCss,
        cssFromComicRule;

/// 一本书的"追更"记录：我看到过的目录 + 上次查的时间。
class ComicUpdateRecord {
  const ComicUpdateRecord({
    required this.bookUrl,
    required this.chapterCount,
    required this.firstTitle,
    required this.firstUrl,
    required this.lastTitle,
    required this.lastUrl,
    required this.checkedAt,
    this.newCount = 0,
  });

  final String bookUrl;

  /// 我看到时的总话数。
  final int chapterCount;

  /// 目录**两头**（站点有的最新在前、有的最旧在前，两头都记就不用猜是哪种）。
  final String firstTitle;
  final String firstUrl;
  final String lastTitle;
  final String lastUrl;

  /// 上次查的时间（毫秒）。限流看它。
  final int checkedAt;

  /// 查到的新话数（>0 才显示角标）。
  final int newCount;

  bool get hasNew => newCount > 0;

  ComicUpdateRecord copyWith({int? newCount, int? checkedAt}) =>
      ComicUpdateRecord(
        bookUrl: bookUrl,
        chapterCount: chapterCount,
        firstTitle: firstTitle,
        firstUrl: firstUrl,
        lastTitle: lastTitle,
        lastUrl: lastUrl,
        checkedAt: checkedAt ?? this.checkedAt,
        newCount: newCount ?? this.newCount,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'bookUrl': bookUrl,
    'count': chapterCount,
    'firstTitle': firstTitle,
    'firstUrl': firstUrl,
    'lastTitle': lastTitle,
    'lastUrl': lastUrl,
    'checkedAt': checkedAt,
    'newCount': newCount,
  };

  static ComicUpdateRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final url = (m['bookUrl'] as String?)?.trim() ?? '';
    if (url.isEmpty) return null;
    int intOf(String k) => (m[k] is num) ? (m[k] as num).toInt() : 0;
    String strOf(String k) => (m[k] as String?)?.trim() ?? '';
    return ComicUpdateRecord(
      bookUrl: url,
      chapterCount: intOf('count'),
      firstTitle: strOf('firstTitle'),
      firstUrl: strOf('firstUrl'),
      lastTitle: strOf('lastTitle'),
      lastUrl: strOf('lastUrl'),
      checkedAt: intOf('checkedAt'),
      newCount: intOf('newCount'),
    );
  }
}

/// 追更的记录本（按书存一条）。
class ComicUpdateWatch {
  ComicUpdateWatch({
    CacheStore? cacheStore,
    ComicSource? source,
    ComicFetcher? fetcher,
  })  : _cache = cacheStore ?? CacheStore(namespace: 'comic_updates'),
        _source = source,
        _fetcher = fetcher;

  final CacheStore _cache;

  /// 解析目录用的书源规则（默认为空 = 由调用方给；没给就查不了）。
  final ComicSource? _source;

  /// 取数器（默认直连站点，带手机 UA；测试注入假的）。
  final ComicFetcher? _fetcher;

  ComicFetcher? _direct;

  /// 真的去取数的那一个（默认直连；测试注入的优先）。
  ComicFetcher get _fetcherOrDirect {
    final injected = _fetcher;
    if (injected != null) return injected;
    return _direct ??= ComicDirectFetcher();
  }

  /// 同一本书两次自动检查的最小间隔。**这是"别一进页面就 N 个请求"的那道闸。**
  static const Duration defaultMinInterval = Duration(hours: 6);

  /// 一次最多查几本（点刷新时按收藏顺序，越靠前越新收的越先查）。
  static const int defaultBatch = 3;

  /// 单本取数上限：追更是顺手看一眼，不是用户等着用的东西，不能拖。
  static const Duration fetchTimeout = Duration(seconds: 10);

  String _keyOf(String bookUrl) => 'book_${bookUrl.trim()}';

  /// 读一本书的记录。**任何失败都当"没有记录"**（含存储本身读不了）：
  /// 追更是装饰，不该因为它让收藏页变成"加载失败"。
  Future<ComicUpdateRecord?> read(String bookUrl) async {
    try {
      final raw = await _cache.read(_keyOf(bookUrl));
      if (raw is String) return ComicUpdateRecord.fromJson(jsonDecode(raw));
      if (raw is Map) return ComicUpdateRecord.fromJson(raw);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 写记录同样不抛（写不进去最多是角标多挂一会）。
  Future<void> _write(ComicUpdateRecord record) async {
    try {
      await _cache.write(_keyOf(record.bookUrl), jsonEncode(record.toJson()));
    } catch (_) {
      // 忽略：见上。
    }
  }

  /// 记下"我现在看到的目录"（用户已经看见了 → 角标清掉）。
  ///
  /// [latestFirst] 由调用方告知站点是"最新在前"还是"最旧在前"；两头都存，
  /// 所以这里只是把两端原样记下来。
  Future<void> seen({
    required String bookUrl,
    required List<String> titles,
    required List<String> urls,
    int? nowMs,
  }) async {
    if (urls.isEmpty) return;
    final at = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    await _write(
      ComicUpdateRecord(
        bookUrl: bookUrl,
        chapterCount: urls.length,
        firstTitle: titles.isNotEmpty ? titles.first : '',
        firstUrl: urls.first,
        lastTitle: titles.isNotEmpty ? titles.last : '',
        lastUrl: urls.last,
        checkedAt: at,
      ),
    );
  }

  /// 查一本：拉最新目录，跟记下的比。**取不到/解析不出就原样返回**（不误报）。
  ///
  /// [force] = 用户明确点了刷新（跳过限流）。
  Future<ComicUpdateRecord?> check(
    String bookUrl, {
    bool force = false,
    Duration minInterval = defaultMinInterval,
  }) async {
    final url = bookUrl.trim();
    final source = _source;
    if (url.isEmpty || source == null) return read(url);

    final before = await read(url);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force &&
        before != null &&
        before.checkedAt > 0 &&
        now - before.checkedAt < minInterval.inMilliseconds) {
      return before; // 刚查过（限流）
    }

    List<String> titles;
    List<String> urls;
    try {
      final html = await _fetcherOrDirect.getText(url).timeout(fetchTimeout);
      if (!html.trim().startsWith('<')) return before; // 不是 HTML（WAF 挑战页等）→ 没消息
      final doc = parseComicHtml(html);
      final container = _tocContainerRule(source);
      if (container.isEmpty) return before;
      titles = comicHtmlPerElement(doc, container, source.tocRules['chapterName'] ?? '');
      urls = comicHtmlPerElement(doc, container, source.tocRules['chapterUrl'] ?? '')
          .map((u) => u.trim())
          .where((u) => u.isNotEmpty)
          .map(source.absolute)
          .toList();
    } catch (_) {
      // 取数/解析失败 = "这次没消息"，保留上一次的记录（含它已经带的新话数）。
      return before?.copyWith(checkedAt: now);
    }
    // 规则解析不出目录也算"没消息"：宁可不提示，也不能把所有书都标成有新话。
    if (urls.isEmpty) return before?.copyWith(checkedAt: now);

    final firstTitle = titles.isNotEmpty ? titles.first : '';
    final lastTitle = titles.isNotEmpty ? titles.last : '';
    var newCount = 0;
    if (before != null && before.firstUrl.isNotEmpty) {
      final moved = before.firstUrl != urls.first || before.lastUrl != urls.last;
      if (moved) {
        // 话数涨了就说涨了多少；两头都变了但数目没变（改名/重排）至少算 1 —— 有动静。
        newCount = urls.length > before.chapterCount
            ? urls.length - before.chapterCount
            : 1;
      } else {
        // 目录两头都没动：上次已经提示过的（用户还没去看）要留着，别自己清掉。
        newCount = before.newCount;
      }
    }

    final next = ComicUpdateRecord(
      bookUrl: url,
      chapterCount: urls.length,
      firstTitle: firstTitle,
      firstUrl: urls.first,
      lastTitle: lastTitle,
      lastUrl: urls.last,
      checkedAt: now,
      newCount: newCount,
    );
    await _write(next);
    return next;
  }

  /// 批量查：**先判"该不该查"**（限流 + 最多查几本），再查。返回这次查到的记录。
  ///
  /// 单本失败不影响别的（`check` 自己不抛）。
  Future<Map<String, ComicUpdateRecord>> checkDue(
    Iterable<String> bookUrls, {
    bool force = false,
    int max = defaultBatch,
    Duration minInterval = defaultMinInterval,
  }) async {
    final out = <String, ComicUpdateRecord>{};
    var checked = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final url in bookUrls) {
      if (checked >= max) break;
      final before = await read(url);
      final due = force ||
          before == null ||
          before.checkedAt == 0 ||
          (now - before.checkedAt) >= minInterval.inMilliseconds;
      if (!due) continue;
      final rec = await check(url, force: true); // "该查"已判过，跳过它内部的限流
      if (rec != null) out[rec.bookUrl] = rec;
      checked++;
    }
    return out;
  }

  /// 目录容器规则：取 `tocUrl` 的第一段选择器（与在线页同一套取法，别两处各自演化）。
  static String _tocContainerRule(ComicSource source) {
    final tocRule = source.bookInfoRules['tocUrl'] ?? '';
    return firstSelectorRule(tocRule) ??
        firstSelectorCss(tocRule) ??
        cssFromComicRule(tocRule) ??
        '';
  }

  void close() => _direct?.close();

  /// 追更解析用的书源：**内置清单里的第一份**（在线页默认选中的也是它）。
  ///
  /// 为什么是"默认那份"而不是"每本书记住自己的源"：收藏里没存书源，而用户现在多半
  /// 就用这一份。别的站的书解析不出来 → 结果是"没有新话"，不会误报。
  static ComicSource? defaultComicSource() {
    for (final json in kSeedComicSourcesJson) {
      final parsed = ComicSource.tryParse(json);
      if (parsed != null) return parsed;
    }
    return null;
  }
}

/// 追更取数走哪条：**与阅读同一条退路** —— 配了设备令牌就走自己的中转，否则直连站点。
///
/// 直连要带手机 UA（站点挑客户端特征），`ComicDirectFetcher` 自己会带。
ComicFetcher comicUpdateFetcher(ComicSource source, String relayToken) {
  final spec = source.relay;
  final token = relayToken.trim();
  if (spec != null && token.isNotEmpty) {
    return ComicRelay(endpoint: spec.endpoint, token: token);
  }
  return ComicDirectFetcher();
}
