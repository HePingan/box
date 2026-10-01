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
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'comic_chapter_api.dart';
import 'comic_fetcher.dart';
import 'comic_html_engine.dart';
import 'comic_json_rules.dart';
import 'comic_relay.dart';
import 'comic_source_engine.dart';
import 'comic_source_diagnostics.dart' show ComicNavOutcome;

/// 分类浏览里的一个分类（书源的 exploreUrl 是 JS 生成的一整张列表）。
class ComicCategory {
  const ComicCategory({required this.title, required this.url});

  final String title;

  /// 第 1 页的地址（`{{page}}` 已经填成 1）。
  ///
  /// 后面翻页**不用自己算页码**：接口的响应里带 `next`（下一页地址），用它更准
  /// （人家下一页会多带 `state`/`filter` 之类的参数，自己拼会漏）。
  final String url;
}

/// 分类一页的结果：这一页的书 + 下一页地址（接口给的；没有就是到底了）。
class ComicExplorePage {
  const ComicExplorePage({required this.hits, this.nextUrl});

  final List<ComicSearchHit> hits;

  /// 接口给的下一页地址（我这边读响应里的 `next`，Legado 没这个口径）。
  final String? nextUrl;
}

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
    this.relay,
    this.directClient,
    this.waitTimeout = const Duration(seconds: 15),
    this.listTimeout = const Duration(seconds: 12),
    this.openTimeout = const Duration(seconds: 20),
    this.pollInterval = const Duration(milliseconds: 250),
  });

  final ComicSourceTarget target;
  final ComicSource source;

  /// 中转（**退路**：手机那条网真到不了站点时才走它）。非 null 时不再需要 WebView：
  /// 取 HTML、搜索、详情、分类、章节取图全经自己的服务器。
  final ComicRelay? relay;

  /// 直连用的 HTTP 客户端（测试注入；为空就自己建一个）。
  final http.Client? directClient;

  ComicFetcher? _direct;

  /// 这次取数**走哪条**：配了中转就走中转，否则**直连站点**（默认那条）。
  ///
  /// 直连不是"降级"：手机本来就能打开站点（站点挑的是客户端特征，直连会带手机 UA，
  /// 见 comic_fetcher.dart）。源没配 relay 时返回 null —— 那是完全另一条老路（WebView 渲染）。
  ComicFetcher? get _fetcher =>
      relay ??
      (source.hasRelay
          ? _direct ??= ComicDirectFetcher(client: directClient)
          : null);

  /// 取**这个地址**要带的请求头（图片缓存与封面用）：中转地址带令牌、图床地址带手机 UA；
  /// 没有取数器（老路 WebView 渲染那类源）就是空表。
  Map<String, String> headersFor(String url) =>
      _fetcher?.headersFor(url) ?? const <String, String>{};

  /// 关掉取数器（页面销毁时调，别把连接池漏在那儿）。
  void close() {
    relay?.close();
    _direct?.close();
    _direct = null;
  }

  /// 等**图片地址**出现的上限。
  final Duration waitTimeout;

  /// 等**列表**（搜索结果 / 章节目录）出现的上限。
  final Duration listTimeout;

  /// 打开页面这一跳的上限（含镜像候选）。
  final Duration openTimeout;

  final Duration pollInterval;

  /// 上一次取数**走的是哪条路**（快路 = 取 HTML 文本解析 / 老路 = 打开页面渲染）。
  /// 界面与自检可以据此说清楚"为什么慢"。
  String lastPath = '';

  /// 快路没走通时的原因（为空表示快路成功或没试）。
  String? lastPathNote;

  /// 搜索：返回书列表（书名/作者/封面/书链）。
  Future<List<ComicSearchHit>> search(String key) async {
    final url = source.searchUrlFor(key);
    if (url == null) {
      throw ComicProbeException('这个书源没给搜索地址（searchUrl 为空），没法搜');
    }
    final card = source.searchRules['bookList'] ?? '';
    if (card.trim().isEmpty) {
      throw ComicProbeException('书源没给 bookList 规则，取不到卡片');
    }

    // 快路：数据本来就在 HTML 里 → 取文本直接解析（不用打开页面、不用等渲染）
    try {
      await _ensureOnSite();
    } on ComicProbeException catch (e) {
      // 连站点都进不去：按"搜索页打不开"报，并把每条尝试带上
      throw ComicProbeException('搜索页打不开：$e');
    }
    final html = await _tryHtml(url);
    if (html != null) {
      final hits = _buildHits(
        names: comicHtmlPerElement(parseComicHtml(html), card, source.searchRules['name'] ?? ''),
        links: comicHtmlPerElement(parseComicHtml(html), card, source.searchRules['bookUrl'] ?? ''),
        covers: comicHtmlPerElement(parseComicHtml(html), card, source.searchRules['coverUrl'] ?? ''),
        authors: comicHtmlPerElement(parseComicHtml(html), card, source.searchRules['author'] ?? ''),
      );
      if (hits.isNotEmpty) {
        lastPath = _fastPathLabel;
        return hits;
      }
      lastPathNote = '${lastPathNote ?? ''}取到的 HTML 里没解析出卡片'.trim();
    }

    // 老路：打开页面、等渲染、在 DOM 里查
    lastPath = '老路（打开页面渲染后取）';
    await _open(url, what: '搜索页');
    await _waitForCount(card, listTimeout);
    final hits = _buildHits(
      names: await _perElement(card, source.searchRules['name'] ?? ''),
      links: await _perElement(card, source.searchRules['bookUrl'] ?? ''),
      covers: await _perElement(card, source.searchRules['coverUrl'] ?? ''),
      authors: await _perElement(card, source.searchRules['author'] ?? ''),
    );
    if (hits.isEmpty) {
      throw ComicProbeException('卡片取到了，但书链一条都没取到（站点可能改版）');
    }
    return hits;
  }

  /// 把四条字段拼成结果（快路与老路共用一份，避免两处各自演化）。
  ///
  /// 按序号配对：**共 1 条时对不齐的数据宁可丢掉，也不张冠李戴**。
  List<ComicSearchHit> _buildHits({
    required List<String> names,
    required List<String> links,
    required List<String> covers,
    required List<String> authors,
  }) {
    final out = <ComicSearchHit>[];
    for (var i = 0; i < links.length; i++) {
      final link = links[i].trim();
      if (link.isEmpty) continue;
      out.add(
        ComicSearchHit(
          name: _at(names, i) ?? '（无书名）',
          bookUrl: source.absolute(link),
          author: _at(authors, i),
          cover: _absoluteOrNull(_at(covers, i)),
        ),
      );
    }
    return out;
  }

  /// 相对地址补成绝对；空/ null 就给 null（不拼半个地址）。
  String? _absoluteOrNull(String? raw) {
    final v = raw?.trim() ?? '';
    return v.isEmpty ? null : source.absolute(v);
  }

  /// 把 WebView 停在站点上（快路要**同域**发请求才带站点 cookie；机房 IP 直连是 403）。
  ///
  /// 走中转时**直接返回**：请求是服务器替我们发的，跟这台手机的 WebView 在哪没关系
  /// —— 那时候硬去"停在站点上"只会白等一轮（直连那条才需要停在站点上）。
  Future<void> _ensureOnSite() async {
    if (relay != null) return;
    final cur = await target.currentUrl();
    final hosts = comicMirrorCandidates(source, source.baseUrl);
    if (hosts.any((h) => cur.startsWith(h))) return;
    await _open(source.baseUrl, what: '站点首页');
  }

  /// 取一个地址的 HTML 文本；取不到就返回 null 并把原因记在 [lastPathNote]。
  ///
  /// 走中转时**不返回 null**：没有 WebView 那条路可退，取不到就如实抛出
  /// （悄悄换一条走不通的路，用户只会看到"一直转圈"，查不出是谁的问题）。
  Future<String?> _tryHtml(String url) async {
    final r = relay;
    if (r != null) {
      final body = await r.getText(url);
      if (body.trim().isEmpty) {
        throw ComicProbeException('中转取回来的 HTML 是空的（$url）');
      }
      if (!body.trimLeft().startsWith('<')) {
        throw ComicProbeException('中转取回来的不是网页（开头：${_head(body)}）');
      }
      lastPathNote = null;
      return body;
    }
    try {
      final body = await target.fetchInPage(url, headers: _headers(), timeout: openTimeout);
      if (body.trim().isEmpty) {
        lastPathNote = '取回来的 HTML 是空的';
        return null;
      }
      final head = body.trimLeft();
      if (!head.startsWith('<')) {
        lastPathNote = '取回来的不是网页（开头：${_head(body)}）';
        return null;
      }
      lastPathNote = null;
      return body;
    } on ComicProbeException catch (e) {
      lastPathNote = e.message;
      return null;
    }
  }

  /// 快路的说明文案：走中转时直说是中转，别让用户以为手机自己去站点取过。
  String get _fastPathLabel => relay == null
      ? '快路（直连站点取 HTML 解析）'
      : '中转（经自己的服务器取 HTML）';

  /// 接口取文本（分类榜单这类 JSON 接口）：走中转时不碰 WebView。
  Future<String> _fetchText(String url) async {
    final r = relay;
    if (r != null) return r.getText(url);
    return target.fetchInPage(url, headers: _headers());
  }

  /// 分类列表：跑源里 `exploreUrl` 的 JS（必须在**站点自己的页面**上跑）。
  ///
  /// 两种写法各有各的路：
  ///   * 纯文本（`名称::地址` 每行一条）—— 直接就是清单，不用跑 JS、不用打开页面；
  ///   * `<js>` —— 必须打开站点页面在页面里跑（挑战/站点 JS 都在那个环境里）。
  Future<List<ComicCategory>> categories() async {
    final plain = source.plainExplore;
    if (plain != null) {
      if (plain.isEmpty) {
        throw ComicProbeException('书源的分类清单是空的（exploreUrl 里没有一条 `名称::地址`）');
      }
      return plain
          .map(
            (e) => ComicCategory(
              title: e.title,
              url: e.url.replaceAll('{{page}}', '1'),
            ),
          )
          .toList();
    }
    final rule = source.exploreUrl ?? '';
    if (rule.trim().isEmpty) {
      // 说清是"没配"，别让用户以为站点坏了（他的下一步是搜索，不是修源）。
      throw ComicProbeException('这份书源没配分类浏览（exploreUrl 空着）—— 直接用搜索就行');
    }
    if (!isComicJsRule(rule)) {
      throw ComicProbeException('分类清单格式看不懂（exploreUrl 既不是 `<js>`，也不是每行 `名称::地址`）');
    }
    // 中转模式下不打开站点页面：JS 段仍需页面环境，这里的 WebView 只当"JS 求值器"用，
    // 取数本身走中转（直连那条才需要先停在站点上）。
    if (relay == null) {
      await _open(source.baseUrl, what: '站点首页');
    }
    final raw = await target.evalRaw(buildComicJsBlockScript(comicJsBody(rule)));
    final v = parseComicJsValue(raw);
    final text = v is Map ? (v['text']?.toString() ?? '') : (v?.toString() ?? '');
    if (text.trim().isEmpty) {
      throw ComicProbeException('书源的分类列表没跑出结果（exploreUrl 的 JS 段）');
    }
    final Object? data;
    try {
      data = jsonDecode(text);
    } catch (_) {
      throw ComicProbeException('分类列表不是 JSON（拿到的是：${_head(text)}）');
    }
    if (data is! List) {
      throw ComicProbeException('分类列表不是数组（实际是 ${data.runtimeType}）');
    }
    final out = <ComicCategory>[];
    for (final e in data) {
      if (e is! Map) continue;
      final title = e['title']?.toString().trim() ?? '';
      final url = e['url']?.toString().trim() ?? '';
      if (title.isEmpty || url.isEmpty) continue;
      out.add(ComicCategory(title: title, url: url.replaceAll('{{page}}', '1')));
    }
    if (out.isEmpty) throw ComicProbeException('分类列表是空的（exploreUrl 跑出来没有分类）');
    return out;
  }

  /// 按分类取书。
  ///
  /// 两条路（看 `ruleExplore.bookList` 的写法）：
  ///   * `$.items[*]` → 接口返回 JSON（榜单类站点）；
  ///   * `class.xxx` → **分类页本身是网页**，跟搜索页是同一套卡片，走页面解析这条
  ///     （2026-10-01 补：野蛮漫画的分类页就是这种，之前只认 JSON，界面上一直显示
  ///     "分类浏览不可用"）。
  Future<ComicExplorePage> explore(String url) async {
    final rules = source.exploreRules;
    final listRule = rules['bookList'] ?? '';
    if (listRule.trim().isEmpty) {
      throw ComicProbeException('这份书源没给分类取数规则（ruleExplore.bookList）');
    }
    if (!listRule.trim().startsWith(r'$')) {
      return _exploreHtml(url, rules);
    }
    // 必须在站点自己的页面上发请求：页面里发才带着站点发的 cookie（机房 IP 直连是 403）。
    // 走中转时由服务器代发，不用碰 WebView。
    if (relay == null) {
      await _open(source.baseUrl, what: '站点首页');
    }
    final body = await _fetchText(url);
    final Object? data;
    try {
      data = jsonDecode(body);
    } catch (_) {
      throw ComicProbeException('接口没返回 JSON（可能被站点拦了；开头：${_head(body)}）');
    }
    final items = comicJsonList(data, listRule);
    final out = <ComicSearchHit>[];
    for (final item in items) {
      if (item is! Map) continue;
      final name = _ruleText(item, rules['name']);
      final link = _ruleText(item, rules['bookUrl']);
      if (link.isEmpty) continue; // 没有书链的条目留着没用（点进去无从可去）
      out.add(
        ComicSearchHit(
          name: name.isEmpty ? '（无书名）' : name,
          bookUrl: source.absolute(link),
          author: _optionalRuleText(item, rules['author']),
          cover: _coverOf(item, rules['coverUrl']),
        ),
      );
    }
    if (out.isEmpty) throw ComicProbeException('这一页没取到任何书（站点可能改版）');
    return ComicExplorePage(hits: out, nextUrl: _nextUrlOf(data));
  }

  /// HTML 写法的分类页：跟搜索页同一套卡片规则，走同一条路（先取 HTML 直接解析，
  /// 解析不出卡片再打开页面渲染后取 DOM）。
  ///
  /// 为什么要专门有一条：站点之间的差别不在"分类"这个概念，而在**这张列表是网页还是
  /// 接口**。只认 JSON 的话，网页式分类页永远显示"分类浏览不可用"（用户看到的正是这句）。
  Future<ComicExplorePage> _exploreHtml(
    String url,
    Map<String, String> rules,
  ) async {
    final card = rules['bookList']!;
    try {
      await _ensureOnSite();
    } on ComicProbeException catch (e) {
      throw ComicProbeException('分类页打不开：$e');
    }
    final html = await _tryHtml(url);
    if (html != null) {
      final doc = parseComicHtml(html);
      final hits = _buildHits(
        names: comicHtmlPerElement(doc, card, rules['name'] ?? ''),
        links: comicHtmlPerElement(doc, card, rules['bookUrl'] ?? ''),
        covers: comicHtmlPerElement(doc, card, rules['coverUrl'] ?? ''),
        authors: comicHtmlPerElement(doc, card, rules['author'] ?? ''),
      );
      if (hits.isNotEmpty) {
        lastPath = _fastPathLabel;
        return ComicExplorePage(hits: hits, nextUrl: _nextListPage(url));
      }
      lastPathNote = '${lastPathNote ?? ''}取到的 HTML 里没解析出卡片'.trim();
    }

    lastPath = '老路（打开页面渲染后取）';
    await _open(url, what: '分类页');
    await _waitForCount(card, listTimeout);
    final hits = _buildHits(
      names: await _perElement(card, rules['name'] ?? ''),
      links: await _perElement(card, rules['bookUrl'] ?? ''),
      covers: await _perElement(card, rules['coverUrl'] ?? ''),
      authors: await _perElement(card, rules['author'] ?? ''),
    );
    if (hits.isEmpty) {
      throw ComicProbeException('分类页的卡片取到了，但书链一条都没取到（站点可能改版；也可能是这一类翻到底了）');
    }
    return ComicExplorePage(hits: hits, nextUrl: _nextListPage(url));
  }

  /// 纯文本清单（`名称::地址`）里这一页的**下一页**地址。
  ///
  /// 为什么从清单反推：`explore(url)` 只拿到一个具体地址，各家分页写法不同
  /// （`.../3/1.html`、`?page=1`），只有清单里的 `{{page}}` 是唯一定义 —— 把当前
  /// 地址扣回模板、取中间那截数字、加一，就对得上。
  String? _nextListPage(String url) {
    final plain = source.plainExplore;
    if (plain == null) return null;
    for (final e in plain) {
      if (!e.url.contains('{{page}}')) continue;
      final parts = e.url.split('{{page}}');
      if (parts.length != 2) continue; // 多个占位符：不猜
      final head = parts[0];
      final tail = parts[1];
      if (!url.startsWith(head) || !url.endsWith(tail)) continue;
      final mid = url.substring(head.length, url.length - tail.length);
      final n = int.tryParse(mid);
      if (n == null) continue;
      return '$head${n + 1}$tail';
    }
    return null;
  }

  /// 响应里的下一页地址（没有 / 不是字符串 → null，界面就不显示「加载更多」）。
  String? _nextUrlOf(Object? data) {
    if (data is! Map) return null;
    final n = data['next'];
    if (n is! String || n.trim().isEmpty) return null;
    return n.trim();
  }

  /// 按 JSON 规则取一条记录的字段；规则缺失时返回空串（由调用方决定要不要报错）。
  String _ruleText(Object? item, String? rule) {
    if (rule == null || rule.trim().isEmpty) return '';
    final r = rule.trim();
    try {
      return r.contains('{{') ? comicTemplate(r, item) : comicJsonFieldText(item, r);
    } on ComicJsonMissingField {
      // 这条记录没有这个字段（作者/封面常常没有）—— 空着，但**不报错、不编造**。
      return '';
    } on ComicJsonRuleException catch (e) {
      // 规则写法本身有问题才算错（配置错要能看出来）。
      throw ComicProbeException('分类规则没取到：$e');
    }
  }

  /// 封面可能给的是相对地址或模板，都要补成完整地址。
  String? _coverOf(Object? item, String? rule) {
    final c = _ruleText(item, rule);
    return c.isEmpty ? null : source.absolute(c);
  }

  String? _optionalRuleText(Object? item, String? rule) {
    final t = _ruleText(item, rule);
    return t.isEmpty ? null : t;
  }

  String _head(String s) {
    final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
    return t.length <= 120 ? t : '${t.substring(0, 120)}…';
  }

  /// 详情 + 章节目录。
  Future<ComicBookDetail> bookInfo(String bookUrl) async {
    // 快路：详情页的数据本来就在 HTML 里（真页面实测：目录 1212 处在 HTML 里）
    try {
      await _ensureOnSite();
    } on ComicProbeException catch (e) {
      throw ComicProbeException('详情页打不开：$e');
    }
    final html = await _tryHtml(bookUrl);
    if (html != null) {
      final doc = parseComicHtml(html);
      final detail = _detailFromRules(
        bookUrl: bookUrl,
        name: comicHtmlExtract(doc, source.bookInfoRules['name'] ?? '').firstOrNull,
        author: comicHtmlExtract(doc, source.bookInfoRules['author'] ?? '').firstOrNull,
        cover: comicHtmlExtract(doc, source.bookInfoRules['coverUrl'] ?? '').firstOrNull,
        intro: comicHtmlExtract(doc, source.bookInfoRules['intro'] ?? '').firstOrNull,
        chapters: _chapterRefsFromRules(
          titles: comicHtmlPerElement(
            doc,
            _tocContainerRule(),
            source.tocRules['chapterName'] ?? '',
          ),
          urls: comicHtmlPerElement(
            doc,
            _tocContainerRule(),
            source.tocRules['chapterUrl'] ?? '',
          ),
        ),
      );
      if (detail.name.isNotEmpty && detail.chapters.isNotEmpty) {
        lastPath = _fastPathLabel;
        return detail;
      }
      lastPathNote = '${lastPathNote ?? ''}快路没解析出书名/目录'.trim();
    }

    // 老路：打开页面、等渲染、在 DOM 里查
    lastPath = '老路（打开页面渲染后取）';
    await _open(bookUrl, what: '详情页');
    return _detailFromRules(
      bookUrl: bookUrl,
      name: _firstNonNull(await _values(source.bookInfoRules['name'] ?? '')),
      author: _firstNonNull(await _values(source.bookInfoRules['author'] ?? '')),
      cover: _firstNonNull(await _values(source.bookInfoRules['coverUrl'] ?? '')),
      intro: _firstNonNull(await _values(source.bookInfoRules['intro'] ?? '')),
      chapters: await _chapters(),
    );
  }

  /// 目录容器规则：取 `tocUrl` 的**第一段选择器原文**（整条里有书源自己写的笔误段 `harf`）。
  String _tocContainerRule() {
    final tocRule = source.bookInfoRules['tocUrl'] ?? '';
    final rule = firstSelectorRule(tocRule) ?? firstSelectorCss(tocRule) ?? cssFromComicRule(tocRule) ?? '';
    if (rule.isEmpty) {
      throw ComicProbeException('书源的 tocUrl 规则不认识：「$tocRule」');
    }
    return rule;
  }

  /// 把各字段拼成详情（快路与老路共用一份，避免两处各自演化）。
  ComicBookDetail _detailFromRules({
    required String bookUrl,
    String? name,
    String? author,
    String? cover,
    String? intro,
    required List<ComicChapterRef> chapters,
  }) {
    final n = name?.trim() ?? '';
    return ComicBookDetail(
      bookUrl: bookUrl,
      name: n.isEmpty ? '（无书名）' : n,
      author: _nonEmpty(author),
      cover: _absoluteOrNull(cover),
      intro: _nonEmpty(intro),
      chapters: chapters,
    );
  }

  /// 目录标题 + 链接按序号配对（**没有链接的那条丢掉**，不张冠李戴）。
  List<ComicChapterRef> _chapterRefsFromRules({
    required List<String> titles,
    required List<String> urls,
  }) {
    final out = <ComicChapterRef>[];
    for (var i = 0; i < urls.length; i++) {
      final u = urls[i].trim();
      if (u.isEmpty) continue;
      out.add(
        ComicChapterRef(
          title: _at(titles, i) ?? '第 ${i + 1} 话',
          url: source.absolute(u),
        ),
      );
    }
    return out;
  }

  String? _nonEmpty(String? raw) {
    final v = raw?.trim() ?? '';
    return v.isEmpty ? null : v;
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
    return _chapterRefsFromRules(titles: titles, urls: urls);
  }

  /// 章节取图：返回图片地址列表。
  ///
  /// [onPartial]：接口型源**每取到一批**就回调一次当前全部地址 —— 阅读页靠它先把
  /// 前几张显示出来。整话 209 张要 21 次往返，全取完才显示的话用户看到的就是
  /// "一直转圈"（2026-10-01 用户报的）。
  ///
  /// 两条互不相干的路：
  ///   * **取图接口**（源带 `relay` 段 = 图不在 HTML 里）：先取章节页拿到
  ///     `aid/cid/picCount`，再用站点的取图接口分批取。**默认直连**（手机能到站点），
  ///     配了设备令牌才经自己的服务器；两条走法共用同一套分批逻辑（[ComicFetcher]）。
  ///     这一路失败**如实报错**，不悄悄退回"打开页面"那条 —— HTML 里根本没有图地址，
  ///     退了只会白等一轮；
  ///   * 老路：打开章节页、等图片地址真的出现，再按书源 JS 段 → 直读属性两路取。
  Future<List<String>> chapterImages(
    String chapterUrl, {
    void Function(List<String> urls)? onPartial,
  }) async {
    final fetcher = _fetcher;
    if (fetcher != null) {
      final picsPath = source.relay?.picsPath;
      if (picsPath == null) {
        throw ComicProbeException(
          '这份书源没配取图接口（relay.chapterApi.pics）—— 取不到图',
        );
      }
      return _chapterImagesViaApi(chapterUrl, fetcher, picsPath, onPartial);
    }
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

  /// 取一话的图：章节页拿 `aid/cid` → 取图接口按 offset 分批 → 地址交给取数器
  /// （中转会包成中转地址；直连原样返回，图片由图片缓存带着手机 UA 去取）。
  ///
  /// 分批那套逻辑在 `comic_chapter_api.dart` 里 —— 自检页的「章节取图」跑的是**同一份**
  /// （以前只有这里实现，自检页对接口型源会误报「找不到图片选择器」）。
  ///
  /// [onPartial] 逐批回调（先显示前几张，不必等整话取完）。
  Future<List<String>> _chapterImagesViaApi(
    String chapterUrl,
    ComicFetcher fetcher,
    String picsPath,
    void Function(List<String> urls)? onPartial,
  ) async {
    lastPath = relay == null ? '直连（章节取图接口）' : '中转（章节取图接口）';
    return fetchComicChapterPicsViaApi(
      fetcher: fetcher,
      source: source,
      chapterUrl: chapterUrl,
      picsPath: picsPath,
      onImages: onPartial,
    );
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
