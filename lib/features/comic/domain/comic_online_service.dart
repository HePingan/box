// 在线漫画源服务：搜索 / 详情 + 章节 / 章节取图。
//
// 与「源自检」共用同一套引擎与取值逻辑（引擎跑在页面里，WebView 由界面提供）；
// 区别是这里要**结果**，不要逐项结论 —— 失败一律抛出**人话**错误，由界面如实显示。
//
// 两条取值路径分清楚（真机上踩过）：
//   * `_values`：整页取值（书名、作者这类**单值**字段）；
//   * `_perElement`：**按卡片**取字段（列表类：搜索结果、章节目录）。
//     拉平了再按序号配对会错位 —— 真源上 77 张卡片对应 154 条书链。
library;

import 'comic_source.dart';
import 'comic_source_diagnostics.dart'
    show
        ComicSourceTarget,
        comicNavFailureNote,
        openComicWithFallback;
import 'comic_source_engine.dart';
import 'comic_source_diagnostics.dart' show ComicNavOutcome;

/// 搜索结果里的一条书。
class ComicSearchHit {
  const ComicSearchHit({
    required this.name,
    required this.bookUrl,
    this.author,
    this.cover,
  });

  final String name;
  final String bookUrl;
  final String? author;
  final String? cover;
}

/// 章节目录里的一条。
class ComicChapterRef {
  const ComicChapterRef({required this.title, required this.url});

  final String title;
  final String url;
}

/// 书籍详情（含章节目录）。
class ComicBookDetail {
  const ComicBookDetail({
    required this.bookUrl,
    required this.name,
    this.author,
    this.cover,
    this.intro,
    this.chapters = const [],
  });

  final String bookUrl;
  final String name;
  final String? author;
  final String? cover;
  final String? intro;
  final List<ComicChapterRef> chapters;

  /// 从第几话开始读（站点目录是倒序的：第一条是最新一话）。
  ComicChapterRef? get firstChapter => chapters.isEmpty ? null : chapters.first;
}

/// 在线源取数服务。**所有失败都抛 [ComicProbeException]**（带人话说明）。
class ComicOnlineService {
  ComicOnlineService({
    required this.target,
    required this.source,
    this.waitTimeout = const Duration(seconds: 15),
    this.listTimeout = const Duration(seconds: 12),
    this.openTimeout = const Duration(seconds: 20),
    this.pollInterval = const Duration(milliseconds: 250),
  });

  final ComicSourceTarget target;
  final ComicSource source;
  /// 等**图片地址**出现的上限。
  final Duration waitTimeout;

  /// 等**列表**（搜索结果 / 章节目录）出现的上限。
  final Duration listTimeout;

  /// 打开页面这一跳的上限（含镜像候选）。
  final Duration openTimeout;

  final Duration pollInterval;

  /// 搜索：返回书列表（书名/作者/封面/书链）。
  Future<List<ComicSearchHit>> search(String key) async {
    final url = source.searchUrlFor(key);
    if (url == null) {
      throw ComicProbeException('这个书源没给搜索地址（searchUrl 为空），没法搜');
    }
    await _open(url, what: '搜索页');

    final card = source.searchRules['bookList'] ?? '';
    if (card.trim().isEmpty) {
      throw ComicProbeException('书源没给 bookList 规则，取不到卡片');
    }
    await _waitForCount(card, listTimeout);
    final names = await _perElement(card, source.searchRules['name'] ?? '');
    final links = await _perElement(card, source.searchRules['bookUrl'] ?? '');
    final covers = await _perElement(card, source.searchRules['coverUrl'] ?? '');
    final authors = await _perElement(card, source.searchRules['author'] ?? '');
    if (links.every((l) => l.trim().isEmpty)) {
      throw ComicProbeException('卡片取到了，但书链一条都没取到（站点可能改版）');
    }

    final out = <ComicSearchHit>[];
    for (var i = 0; i < links.length; i++) {
      final link = links[i].trim();
      if (link.isEmpty) continue; // 共 1 条时对不齐的数据宁可丢掉，也不张冠李戴
      final name = _at(names, i);
      final cover = _at(covers, i);
      out.add(
        ComicSearchHit(
          name: name ?? '（无书名）',
          bookUrl: source.absolute(link),
          author: _at(authors, i),
          cover: cover == null ? null : source.absolute(cover),
        ),
      );
    }
    return out;
  }

  /// 详情 + 章节目录。
  Future<ComicBookDetail> bookInfo(String bookUrl) async {
    await _open(bookUrl, what: '详情页');

    final name = _firstNonNull(await _values(source.bookInfoRules['name'] ?? ''));
    final author = _firstNonNull(await _values(source.bookInfoRules['author'] ?? ''));
    final cover = _firstNonNull(await _values(source.bookInfoRules['coverUrl'] ?? ''));
    final intro = _firstNonNull(await _values(source.bookInfoRules['intro'] ?? ''));

    final chapters = await _chapters();
    return ComicBookDetail(
      bookUrl: bookUrl,
      name: name ?? '（无书名）',
      author: author,
      cover: cover == null ? null : source.absolute(cover),
      intro: intro,
      chapters: chapters,
    );
  }

  /// 章节目录。容器取 `tocUrl` 规则的**第一段选择器**：
  /// 整条规则里有书源自己写的笔误段（`harf`），整条拼进去会生成永不匹配的 CSS。
  Future<List<ComicChapterRef>> _chapters() async {
    final tocRule = source.bookInfoRules['tocUrl'] ?? '';
    // 两条路各用各的写法（真机上把 CSS 当规则传过一次，整段解析失败 → "共 1 话"）：
    //   * 等渲染：用 CSS（`.a.b`）给页面查询；
    //   * 取字段：用**规则原文**（`class.a b`）给引擎按规则求值。
    final containerCss = firstSelectorCss(tocRule) ?? cssFromComicRule(tocRule) ?? '';
    final containerRule = firstSelectorRule(tocRule) ?? containerCss;
    if (containerCss.isEmpty) {
      throw ComicProbeException('书源的 tocUrl 规则不认识：「$tocRule」');
    }
    // 目录是渲染出来的，**必须等它出现**（不等就会在页面刚打开时数到 0/1 条）。
    await _waitForCount(containerCss, listTimeout);
    final titles = await _perElement(containerRule, source.tocRules['chapterName'] ?? '');
    final urls = await _perElement(containerRule, source.tocRules['chapterUrl'] ?? '');
    final out = <ComicChapterRef>[];
    for (var i = 0; i < urls.length; i++) {
      final u = urls[i].trim();
      if (u.isEmpty) continue;
      final t = _at(titles, i);
      out.add(
        ComicChapterRef(
          title: t ?? '第 ${i + 1} 话',
          url: source.absolute(u),
        ),
      );
    }
    return out;
  }

  /// 章节取图：返回图片地址列表（**先等"地址真的出现"**，再按书源 JS 段 → 直读属性两路取）。
  Future<List<String>> chapterImages(String chapterUrl) async {
    await _open(chapterUrl, what: '章节页');

    final css = _imageCss();
    if (css == null) {
      throw ComicProbeException(
        '书源的 content 规则里找不到图片选择器（getElements(...)）：'
        '「${source.contentRules['content'] ?? '(空)'}」',
      );
    }
    final waited = await _waitForImageUrls(css);
    final urls = <String>[];

    // ① 书源的 JS 段（它自己写错也算一条路，不拖死整步）。
    final jsBody = source.contentRules['content'] ?? '';
    if (isComicJsRule(jsBody)) {
      try {
        final raw = await target.evalRaw(
          buildComicJsBlockScript(comicJsBody(jsBody)),
        );
        urls.addAll(_imageUrlsFromJsText(comicJsSegmentText(raw)));
      } on ComicProbeException {
        // 忽略：下面还有属性直读那条路
      }
    }
    // ② 直读元素属性（data-src 优先，再 src）。
    if (urls.isEmpty) urls.addAll(waited);
    if (urls.isEmpty) {
      throw ComicProbeException(
        waited.isEmpty
            ? '等了 ${waitTimeout.inSeconds} 秒，$css 一个图地址都没有'
            : '取不到图片地址（$css）',
      );
    }
    return urls.map(source.absolute).toList();
  }

  // ── 内部 ──────────────────────────────────────────────────────

  static String? _at(List<String> list, int i) {
    if (i >= list.length) return null;
    final v = list[i].trim();
    return v.isEmpty ? null : v;
  }

  static String? _firstNonNull(List<String> list) {
    for (final v in list) {
      final t = v.trim();
      if (t.isNotEmpty) return t;
    }
    return null;
  }

  /// 打开地址：主站优先、失败按 `mirrors` 换镜像、每个地址最多试 2 次；每次波折都报出来。
  Future<void> _open(String pathOrUrl, {required String what}) async {
    // 每个地址**只试一轮**：镜像回退在自检里值得（要把每种错都试出来），
    // 但在浏览/阅读里会把"等一次 20 秒"乘成好几分钟 —— 用户看到的就是"一直转圈"。
    final nav = await openComicWithFallback(
      target,
      source,
      pathOrUrl,
      headers: _headers(),
      attemptsPerHost: 1,
    ).timeout(
      openTimeout,
      onTimeout: () => const ComicNavOutcome(ok: false),
    );
    if (!nav.ok) {
      throw ComicProbeException(
        nav.attempts.isEmpty
            ? '$what打开超时（等了 ${openTimeout.inSeconds} 秒还没出结果，站点这一侧可能不可达）'
            : comicNavFailureNote(nav, what),
      );
    }
  }

  /// 请求头：书源的 header 是 JS 规则，这里不为其引入 JS 求值器（只保证中文站点能正常回）。
  Map<String, String> _headers() =>
      const {'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8'};

  Future<List<String>> _values(String rule) async {
    if (rule.trim().isEmpty) return const [];
    if (isComicJsRule(rule)) {
      final raw = await target.evalRaw(
        buildComicJsBlockScript(comicJsBody(rule)),
      );
      return _imageUrlsFromJsText(comicJsSegmentText(raw));
    }
    final raw = await target.evalRaw(buildComicRuleScript(rule));
    return comicValuesFromResult(raw);
  }

  Future<List<String>> _perElement(String cardRule, String fieldRule) async {
    if (cardRule.trim().isEmpty || fieldRule.trim().isEmpty) return const [];
    final raw = await target.evalRaw(
      buildComicPerElementValuesScript(cardRule, fieldRule),
    );
    return comicValuesFromResult(raw);
  }

  /// 书源 content 规则里的图片选择器（`getElements('…')` 的第一段取出来转成 CSS）。
  String? _imageCss() {
    final m = RegExp(
      """getElements\\(\\s*['"]([^'"]+)['"]\\s*\\)""",
    ).firstMatch(source.contentRules['content'] ?? '');
    if (m == null) return null;
    return cssFromComicRule(m.group(1)!) ?? m.group(1)!;
  }

  /// 等到"真的有图地址"为止（元素出现 ≠ 地址出现：AMP 是懒加载），
  /// 返回地址列表（data-src 优先，再 src）；等不到就是空表，由调用方如实说明。
  Future<List<String>> _waitForImageUrls(String css) async {
    final sw = Stopwatch()..start();
    while (sw.elapsed < waitTimeout) {
      final data = await _urlsOf(css, 'data-src');
      if (data.isNotEmpty) return data;
      final plain = await _urlsOf(css, 'src');
      if (plain.isNotEmpty) return plain;
      await Future<void>.delayed(pollInterval);
    }
    return const [];
  }

  /// 等到某个 CSS **至少命中一个**为止（列表是渲染出来的，早查只会得到 0/1 条）。
  Future<int> _waitForCount(String css, Duration timeout) async {
    final sw = Stopwatch()..start();
    var count = 0;
    while (sw.elapsed < timeout) {
      try {
        final raw = await target.evalRaw(buildComicCountScript(css));
        final v = parseComicJsValue(raw);
        count = v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
      } catch (_) {
        count = 0;
      }
      if (count > 0) return count;
      await Future<void>.delayed(pollInterval);
    }
    return count;
  }

  Future<List<String>> _urlsOf(String css, String attr) async {
    try {
      final raw = await target.evalRaw(buildComicAttrsScript(css, attr));
      return comicAttrList(raw).map((u) => u.trim()).where((u) => u.isNotEmpty).toList();
    } catch (_) {
      return const []; // 拿不到就当没有；上层的"取不到地址"说明会如实报出来
    }
  }
}

/// 从 HTML 文本里抠出所有 `src="…"`（书源 JS 段拼出来的 `<img>` 串）。
List<String> _imageUrlsFromJsText(String text) {
  final out = <String>[];
  for (final m in RegExp(r'''src\s*=\s*["']([^"']+)["']''').allMatches(text)) {
    final u = m.group(1)!.trim();
    if (u.isNotEmpty) out.add(u);
  }
  return out;
}
