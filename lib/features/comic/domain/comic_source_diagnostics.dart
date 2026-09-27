// 漫画源自检：用真手机上的 WebView 把「搜索 → 详情 → 章节取图」跑一遍，逐项给结论。
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

/// 跑一次自检。[key] 是搜索关键字。
Future<ComicProbeReport> runComicSourceProbe({
  required ComicSourceTarget target,
  required ComicSource source,
  String key = '海贼',
  Duration waitTimeout = kComicProbeWaitTimeout,
  Duration pollInterval = kComicProbePollInterval,
  void Function(ComicProbeStep step)? onStep,
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
            note: _zeroHitNote(
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
            note: (urls.isNotEmpty
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
          note: _zeroHitNote(
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
          note: '书名「${names.isEmpty ? '—' : names.first}」'
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
  if (firstChapterUrl == null) {
    const step = ComicProbeStep(
      name: '章节取图',
      ok: false,
      elapsedMs: 0,
      note: '上一步没拿到章链，跳过了（不是"通过"）',
    );
    steps.add(step);
    onStep?.call(step);
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
      final jsBody = source.contentRules['content'] ?? '';
      if (isComicJsRule(jsBody)) {
        final raw = await target.evalRaw(
          buildComicJsBlockScript(comicJsBody(jsBody)),
        );
        imageUrls = _imageUrlsFromJsResult(raw);
        if (imageUrls.isNotEmpty) imageSource = '（来自书源的 JS 段）';
      }
      if (imageUrls.isEmpty && urlWait.urls.isNotEmpty) {
        imageUrls = urlWait.urls;
        imageSource = urlWait.attr == 'data-src'
            ? '（JS 段没给图链，改用元素上的 data-src 直读）'
            : '（JS 段没给图链、元素上也没有 data-src，改用 src 直读）';
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
                    ? '等了 ${urlWait.seconds} 秒，$imageRule 命中 '
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
  final json = _decodeJsonString(raw);
  final text = json is String ? json : _textOf(json);
  final out = <String>[];
  for (final m in RegExp(r'''src\s*=\s*["']([^"']+)["']''').allMatches(text)) {
    final u = m.group(1)!.trim();
    if (u.isNotEmpty) out.add(u);
  }
  return out;
}

/// JSON 字符串反转义。WebView 回来的字符串是**转义过**的（引号是 \"、换行是 \n）；
/// 不还原的话，后面按引号匹配 `<img src="…">` 会一律匹配不到 —— 那就成了
/// "取到 0 张图"的假结论，正好是要避免的那种假。
String unescapeJsonString(String s) {
  final sb = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c != r'\' || i + 1 >= s.length) {
      sb.write(c);
      continue;
    }
    final n = s[++i];
    switch (n) {
      case 'n':
        sb.write('\n');
      case 't':
        sb.write('\t');
      case 'r':
        sb.write('\r');
      case 'u':
        if (i + 4 < s.length) {
          final code = int.tryParse(s.substring(i + 1, i + 5), radix: 16);
          if (code != null) {
            sb.writeCharCode(code);
            i += 4;
            continue;
          }
        }
        sb.write('u');
      default:
        sb.write(n);
    }
  }
  return sb.toString();
}

/// 引擎返回的是 JSON 字符串；这里尽量宽容地取出 text 字段或原样返回。
Object? _decodeJsonString(String raw) {
  final t = raw.trim();
  if (!t.startsWith('{') && !t.startsWith('"')) return t;
  if (t.startsWith('"') && t.endsWith('"')) {
    return unescapeJsonString(t.substring(1, t.length - 1));
  }
  final m = RegExp(r'"text"\s*:\s*"(.*)"\s*}', dotAll: true).firstMatch(t);
  if (m != null) return unescapeJsonString(m.group(1)!);
  final e = RegExp(r'"error"\s*:\s*"(.*)"\s*}', dotAll: true).firstMatch(t);
  if (e != null) throw ComicProbeException('JS 段出错：${e.group(1)}');
  return t;
}

String _textOf(Object? v) => v == null ? '' : '$v';

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
  return _valuesFromExtract(raw);
}

/// 解析引擎返回的 `{"values":[…]}` / `{"error":"…"}`。
List<String> _valuesFromExtract(String raw) {
  final decoded = _decodeJsonString(raw);
  if (decoded is! String) return const [];
  final t = decoded.trim();
  final m = RegExp(r'"values"\s*:\s*\[(.*?)\]\s*}', dotAll: true).firstMatch(t);
  if (m == null) return const [];
  final body = m.group(1)!;
  return RegExp(r'"((?:[^"\\]|\\.)*)"')
      .allMatches(body)
      .map((x) => unescapeJsonString(x.group(1)!))
      .toList();
}

Future<T?> _safe<T>(Future<T> Function() f) async {
  try {
    return await f();
  } catch (_) {
    return null;
  }
}

/// 自检里可以给人看的错误。
class ComicProbeException implements Exception {
  ComicProbeException(this.message);
  final String message;
  @override
  String toString() => message;
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
