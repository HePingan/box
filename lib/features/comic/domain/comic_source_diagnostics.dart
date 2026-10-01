// 漫画源自检：用真手机上的 WebView 把「搜索 → 详情 → 章节取图 → 真下一张图」跑一遍，
// 逐项给结论。
//
// 为什么值得单独做这一步：站点有 WAF（JS 挑战），而章节页在我们两台服务器上都是
// 502 —— **只有手机上能问出真相**。所以本文件的价值是"把未知变已知"，而不是"能看漫画"。
//
// 纪律：
//   * 每一失败都要有原因（超时 / HTTP 状态 / 选择器 0 命中 / 规则不认识）；
//   * 页面标题与最终地址一律记下来 —— 502 这种错误光看"命中 0"是看不出来的；
//   * 单元测试用假目标（不联网、不起 WebView），真机行为由界面上的一次真跑证明。
library;

import 'dart:async';

import 'comic_chapter_api.dart';
import 'comic_fetcher.dart';
import 'comic_html_engine.dart';
import 'comic_image_cache.dart';
import 'comic_source.dart';
import 'comic_source_engine.dart';

/// 取数目标：真机 = WebView；单测 = 假实现。
///
/// 所有方法都要求"出错就抛"，不要吞成空 —— 自检的全部意义就是把原因说出来。
abstract class ComicSourceTarget {
  /// 打开地址并等页面加载完成。
  Future<void> open(String url, {Map<String, String>? headers});

  /// 当前地址（页面可能跳转，比如章节页会跳到镜像域名）。
  Future<String> currentUrl();

  /// 页面标题（502 这类错误只体现在标题/正文里）。
  Future<String> pageTitle();

  /// 某个 CSS 当前命中几个元素。
  Future<int> countOf(String css);

  /// 在页面里跑一段 JS，返回字符串结果。
  Future<String> evalRaw(String script);

  /// 取某个 CSS 命中的第一个元素的属性值（页面查询，不走书源规则）。
  Future<String?> attrOf(String css, String attr);

  /// 取某个 CSS 命中的**所有**元素的属性值（空值丢掉）。
  Future<List<String>> attrsOf(String css, String attr);

  /// 取第一个命中元素的 HTML 片段（失败诊断用；取不到就 null）。
  Future<String?> sampleHtml(String css);

  /// 在**页面里**发一个 GET，把响应体当文本返回（用于 JSON 接口类规则）。
  ///
  /// 默认实现：如实说"这个目标不支持"—— 别静默返回空串（那会变成"接口没数据"的假结论）。
  /// 真机目标（WebView）覆盖实现；自检流程用不到它，所以自检的假目标不必实现。
  Future<String> fetchInPage(
    String url, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 15),
  }) async {
    throw ComicProbeException('这个取数目标不支持在页面里发请求（$url）');
  }

  /// 上一次打开时**主文档**的加载错误（子资源错误不算；没有就 null）。
  ComicLoadFailure? get lastLoadError;
}

/// 主文档加载失败的信息（子资源失败不在这里）。
class ComicLoadFailure {
  const ComicLoadFailure({required this.code, required this.description});

  final int? code;
  final String description;
}

/// 自检的一步。
class ComicProbeStep {
  const ComicProbeStep({
    required this.name,
    required this.ok,
    required this.elapsedMs,
    required this.note,
    this.samples = const [],
    this.finalUrl,
    this.pageTitle,
  });

  final String name;
  final bool ok;
  final int elapsedMs;
  final String note;

  /// 取到的样例（书名 / 章节名 / 图片地址前几条）。
  final List<String> samples;
  final String? finalUrl;
  final String? pageTitle;

  ComicProbeStep copyWith({bool? ok, String? note, List<String>? samples}) =>
      ComicProbeStep(
        name: name,
        ok: ok ?? this.ok,
        elapsedMs: elapsedMs,
        note: note ?? this.note,
        samples: samples ?? this.samples,
        finalUrl: finalUrl,
        pageTitle: pageTitle,
      );
}

/// 自检结论。
class ComicProbeReport {
  const ComicProbeReport({
    required this.sourceName,
    required this.steps,
    this.firstBookUrl,
    this.firstChapterUrl,
    this.firstImageUrl,
    this.tocCount,
    this.totalMs = 0,
  });

  final String sourceName;
  final List<ComicProbeStep> steps;

  /// 打通后能直接用来展示的东西。
  final String? firstBookUrl;
  final String? firstChapterUrl;
  final String? firstImageUrl;
  final int? tocCount;
  final int totalMs;

  bool get allOk => steps.isNotEmpty && steps.every((s) => s.ok);
  int get okCount => steps.where((s) => s.ok).length;
}

/// 自检里"等到选择器出现"的默认节奏：WAF 挑战本身要几秒，页面渲染也要时间。
const Duration kComicProbeWaitTimeout = Duration(seconds: 25);
const Duration kComicProbePollInterval = Duration(milliseconds: 400);

/// 自检第 4 步的"真下一张图"：返回图片字节数，失败就抛（由调用方如实写进结论）。
///
/// 为什么要有这一步（2026-10-01 用户报「封面图加载不出来 + 取第一页一直转圈」）：
/// 前三步只证明**能列出图地址**，证明不了**图能下下来** —— 而这两个是两回事：书源全对、
/// 图床在这台手机的网上取不到，界面上就是"封面一直转圈、阅读页一直转圈"。
/// 自检的价值是"这一步过了 App 就能用"，那就不能停在"地址列出来了"。
typedef ComicImageDownloader = Future<int> Function(String url);

/// 真机用的实现：走图片缓存那条路（带手机 UA、同一套超时规则），返回字节数。
Future<int> downloadComicImageForProbe(String url) async {
  final cache = ComicImageCache(headerFor: (u) => comicDirectHeaders());
  final file = await cache.fetch(url);
  return file.length();
}

/// 快路（取 HTML 文本 + 规则引擎）跑出来的一次结果。
///
/// 为什么要单独记 [note]：自检的价值是把未知变已知，**快路为什么没通**本身就是一条
/// 结论（站点不给 HTML / 规则解析不出卡片 / 取回来的不是网页），不能只留个 false。
class _FastPathResult {
  const _FastPathResult({
    this.ok = false,
    required this.note,
    this.firstBookUrl,
    this.firstChapterUrl,
    this.tocCount,
    this.samples = const <String>[],
  });

  final bool ok;
  final String note;
  final String? firstBookUrl;
  final String? firstChapterUrl;
  final int? tocCount;
  final List<String> samples;
}

/// 取一个地址的 HTML 文本（判断口径与 `ComicOnlineService._tryHtml` 一致：
/// 空的 / 开头不是 `<` 的一律算"没取到"）。
///
/// 走的是**页面内取文本**（与 App 快路同一个入口），所以带着站点的 cookie，
/// 不是在 App 侧另发一个裸 HTTP 请求 —— 后者会得出与 App 不一样的结论。
Future<String?> _fetchHtmlText(
  ComicSourceTarget target,
  String url, {
  required Map<String, String> headers,
  required Duration timeout,
}) async {
  try {
    final body = await target.fetchInPage(url, headers: headers, timeout: timeout);
    final text = body.trim();
    if (text.isEmpty) return null;
    if (!text.startsWith('<')) return null;
    return body;
  } on Object {
    // 取不到不算错误：这条路现在不通，退到渲染后查 DOM（原因由调用方拼进说明）。
    return null;
  }
}

/// 搜索的快路：**与 App 搜索同一条路**（取 HTML 文本 + 规则引擎解析卡片）。
Future<_FastPathResult> _searchViaHtmlFastPath({
  required ComicSourceTarget target,
  required ComicSource source,
  required String url,
  required Map<String, String> headers,
  required Duration timeout,
}) async {
  final cardRule = source.searchRules['bookList'] ?? '';
  if (cardRule.trim().isEmpty) {
    return const _FastPathResult(note: '书源没给 bookList 规则，快路无从解析');
  }
  final html = await _fetchHtmlText(target, url, headers: headers, timeout: timeout);
  if (html == null) {
    return const _FastPathResult(note: '取不到搜索页的 HTML（多为 WAF 挑战页或需要渲染）');
  }
  final doc = parseComicHtml(html);
  final names = comicHtmlPerElement(doc, cardRule, source.searchRules['name'] ?? '');
  final links = comicHtmlPerElement(doc, cardRule, source.searchRules['bookUrl'] ?? '');
  if (links.isEmpty) {
    return const _FastPathResult(note: 'HTML 里没解析出书链（规则与站点页面可能已不匹配）');
  }
  return _FastPathResult(
    ok: true,
    note: '走的是快路（取 HTML 文本 + 规则引擎）—— 与 App 搜索同一条路：'
        '书名 ${names.length} 个、书链 ${links.length} 个',
    firstBookUrl: source.absolute(links.first),
    samples: names.take(3).toList(),
  );
}

/// 详情的快路：**与 App 打开详情页同一条路**（取 HTML 文本 + 规则引擎解析书名/目录）。
Future<_FastPathResult> _detailViaHtmlFastPath({
  required ComicSourceTarget target,
  required ComicSource source,
  required String url,
  required Map<String, String> headers,
  required Duration timeout,
}) async {
  final html = await _fetchHtmlText(target, url, headers: headers, timeout: timeout);
  if (html == null) {
    return const _FastPathResult(note: '取不到详情页的 HTML（多为 WAF 挑战页或需要渲染）');
  }
  final doc = parseComicHtml(html);
  final names = comicHtmlExtract(doc, source.bookInfoRules['name'] ?? '');
  final authors = comicHtmlExtract(doc, source.bookInfoRules['author'] ?? '');
  final String container;
  try {
    container = _tocContainerRuleOf(source);
  } on ComicProbeException catch (e) {
    return _FastPathResult(note: '读不了目录规则：${e.message}');
  }
  final chapterTitles = comicHtmlPerElement(
    doc,
    container,
    source.tocRules['chapterName'] ?? '',
  );
  final chapterUrls = comicHtmlPerElement(
    doc,
    container,
    source.tocRules['chapterUrl'] ?? '',
  );
  if (names.isEmpty || chapterUrls.isEmpty) {
    return _FastPathResult(
      note: 'HTML 里没解析出${names.isEmpty ? '书名' : '章节链接'}',
    );
  }
  return _FastPathResult(
    ok: true,
    note: '走的是快路（取 HTML 文本 + 规则引擎）—— 与 App 打开详情页同一条路：'
        '书名「${names.first}」'
        '${authors.isEmpty ? '' : ' · 作者 ${authors.first}'}'
        ' · 章节 ${chapterUrls.length} 条'
        '${chapterTitles.length == chapterUrls.length ? '' : '（章节名 ${chapterTitles.length} 条）'}',
    firstChapterUrl: source.absolute(chapterUrls.first),
    tocCount: chapterUrls.length,
    samples: [
      names.first,
      if (authors.isNotEmpty) authors.first,
      '章节数 ${chapterUrls.length}',
    ],
  );
}

/// 目录容器规则：取 `tocUrl` 的第一段选择器原文（整条里含书源自己写的笔误段 `harf`）。
///
/// 与 `ComicOnlineService._tocContainerRule` 同一口径 —— 自检与 App 用同一段规则，
/// 否则"自检说目录读不到"而 App 读得到（或反过来）。
String _tocContainerRuleOf(ComicSource source) {
  final tocRule = source.bookInfoRules['tocUrl'] ?? '';
  final rule =
      firstSelectorRule(tocRule) ?? firstSelectorCss(tocRule) ?? cssFromComicRule(tocRule) ?? '';
  if (rule.isEmpty) {
    throw ComicProbeException('书源的 tocUrl 规则不认识：「$tocRule」');
  }
  return rule;
}

/// 跑一次自检。[key] 是搜索关键字。
///
/// [fetcher] 只在**接口型源**（图不在 HTML 里，如野蛮漫画）的「章节取图」那一步用到 ——
/// 那种源必须按 App 实际的路走（直连站点 + 取图接口）。不传就现造一个
/// [ComicDirectFetcher]（真机上的正常情况）；测试里注入假的即可。
Future<ComicProbeReport> runComicSourceProbe({
  required ComicSourceTarget target,
  required ComicSource source,
  String key = '海贼',
  Duration waitTimeout = kComicProbeWaitTimeout,
  Duration pollInterval = kComicProbePollInterval,
  void Function(ComicProbeStep step)? onStep,
  ComicFetcher? fetcher,
  ComicImageDownloader? imageDownloader,
}) async {
  final steps = <ComicProbeStep>[];
  final sw = Stopwatch()..start();

  String? firstBookUrl;
  String? firstChapterUrl;
  String? firstImageUrl;
  int? tocCount;

  Map<String, String> headers() {
    // 这份源的 header 是 @js: 生成的 Accept-Language；本 App 固定带上同类头即可
    // （不实现 JS 求值取头，避免为一行头引入一套求值器）。
    return const {'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8'};
  }

  // ── 第 1 步：搜索 ───────────────────────────────────────────────
  {
    final stepSw = Stopwatch()..start();
    final url = source.searchUrlFor(key);
    if (url == null) {
      final step = ComicProbeStep(
        name: '搜索',
        ok: false,
        elapsedMs: stepSw.elapsedMilliseconds,
        note: '这个书源没给搜索地址（searchUrl 为空），没法搜',
      );
      steps.add(step);
      onStep?.call(step);
    } else {
      try {
        // ① 先按 **App 实际那条路**跑一遍：取 HTML 文本 + 规则引擎（快路）。
        //    只验"渲染后查 DOM"会得出与 App 不一致的结论 —— 站点给"取文本"和给
        //    "渲染后的 DOM"的东西不保证一样，而自检的全部价值就是"这一步过了 App 就能用"。
        final fast = await _searchViaHtmlFastPath(
          target: target,
          source: source,
          url: url,
          headers: headers(),
          timeout: waitTimeout,
        );
        if (fast.ok) {
          firstBookUrl = fast.firstBookUrl;
          final step = ComicProbeStep(
            name: '搜索',
            ok: true,
            elapsedMs: stepSw.elapsedMilliseconds,
            note: fast.note,
            samples: fast.samples,
            finalUrl: url,
          );
          steps.add(step);
          onStep?.call(step);
        } else {
        // ② 快路没通：退到"打开页面、等渲染、在 DOM 里查"，并**把快路失败的原因带上**
        //    —— 这条原因本身就是结论（站点不给 HTML ≠ 站点没有这本书）。
        final fastPrefix = '快路没走通（${fast.note}）；退到渲染后查 DOM：';
        final nav = await openComicWithFallback(
          target,
          source,
          url,
          headers: headers(),
        );
        if (!nav.ok) {
          throw ComicProbeException(comicNavFailureNote(nav, '搜索页'));
        }
        final cardCss = cssFromComicRule(source.searchRules['bookList'] ?? '');
        if (cardCss == null) {
          final step = ComicProbeStep(
            name: '搜索',
            ok: false,
            elapsedMs: stepSw.elapsedMilliseconds,
            note: '书源的 bookList 规则不认识：'
                '「${source.searchRules['bookList'] ?? '(空)'}」—— 这是配置问题，不是站点问题',
            finalUrl: await _safe(() => target.currentUrl()),
          );
          steps.add(step);
          onStep?.call(step);
        } else {
        final waited = await _waitForCount(
          target,
          cardCss,
          waitTimeout: waitTimeout,
          pollInterval: pollInterval,
        );
        final title = await _safe(() => target.pageTitle());
        final finalUrl = await _safe(() => target.currentUrl());
        if (waited.count == 0) {
          final step = ComicProbeStep(
            name: '搜索',
            ok: false,
            elapsedMs: stepSw.elapsedMilliseconds,
            note: fastPrefix +
                _zeroHitNote(
                  selector: cardCss,
                  waitedSeconds: waited.seconds,
                  pageTitle: title,
                ),
            finalUrl: finalUrl,
            pageTitle: title,
          );
          steps.add(step);
          onStep?.call(step);
        } else {
          final names = await _extractValues(
            target,
            source.searchRules['name'] ?? '',
          );
          final urls = await _extractValues(
            target,
            source.searchRules['bookUrl'] ?? '',
          );
          firstBookUrl = urls.isEmpty ? null : source.absolute(urls.first);
          final step = ComicProbeStep(
            name: '搜索',
            ok: urls.isNotEmpty,
            elapsedMs: stepSw.elapsedMilliseconds,
            note: fastPrefix +
                (urls.isNotEmpty
                    ? '命中 ${waited.count} 条，取到书名 ${names.length} 个、链接 ${urls.length} 个'
                    : '卡片命中 ${waited.count} 条，但书链规则一条都没取到（站点可能改版）') +
                navSuffix(nav),
            samples: names.take(3).toList(),
            finalUrl: finalUrl,
            pageTitle: title,
          );
          steps.add(step);
          onStep?.call(step);
        }
        }
        } // else: 快路没通 → 老路
      } catch (e) {
        final step = ComicProbeStep(
          name: '搜索',
          ok: false,
          elapsedMs: stepSw.elapsedMilliseconds,
          note: e is ComicProbeException
              ? e.message
              : '打不开搜索页：${describeComicProbeError(e)}',
          finalUrl: await _safe(() => target.currentUrl()),
        );
        steps.add(step);
        onStep?.call(step);
      }
    }
  }

  // ── 第 2 步：详情 + 章节列表 ─────────────────────────────────────
  if (firstBookUrl == null) {
    const step = ComicProbeStep(
      name: '详情',
      ok: false,
      elapsedMs: 0,
      note: '上一步没拿到书链，跳过了（不是"通过"）',
    );
    steps.add(step);
    onStep?.call(step);
  } else {
    final stepSw = Stopwatch()..start();
    try {
      // ① 同样先走 App 实际那条路（取 HTML 文本 + 规则引擎解析详情与目录）。
      final fast = await _detailViaHtmlFastPath(
        target: target,
        source: source,
        url: firstBookUrl,
        headers: headers(),
        timeout: waitTimeout,
      );
      if (fast.ok) {
        firstChapterUrl = fast.firstChapterUrl;
        tocCount = fast.tocCount;
        final step = ComicProbeStep(
          name: '详情',
          ok: true,
          elapsedMs: stepSw.elapsedMilliseconds,
          note: fast.note,
          samples: fast.samples,
          finalUrl: firstBookUrl,
        );
        steps.add(step);
        onStep?.call(step);
      } else {
      final fastPrefix = '快路没走通（${fast.note}）；退到渲染后查 DOM：';
      final nav = await openComicWithFallback(
        target,
        source,
        firstBookUrl,
        headers: headers(),
      );
      if (!nav.ok) {
        throw ComicProbeException(comicNavFailureNote(nav, '详情页'));
      }
      final titleCss = cssFromComicRule(source.bookInfoRules['name'] ?? '');
      final waited = await _waitForCount(
        target,
        titleCss,
        waitTimeout: waitTimeout,
        pollInterval: pollInterval,
      );
      final pageTitle = await _safe(() => target.pageTitle());
      final finalUrl = await _safe(() => target.currentUrl());
      if (waited.count == 0) {
        final step = ComicProbeStep(
          name: '详情',
          ok: false,
          elapsedMs: stepSw.elapsedMilliseconds,
          note: fastPrefix +
              _zeroHitNote(
                selector: titleCss,
                waitedSeconds: waited.seconds,
                pageTitle: pageTitle,
              ),
          finalUrl: finalUrl,
          pageTitle: pageTitle,
        );
        steps.add(step);
        onStep?.call(step);
      } else {
        final names = await _extractValues(target, source.bookInfoRules['name'] ?? '');
        final authors = await _extractValues(
          target,
          source.bookInfoRules['author'] ?? '',
        );
        // 章节列表：书源里 tocUrl 那条规则自带笔误（@harf@），所以只取它的**容器段**
        // 直接数链接（实测 1211 章），并把这条差异如实写进说明。
        // 只用**容器那一段**：tocUrl 第 3 段 `harf` 是它自己的笔误，
        // 照整条规则拼 CSS 会拼出永远匹配不到的选择器（真机上表现为"章节 0 条"）。
        final tocCss = firstSelectorCss(source.bookInfoRules['tocUrl'] ?? '');
        final chapterCss = tocCss == null ? null : '$tocCss a[href]';
        final count = chapterCss == null
            ? 0
            : await _waitForCount(
                target,
                chapterCss,
                // 别用 8 秒这种紧值：移动网络下整页响应偶尔要十几秒
                // （实测：同一次导航重跑就是瞬时的），紧了会把"慢"误判成"没有"。
                waitTimeout: waitTimeout,
                pollInterval: pollInterval,
              ).then((w) => w.count);
        tocCount = count;
        // 章链：用 tocUrl 的选择器段 + 直接取 href（书源那条第 3 段是笔误，不照抄）。
        final firstChapter = chapterCss == null
            ? null
            : await _safe(() => target.attrOf(chapterCss, 'href'));
        firstChapterUrl =
            firstChapter == null ? null : source.absolute(firstChapter);
        final step = ComicProbeStep(
          name: '详情',
          ok: names.isNotEmpty && count > 0,
          elapsedMs: stepSw.elapsedMilliseconds,
          note: '$fastPrefix'
              '书名「${names.isEmpty ? '—' : names.first}」'
              '${authors.isEmpty ? '' : ' · 作者 ${authors.first}'}'
              ' · 章节 $count 条'
              '${count == 0 ? '（章节选择器 0 命中）' : ''}'
              '${navSuffix(nav)}',
          samples: [
            if (names.isNotEmpty) names.first,
            if (authors.isNotEmpty) authors.first,
            '章节数 $count',
          ],
          finalUrl: finalUrl,
          pageTitle: pageTitle,
        );
        steps.add(step);
        onStep?.call(step);
      }
      } // else: 快路没通 → 老路
    } catch (e) {
      // 配置错误（规则不认识）与网络错误要分开说：前者是我们自己的问题，
      // 说成"打不开页面"会把排查方向带偏。
      final step = ComicProbeStep(
        name: '详情',
        ok: false,
        elapsedMs: stepSw.elapsedMilliseconds,
        note: e is ComicProbeException
            ? e.message
            : '打不开详情页：${describeComicProbeError(e)}',
      );
      steps.add(step);
      onStep?.call(step);
    }
  }

  // ── 第 3 步：章节取图 ───────────────────────────────────────────
  final picsPath = source.relay?.picsPath;
  if (firstChapterUrl == null) {
    const step = ComicProbeStep(
      name: '章节取图',
      ok: false,
      elapsedMs: 0,
      note: '上一步没拿到章链，跳过了（不是"通过"）',
    );
    steps.add(step);
    onStep?.call(step);
  } else if (picsPath != null) {
    // 接口型源：**图不在 HTML 里**（野蛮漫画就是），网页里根本扒不出图地址。
    // 所以按 App 实际走的那条路验证：直连站点取章节页拿到 aid/cid，再打站点自己的
    // 取图接口分批取图（带手机 UA）。
    //
    // 以前这一步只会打开章节页扒 HTML，对这类源必然报「content 规则里找不到图片选择器」
    // —— 源明明是好的，看着却像坏了（2026-09-29 把野蛮漫画加进自检时才暴露）。
    final stepSw = Stopwatch()..start();
    try {
      final api = fetcher ?? ComicDirectFetcher();
      final urls = await fetchComicChapterPicsViaApi(
        fetcher: api,
        source: source,
        chapterUrl: firstChapterUrl,
        picsPath: picsPath,
      );
      firstImageUrl = urls.first;
      final step = ComicProbeStep(
        name: '章节取图',
        ok: true,
        elapsedMs: stepSw.elapsedMilliseconds,
        note: '取到 ${urls.length} 张图，首张来自 '
            '${Uri.tryParse(firstImageUrl)?.host ?? '—'}'
            '（这份源的图不在网页里，走站点自己的取图接口'
            '${source.relay!.endpoint}$picsPath，'
            '分 ${(urls.length / kComicPicBatchSize).ceil()} 批取完，直连 + 手机 UA）',
        samples: urls.take(2).toList(),
        finalUrl: firstChapterUrl,
      );
      steps.add(step);
      onStep?.call(step);
    } catch (e) {
      final step = ComicProbeStep(
        name: '章节取图',
        ok: false,
        elapsedMs: stepSw.elapsedMilliseconds,
        note: e is ComicProbeException
            ? e.message
            : '取图接口没跑通：${describeComicProbeError(e)}',
        finalUrl: firstChapterUrl,
      );
      steps.add(step);
      onStep?.call(step);
    }
  } else {
    final stepSw = Stopwatch()..start();
    try {
      final nav = await openComicWithFallback(
        target,
        source,
        firstChapterUrl,
        headers: headers(),
      );
      if (!nav.ok) {
        throw ComicProbeException(comicNavFailureNote(nav, '章节页'));
      }
      final imageRule = _imageRuleFromContentJs(source.contentRules['content'] ?? '');
      if (imageRule == null) {
        throw ComicProbeException(
          '书源的 content 规则里找不到图片选择器（getElements(...)）：'
          '「${source.contentRules['content'] ?? '(空)'}」',
        );
      }
      // 等到"真的有图地址"为止（元素出现 ≠ 地址出现；AMP 是懒加载）。
      final urlWait = await _waitForImageUrls(
        target,
        imageRule,
        waitTimeout: waitTimeout,
        pollInterval: pollInterval,
      );
      final pageTitle = await _safe(() => target.pageTitle());
      final finalUrl = await _safe(() => target.currentUrl());
      // 失败诊断用：把站点实际给的元素片段带回来（不猜）。
      final sample = await _safe(() => target.sampleHtml(imageRule));

      // 先按书源的意图跑它的 JS 段（读 data-src），再退到直读属性。
      var imageUrls = const <String>[];
      var imageSource = '';
      // 书源的 JS 段只是**一条路**：它自己写错了也不该把整步拖死 ——
      // 记下它没跑通，再走"直读元素属性"那条路（真机上就是这么栽的：
      // JS 段返回 undefined，兜底明明能取到图，却被这个错直接判成失败）。
      var jsTrouble = '';
      final jsBody = source.contentRules['content'] ?? '';
      if (isComicJsRule(jsBody)) {
        try {
          final raw = await target.evalRaw(
            buildComicJsBlockScript(comicJsBody(jsBody)),
          );
          imageUrls = _imageUrlsFromJsResult(raw);
          if (imageUrls.isNotEmpty) imageSource = '（来自书源的 JS 段）';
        } on ComicProbeException catch (e) {
          jsTrouble = '书源 JS 段没跑通（${e.message}），改用元素属性直读；';
        }
      }
      if (imageUrls.isEmpty && urlWait.urls.isNotEmpty) {
        imageUrls = urlWait.urls;
        imageSource = urlWait.attr == 'data-src'
            ? '（$jsTrouble元素上的 data-src 直读）'
            : '（$jsTrouble元素上也没有 data-src，改用 src 直读）';
      }
      firstImageUrl = imageUrls.isEmpty ? null : source.absolute(imageUrls.first);
      final step = ComicProbeStep(
        name: '章节取图',
        ok: imageUrls.isNotEmpty,
        elapsedMs: stepSw.elapsedMilliseconds,
        note: (imageUrls.isNotEmpty
                ? '取到 ${imageUrls.length} 张图，首张来自 '
                    '${Uri.tryParse(firstImageUrl!)?.host ?? '—'}$imageSource'
                : urlWait.elementCount > 0
                    ? '$jsTrouble等了 ${urlWait.seconds} 秒，$imageRule 命中 '
                        '${urlWait.elementCount} 个元素，但它们的 data-src / src 里都没有地址'
                        '（图可能还没加载出来，或站点改了取图方式）'
                        '（页面标题：${pageTitle ?? '读不到'}）'
                        '${sample == null || sample.isEmpty ? '' : ' 元素实际长这样：$sample'}'
                    : _zeroHitNote(
                        selector: imageRule,
                        waitedSeconds: urlWait.seconds,
                        pageTitle: pageTitle,
                        count: urlWait.elementCount,
                      )) +
            navSuffix(nav),
        samples: imageUrls.take(2).toList(),
        finalUrl: finalUrl,
        pageTitle: pageTitle,
      );
      steps.add(step);
      onStep?.call(step);
    } catch (e) {
      final step = ComicProbeStep(
        name: '章节取图',
        ok: false,
        elapsedMs: stepSw.elapsedMilliseconds,
        note: e is ComicProbeException
            ? e.message
            : '打不开章节页：${describeComicProbeError(e)}',
        finalUrl: await _safe(() => target.currentUrl()),
      );
      steps.add(step);
      onStep?.call(step);
    }
  }

  // ── 第 4 步：真下一张图 ─────────────────────────────────────────
  //
  // 前三步证明的是"能列出图地址"，这一步证明"图能下下来" —— 两回事。用户 2026-10-01
  // 报的正是"自检三路全通、封面却一直转圈"：源没问题，是图床在这台手机的网上取不到。
  // 所以这一步失败时要**直说是图床/网络的问题**，别让人以为书源又要修。
  if (firstImageUrl == null) {
    const step = ComicProbeStep(
      name: '图片下载',
      ok: false,
      elapsedMs: 0,
      note: '上一步没拿到图地址，跳过了（不是"通过"）',
    );
    steps.add(step);
    onStep?.call(step);
  } else {
    final stepSw = Stopwatch()..start();
    final host = Uri.tryParse(firstImageUrl)?.host ?? firstImageUrl;
    try {
      final bytes = await (imageDownloader ?? downloadComicImageForProbe)(
        firstImageUrl,
      );
      final step = ComicProbeStep(
        name: '图片下载',
        ok: true,
        elapsedMs: stepSw.elapsedMilliseconds,
        note: '真下到 ${_kb(bytes)}（$host），用的就是 App 显示封面/漫画页那条路'
            '（图片缓存 + 手机 UA）',
      );
      steps.add(step);
      onStep?.call(step);
    } catch (e) {
      final step = ComicProbeStep(
        name: '图片下载',
        ok: false,
        elapsedMs: stepSw.elapsedMilliseconds,
        note: '图下不下来（$host）：${e is ComicImageException ? e.message : describeComicProbeError(e)}'
            ' —— 前三步已经证明书源能列出图地址，所以这是**图床/网络**的问题，'
            '不是书源坏了',
      );
      steps.add(step);
      onStep?.call(step);
    }
  }

  sw.stop();
  return ComicProbeReport(
    sourceName: source.name,
    steps: steps,
    firstBookUrl: firstBookUrl,
    firstChapterUrl: firstChapterUrl,
    firstImageUrl: firstImageUrl,
    tocCount: tocCount,
    totalMs: sw.elapsedMilliseconds,
  );
}

class _WaitResult {
  const _WaitResult(this.count, this.seconds);
  final int count;
  final int seconds;
}

/// 打开结果：成不成、用的哪个地址、以及**每一条尝试的说明**。
class ComicNavOutcome {
  const ComicNavOutcome({required this.ok, this.usedUrl, this.attempts = const []});

  final bool ok;
  final String? usedUrl;

  /// 形如 `cn.baozimhcn.com：连接被重置（net::ERR_CONNECTION_RESET）`，
  /// 只放失败的和"重试后才成功"的 —— 一次就成功不留噪音。
  final List<String> attempts;

  bool get hadTrouble => attempts.isNotEmpty;
}

/// 打不开时的说明：把每一条尝试都列出来（哪个镜像什么错，一目了然）。
String comicNavFailureNote(ComicNavOutcome outcome, String what) {
  if (outcome.attempts.isEmpty) return '$what打不开（没有可用的地址）';
  return '$what打不开，每个地址都试过：${outcome.attempts.join('；')}';
}

/// 打开一个地址：**主站优先**，失败按 `mirrors` 顺序换镜像；每个地址最多试 2 次
/// （连接被重置这种多半是这一跳被打断，重试一次经常就好了）。
///
/// 换镜像/重试都**如实记在 [ComicNavOutcome.attempts] 里报给用户** —— 不静默兜底。
Future<ComicNavOutcome> openComicWithFallback(
  ComicSourceTarget target,
  ComicSource source,
  String pathOrUrl, {
  Map<String, String>? headers,
  int attemptsPerHost = 2,
  Duration retryDelay = const Duration(milliseconds: 700),
  Future<void> Function(Duration)? sleep,
}) async {
  final candidates = comicMirrorCandidates(source, pathOrUrl);
  if (candidates.isEmpty) {
    return const ComicNavOutcome(ok: false);
  }
  final attempts = <String>[];
  final wait = sleep ?? (d) => Future<void>.delayed(d);

  for (final url in candidates) {
    final host = Uri.tryParse(url)?.host ?? url;
    for (var i = 0; i < attemptsPerHost; i++) {
      try {
        await target.open(url, headers: headers);
      } catch (e) {
        attempts.add('$host：${_short(e)}');
        if (i + 1 < attemptsPerHost) await wait(retryDelay);
        continue;
      }
      final err = target.lastLoadError;
      if (err == null) {
        if (i > 0) attempts.add('$host：第 ${i + 1} 次才成功');
        return ComicNavOutcome(ok: true, usedUrl: url, attempts: attempts);
      }
      final kind = classifyComicLoadError(
        code: err.code,
        description: err.description,
      );
      attempts.add('$host：${comicLoadErrorText(code: err.code, description: err.description)}');
      if (!comicLoadErrorRetryable(kind)) {
        // 手机没网这种，换镜像也没意义 —— 直接停，别浪费用户时间。
        return ComicNavOutcome(ok: false, attempts: attempts);
      }
      if (i + 1 < attemptsPerHost) await wait(retryDelay);
    }
  }
  return ComicNavOutcome(ok: false, attempts: attempts);
}

/// 打开时有波折（重试后才成功 / 换了镜像）就在结论里点出来：
/// 先列失败原因，再说最后是从哪个地址打开的 —— 不静默兜底。
String navSuffix(ComicNavOutcome nav) {
  if (!nav.hadTrouble) return '';
  final host = nav.usedUrl == null ? null : Uri.tryParse(nav.usedUrl!)?.host;
  final detail = nav.attempts.join('；');
  return host == null ? ' · $detail' : ' · $detail；最后用 $host 打开成功';
}

String _short(Object e) {
  final t = e.toString().replaceFirst('ComicProbeException: ', '').trim();
  return t.length > 80 ? '${t.substring(0, 80)}…' : t;
}

/// 字节数说人话（自检的「图片下载」步要写清"真下到多少"）。
String _kb(int bytes) =>
    bytes < 1024 ? '$bytes 字节' : '${(bytes / 1024).toStringAsFixed(1)} KB';

/// 轮询等到选择器命中；超时返回最后的命中数（**不抛**，由调用方判断并说明）。
///
/// 两个坑都是实测踩出来的，写在这里免得下次重犯：
///   * 超时用**计时器**（`Timer`）而不是墙上时钟（`Stopwatch`）—— 后者在 widget 测试的
///     假时钟下永远不到期，页面就一直转圈、测试卡死；
///   * 结束时**必须取消所有计时器** —— 否则每等一次就留一个悬挂计时器（真机上只是浪费，
///     测试里直接报 "A Timer is still pending..."）。
Future<_WaitResult> _waitForCount(
  ComicSourceTarget target,
  String? css, {
  required Duration waitTimeout,
  required Duration pollInterval,
}) {
  if (css == null || css.isEmpty) {
    return Future.value(const _WaitResult(0, 0));
  }
  final sw = Stopwatch()..start();
  final done = Completer<_WaitResult>();
  var count = 0;
  Timer? ticker;
  Timer? deadline;

  void finish() {
    if (done.isCompleted) return;
    ticker?.cancel();
    deadline?.cancel();
    done.complete(_WaitResult(count, sw.elapsed.inSeconds));
  }

  Future<void> probeOnce() async {
    if (done.isCompleted) return;
    count = await _safe(() => target.countOf(css)) ?? 0;
    if (count > 0) finish();
  }

  unawaited(probeOnce());
  ticker = Timer.periodic(pollInterval, (_) => unawaited(probeOnce()));
  deadline = Timer(waitTimeout, finish);
  return done.future;
}

/// 等图地址的结果。
class _UrlWait {
  const _UrlWait({
    required this.urls,
    required this.attr,
    required this.seconds,
    required this.elementCount,
  });

  final List<String> urls;

  /// 地址取自哪个属性（`data-src` / `src`）；没等到就是空串。
  final String attr;
  final int seconds;

  /// 期间看到的选择器命中数（用来区分"没有元素"和"有元素但没地址"）。
  final int elementCount;
}

/// 等**图地址**出现 —— 元素出现不等于地址出现：AMP 是懒加载，先有 `amp-img` 占位，
/// 之后（脚本跑完）才把 `data-src` / `src` 填上。真机上就是在这里栽的：
/// 元素 1 秒内就命中了，于是"等元素"的判据当场通过，而地址还是空的。
Future<_UrlWait> _waitForImageUrls(
  ComicSourceTarget target,
  String css, {
  required Duration waitTimeout,
  required Duration pollInterval,
}) {
  if (css.isEmpty) {
    return Future.value(
      const _UrlWait(urls: [], attr: '', seconds: 0, elementCount: 0),
    );
  }
  final sw = Stopwatch()..start();
  final done = Completer<_UrlWait>();
  var elementCount = 0;
  Timer? ticker;
  Timer? deadline;

  void finish(_UrlWait r) {
    if (done.isCompleted) return;
    ticker?.cancel();
    deadline?.cancel();
    done.complete(r);
  }

  Future<List<String>> urlsOf(String attr) async {
    final raw = await _safe(() => target.attrsOf(css, attr)) ?? const <String>[];
    return raw.where((u) => u.trim().isNotEmpty).toList();
  }

  Future<void> probeOnce() async {
    if (done.isCompleted) return;
    final data = await urlsOf('data-src');
    if (data.isNotEmpty) {
      finish(_UrlWait(
        urls: data,
        attr: 'data-src',
        seconds: sw.elapsed.inSeconds,
        elementCount: elementCount,
      ));
      return;
    }
    final plain = await urlsOf('src');
    if (plain.isNotEmpty) {
      finish(_UrlWait(
        urls: plain,
        attr: 'src',
        seconds: sw.elapsed.inSeconds,
        elementCount: elementCount,
      ));
      return;
    }
    elementCount = await _safe(() => target.countOf(css)) ?? elementCount;
  }

  unawaited(probeOnce());
  ticker = Timer.periodic(pollInterval, (_) => unawaited(probeOnce()));
  deadline = Timer(waitTimeout, () {
    finish(_UrlWait(
      urls: const [],
      attr: '',
      seconds: sw.elapsed.inSeconds,
      elementCount: elementCount,
    ));
  });
  return done.future;
}

/// 0 命中的说明：把页面标题带出来 —— 502/403 这类错误只看"命中 0"是看不出来的。
String _zeroHitNote({
  required String? selector,
  required int waitedSeconds,
  required String? pageTitle,
  int count = 0,
}) {
  final t = pageTitle?.trim() ?? '';
  final hint = t.isEmpty
      ? '（页面标题读不到）'
      : t.contains('502') || t.toLowerCase().contains('bad gateway')
          ? '（页面是 502 Bad Gateway —— 站点这一侧的上游挂了：实测三个镜像都一样，'
              '换网络/换手机也一样，不是这台手机的问题）'
          : t.contains('403')
              ? '（被站点挡了，403）'
              : t.contains('验证') || t.toLowerCase().contains('challenge')
                  ? '（还停在人机验证页）'
                  : '（页面标题：$t）';
  // 命中数**按实际写**：这里以前写死"仍 0 命中"，于是在"元素在、属性空"的情况下
  // 会说假话（真机上就是被这句话带偏过一次）。
  return '等了 $waitedSeconds 秒，选择器 ${selector ?? '—'} 命中 $count 个$hint';
}

/// 从 `ruleContent.content` 的 JS 里抠出图片选择器（`java.getElements('class.comic-contain@amp-img')`）。
String? _imageRuleFromContentJs(String js) {
  final m = RegExp(r"""getElements\(\s*['"]([^'"]+)['"]\s*\)""").firstMatch(js);
  if (m == null) return null;
  return cssFromComicRule(m.group(1)!);
}

/// 从 JS 段返回的 `<img src="…">` 串里抽出图片地址。
List<String> _imageUrlsFromJsResult(String raw) {
  // 书源 JS 段的返回（`{"text":…}` / `{"error":…}`）→ 文本。
  // 引擎报的错**抛出去**，由调用方决定"是判失败还是走兜底"，不在这里吞掉。
  final text = comicJsSegmentText(raw);
  final out = <String>[];
  for (final m in RegExp(r'''src\s*=\s*["']([^"']+)["']''').allMatches(text)) {
    final u = m.group(1)!.trim();
    if (u.isNotEmpty) out.add(u);
  }
  return out;
}

/// 用规则在页面上取值。取值失败**不抛**（返回空表），由调用方据空表说明情况；
/// 规则本身不认识会抛，因为那是配置错误，不该被当成"站点没数据"。
Future<List<String>> _extractValues(ComicSourceTarget target, String rule) async {
  if (rule.trim().isEmpty) return const [];
  final parsed = parseComicRule(rule);
  if (!parsed.ok && !isComicJsRule(rule)) {
    throw ComicProbeException('规则不认识：「$rule」（${parsed.unknown}）');
  }
  if (isComicJsRule(rule)) {
    final raw = await target.evalRaw(buildComicJsBlockScript(comicJsBody(rule)));
    return _imageUrlsFromJsResult(raw);
  }
  final raw = await target.evalRaw(buildComicRuleScript(rule));
  return comicValuesFromResult(raw);
}

Future<T?> _safe<T>(Future<T> Function() f) async {
  try {
    return await f();
  } catch (_) {
    return null;
  }
}

/// 把取数层的异常翻成人话。
String describeComicProbeError(Object e) {
  if (e is ComicProbeException) return e.message;
  final s = e.toString();
  if (s.contains('Timeout') || s.contains('超时')) return '超时（页面一直没加载完）';
  if (s.contains('502') || s.toLowerCase().contains('bad gateway')) {
    return '站点这一路 502（镜像不可达）';
  }
  if (s.contains('403')) return '被站点挡了（403）';
  return s;
}
