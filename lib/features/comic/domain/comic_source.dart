// 漫画源模型 + 规则解析（纯 Dart，可单测；不碰网络、不碰 WebView）。
//
// 规则语法是 **Legado 书源的子集**，只实现这份源真实用到的形状。不打算做通用引擎：
// 通用引擎需要 JS 求值、正则、模板等一大套，而本 App 里真正要的是"这个源能不能用、
// 衰了能不能看出来"。所以每个不认识的规则段都**显式报错**，不静默返回空。
//
// 支持的形状：
//   class.a b c        同一元素上有这几个类（合成 CSS 的 .a.b.c）
//   tag.a / id.x       标签 / id
//   class.a@tag.b@href 先 .a，再从里面找 tag.b，取属性
//   class.a.0@text     取第 0 个，再取文本
//   text / html        文本 / 内部 HTML
//   任意属性名          getAttribute（src、data-src、href…）
//   以 <js> 或 @js: 开头  整段交给页面里的 JS 直接跑（本 App 不实现 Dart 侧 JS）
library;

import 'dart:convert';

/// 解析后的单步规则。
sealed class ComicRuleStep {
  const ComicRuleStep();
}

/// 选择器步：从当前节点集合往下找。
class ComicSelectorStep extends ComicRuleStep {
  const ComicSelectorStep({required this.css, this.index});

  /// 合成出来的 CSS 选择器（如 `.comics-card.pure-u-1-2`）。
  final String css;

  /// 取第几个（Legado 的 `.0`）；null = 全部。
  final int? index;

  @override
  String toString() => 'selector($css${index == null ? '' : '[${index!}]'})';
}

/// 取值步：text / html / 属性名。
class ComicValueStep extends ComicRuleStep {
  const ComicValueStep(this.kind);

  /// `text` · `html` · 其它一律当属性名。
  final String kind;

  /// 是否取文本。
  bool get isText => kind == 'text';

  /// 是否取内部 HTML。
  bool get isHtml => kind == 'html';

  @override
  String toString() => 'value($kind)';
}

/// 规则解析结果：要么拿到步骤，要么拿到"哪一段不认识"。
class ComicRuleParse {
  const ComicRuleParse({this.steps = const [], this.unknown});

  final List<ComicRuleStep> steps;

  /// 不认识的规则段原文（非 null 表示这条规则不可用）。
  final String? unknown;

  bool get ok => unknown == null && steps.isNotEmpty;
}

/// 取值名白名单：写到规则最后就是"取值"，不会被当成标签。
const kComicValueHolders = <String>{'text', 'html', 'href', 'src', 'alt', 'title'};

final RegExp _selectorToken = RegExp(r'^(class|tag|id)\.(.+)$');
final RegExp _indexToken = RegExp(r'^\.(\d+)$');

/// 把一条 Legado 规则解析成步骤；不认识的段返回 [ComicRuleParse.unknown]。
///
/// [valueRule] 决定"最后一段的裸 token"怎么理解 —— 这是这份源里真实存在的歧义：
///   * **取值规则**（`…@text`、`…@src`、`…@harf`）：最后一段是**属性/文本**；
///   * **选择器规则**（`java.getElements('class.comic-contain@amp-img')`）：裸 token 是**标签**。
/// 位置 + 取值名（text/html/href/…）能把这歧义定死，所以模式必须由调用方明说，不能猜。
ComicRuleParse parseComicRule(String raw, {bool valueRule = false}) {
  final rule = raw.trim();
  if (rule.isEmpty) return const ComicRuleParse(unknown: '（空规则）');
  if (isComicJsRule(rule)) {
    return const ComicRuleParse(unknown: 'JS 规则（交给页面里的 WebView 执行，不走解析）');
  }

  final steps = <ComicRuleStep>[];
  final rawSteps = rule.split('@').map((s) => s.trim()).toList();

  for (var si = 0; si < rawSteps.length; si++) {
    final step = rawSteps[si];
    if (step.isEmpty) continue;
    final isLast = si == rawSteps.length - 1;

    // 取值步要在"裸 token 当标签"之前判掉：`text` 和 `amp-img` 长得一样，
    // 差别只在"它是取值名、且写在最后"。
    if (!step.contains(' ') &&
        (kComicValueHolders.contains(step) ||
            (valueRule && isLast && _looksLikeAttr(step)))) {
      steps.add(ComicValueStep(step));
      continue;
    }

    // `.0` 这类索引步：附加到上一步的选择器上。
    final indexMatch = _indexToken.firstMatch(step);
    if (indexMatch != null) {
      if (steps.isEmpty || steps.last is! ComicSelectorStep) {
        return ComicRuleParse(unknown: step);
      }
      final last = steps.removeLast() as ComicSelectorStep;
      steps.add(
        ComicSelectorStep(css: last.css, index: int.parse(indexMatch.group(1)!)),
      );
      continue;
    }

    // 选择器步。Legado 的语义：**一段里第一个 token 决定类型，后面裸着的 token
    // 是"同一个元素上的更多类名"**（`class.a b c` = `.a.b.c`）；索引 `.N` 可以单独
    // 成 token，也可以贴在名字尾巴上（`tag.amp-img.0`）。
    // 一段里出现两个带前缀的选择器 → 不认识就报出来，不猜（本 App 用到的源没有这种写法）。
    final tokens = step.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    String? type;
    String? firstName;
    int? index;
    final extras = <String>[];
    var bad = false;
    for (final token in tokens) {
      // 已经是 CSS 的整段（`.a.b` / `#id`）→ 直接当 CSS。
      // 与页面里的 JS 引擎同一套判据：调用方很容易把"自己拼的 CSS"当"书源规则"传进来。
      if (RegExp(r'^[.#][A-Za-z_][A-Za-z0-9_.\-#]*$').hasMatch(token)) {
        if (type != null) {
          bad = true;
          break;
        }
        type = 'raw';
        firstName = token;
        continue;
      }
      final indexOnly = _indexToken.firstMatch(token);
      if (indexOnly != null) {
        index = int.parse(indexOnly.group(1)!);
        continue;
      }
      final m = _selectorToken.firstMatch(token);
      if (m != null) {
        if (type != null) {
          bad = true;
          break;
        }
        type = m.group(1)!;
        var name = m.group(2)!;
        final tail = RegExp(r'^(.*)\.(\d+)$').firstMatch(name);
        if (tail != null) {
          name = tail.group(1)!;
          index = int.parse(tail.group(2)!);
        }
        firstName = name;
        continue;
      }
      if (RegExp(r'^[A-Za-z][A-Za-z0-9_-]*$').hasMatch(token)) {
        extras.add(token);
        continue;
      }
      bad = true;
      break;
    }
    if (!bad && firstName == null && extras.isNotEmpty) {
      // 裸标签名开头（`amp-img`、`a`）
      firstName = extras.removeAt(0);
    }
    if (!bad && firstName != null && firstName.isNotEmpty) {
      final head = switch (type) {
        'raw' => firstName,
        'tag' => firstName,
        'id' => '#$firstName',
        'class' => '.$firstName',
        // type == null = 裸标签名开头（amp-img / a）
        _ => firstName,
      };
      steps.add(
        ComicSelectorStep(
          css: head + extras.map((c) => '.$c').join(),
          index: index,
        ),
      );
      continue;
    }

    // 取值步：text/html/属性名（属性名不做白名单，站点用什么属性都允许）。
    if (tokens.length == 1 && (kComicValueHolders.contains(step) || _looksLikeAttr(step))) {
      steps.add(ComicValueStep(step));
      continue;
    }
    return ComicRuleParse(unknown: step);
  }

  if (steps.isEmpty) return const ComicRuleParse(unknown: '（空规则）');
  return ComicRuleParse(steps: steps);
}

bool _looksLikeAttr(String s) => RegExp(r'^[A-Za-z][A-Za-z0-9_-]*$').hasMatch(s);

/// 是不是 JS 规则（`<js>…</js>` 或 `@js:…`）—— 这类整段交给页面执行。
bool isComicJsRule(String raw) {
  final t = raw.trim();
  return t.startsWith('<js>') || t.startsWith('@js:') || t.startsWith('@js');
}

/// 取出 JS 规则里的脚本体（去掉 `<js>` / `@js:` 包裹）。
String comicJsBody(String raw) {
  var t = raw.trim();
  if (t.startsWith('<js>')) t = t.substring(4);
  if (t.endsWith('</js>')) t = t.substring(0, t.length - 5);
  if (t.startsWith('@js:')) t = t.substring(4);
  return t.trim();
}

/// 一个漫画源（Legado 书源格式的子集）。
class ComicSource {
  const ComicSource({
    required this.name,
    required this.baseUrl,
    this.searchUrl,
    this.exploreUrl,
    this.headerJs,
    this.searchRules = const {},
    this.bookInfoRules = const {},
    this.tocRules = const {},
    this.contentRules = const {},
    this.exploreRules = const {},
    this.mirrors = const [],
    this.comment,
  });

  final String name;

  /// 备用镜像（**App 侧扩展字段**，Legado 没有这个键）：主站某一跳被重置/502 时按序试。
  /// 顺序有意义：先主站、再镜像；镜像同样失败就如实报每一条尝试。
  final List<String> mirrors;
  final String baseUrl;

  /// 搜索地址模板，含 `{{key}}`。
  final String? searchUrl;

  /// 分类地址（这份源是 JS 生成的列表）。
  final String? exploreUrl;

  /// 附加请求头（这份源是 `@js:` 形式）。
  final String? headerJs;

  final Map<String, String> searchRules;
  final Map<String, String> bookInfoRules;
  final Map<String, String> tocRules;
  final Map<String, String> contentRules;

  /// 分类浏览的取数规则（这份源取的是 **JSON 接口**，规则是 `$.items[*]` 这种写法）。
  final Map<String, String> exploreRules;

  /// 书源自带的备注（可能包含作者对可用性的观察）。
  final String? comment;

  /// 解析一份书源 JSON。**名字或域名为空即失败** —— 缺了它们后面没法取数，
  /// 与其带一个半残的源往下跑，不如当场说不认识。
  static ComicSource? tryParse(String json) {
    final Object? raw;
    try {
      raw = jsonDecode(json);
    } catch (_) {
      return null;
    }
    if (raw is! Map) return null;
    final name = _str(raw['bookSourceName'])?.trim();
    final base = _str(raw['bookSourceUrl'])?.trim();
    if (name == null || name.isEmpty || base == null || base.isEmpty) return null;
    return ComicSource(
      name: name,
      baseUrl: base,
      searchUrl: _str(raw['searchUrl'])?.trim(),
      exploreUrl: _str(raw['exploreUrl'])?.trim(),
      headerJs: _str(raw['header'])?.trim(),
      searchRules: _strMap(raw['ruleSearch']),
      bookInfoRules: _strMap(raw['ruleBookInfo']),
      tocRules: _strMap(raw['ruleToc']),
      contentRules: _strMap(raw['ruleContent']),
      exploreRules: _strMap(raw['ruleExplore']),
      mirrors: _strList(raw['mirrors']),
      comment: _str(raw['bookSourceComment']),
    );
  }

  /// 搜索地址：把 `{{key}}` 换成关键字（**URL 编码**，中文关键字必须编码）。
  String? searchUrlFor(String key) {
    final tpl = searchUrl;
    if (tpl == null || tpl.isEmpty) return null;
    final encoded = Uri.encodeComponent(key.trim());
    return tpl.replaceAll('{{key}}', encoded).replaceAll('{{page}}', '1');
  }

  /// 分类地址：把 `{{page}}` 换成页码。
  String? exploreUrlFor(int page) {
    final tpl = exploreUrl;
    if (tpl == null || tpl.isEmpty) return null;
    if (isComicJsRule(tpl)) {
      // 这份源的分类地址是 JS 生成的一整张列表，取数时按分类各自展开；
      // 自检阶段只需要知道"它是 JS 生成的"，由取数层去跑。
      return null;
    }
    return tpl.replaceAll('{{page}}', '$page');
  }

  /// 把相对地址补成绝对地址（搜索结果里的 href 都是 `/comic/xxx`）。
  String absolute(String path) {
    final p = path.trim();
    if (p.isEmpty) return p;
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    return Uri.parse(baseUrl).resolve(p).toString();
  }

  /// 自检要验的规则是否都认得出来（不认识的段在这里就暴露，不等到界面上）。
  List<String> unknownRules() {
    final out = <String>[];
    void scan(Map<String, String> rules, String bucket) {
      rules.forEach((key, value) {
        if (isComicJsRule(value)) return; // JS 规则交给页面执行
        final parsed = parseComicRule(value);
        if (!parsed.ok) {
          out.add('$bucket.$key = $value（不认识：${parsed.unknown}）');
        }
      });
    }

    scan(searchRules, 'ruleSearch');
    scan(bookInfoRules, 'ruleBookInfo');
    scan(tocRules, 'ruleToc');
    scan(contentRules, 'ruleContent');
    return out;
  }
}

/// 把规则里的选择器段拼成一条 CSS（等待页面就绪、报命中数时用）。
///
/// `class.comic-contain@amp-img` → `.comic-contain amp-img`；
/// 规则里没有选择器段（纯 JS / 纯取值步）时返回 null。
String? cssFromComicRule(String rule, {bool valueRule = false}) {
  final parts = _leadingSelectorCss(rule);
  if (parts.isEmpty) return null;
  return parts.join(' ');
}

/// **只有最前面那一段选择器**的 CSS（遇到取值步/认不出的段就停）。
///
/// 为什么要单独有这么个东西：书源的 `tocUrl` 里第 3 段 `harf` 是它自己的笔误
/// （本意是 `href`），照整条规则拼 CSS 会拼出 `.容器 a harf .item` 这种**永远匹配不到**
/// 的选择器 —— 看似"章节 0 条"，其实是我的拼接错了。数章节只用容器那一段。
String? firstSelectorCss(String rule) {
  final parts = _leadingSelectorCss(rule);
  if (parts.isEmpty) return null;
  return parts.first;
}

List<String> _leadingSelectorCss(String rule) {
  final parsed = parseComicRule(rule);
  final out = <String>[];
  for (final step in parsed.steps) {
    if (step is! ComicSelectorStep) break; // 取值步/认不出的段 = 选择器链到此为止
    out.add(step.css);
  }
  return out;
}

String? _str(Object? v) => v is String ? v : null;

Map<String, String> _strMap(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, String>{};
  raw.forEach((k, v) {
    if (v is String && v.trim().isNotEmpty) out['$k'] = v.trim();
  });
  return out;
}

/// 取规则的**第一段选择器原文**（保留 `class.` / `tag.` 写法）。
///
/// 与 [firstSelectorCss] 的区别：那个给"页面查询"用（`.a.b`），这个是给
/// **书源规则求值**用（`class.a b`）—— 引擎按规则解析，两者写法不同，别混着传
/// （真机上把 CSS 当规则传过一次：整段解析失败 → 只剩一个"卡片" → "共 1 话"）。
String? firstSelectorRule(String rule) {
  final t = rule.trim();
  if (t.isEmpty || isComicJsRule(t)) return null;
  final first = t.split('@').first.trim();
  if (first.isEmpty) return null;
  final parsed = parseComicRule(first, valueRule: false);
  if (!parsed.ok || parsed.steps.isEmpty) return null;
  return first;
}

/// 把 `mirrors`（字符串数组）读出来；没有就是空表。
List<String> _strList(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Object>()
      .map((e) => e.toString().trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

/// 同一个路径在各镜像上的候选地址（**主站优先**，然后按配置顺序）。
///
/// [pathOrUrl] 可以是相对路径（`/comic/x`）也可以是完整地址；是完整地址时会把它
/// 拆成路径再拼到各镜像上。去重并保序 —— 顺序就是尝试顺序。
List<String> comicMirrorCandidates(ComicSource source, String pathOrUrl) {
  final raw = pathOrUrl.trim();
  if (raw.isEmpty) return const [];
  String path = raw;
  if (raw.startsWith('http://') || raw.startsWith('https://')) {
    final u = Uri.tryParse(raw);
    if (u == null || u.host.isEmpty) return [raw];
    path = u.path + (u.hasQuery ? '?${u.query}' : '');
    final self = <String>[raw];
    for (final m in source.mirrors) {
      final base = m.trim();
      if (base.isEmpty) continue;
      final built = _joinUrl(base, path);
      if (built != null && !self.contains(built)) self.add(built);
    }
    return self;
  }
  final out = <String>[];
  final host = source.baseUrl.trim();
  final first = _joinUrl(host, path);
  if (first != null) out.add(first);
  for (final m in source.mirrors) {
    final built = _joinUrl(m.trim(), path);
    if (built != null && !out.contains(built)) out.add(built);
  }
  return out;
}

String? _joinUrl(String host, String path) {
  final h = host.trim();
  if (h.isEmpty) return null;
  final base = h.endsWith('/') ? h.substring(0, h.length - 1) : h;
  final p = path.startsWith('/') ? path : '/$path';
  final merged = '$base$p';
  return Uri.tryParse(merged) == null ? null : merged;
}

/// 打开页面时的错误种类 —— 决定"重试 / 换镜像 / 直接停"。
enum ComicLoadErrorKind {
  /// 连接被重置（最常见的"这一跳被打断"）。
  connectionReset,

  /// 其它连接层错误（拒绝、关闭、未到达…）。
  connectionOther,

  /// 超时。
  timeout,

  /// 域名解析不了。
  nameNotResolved,

  /// 手机本身没网。
  offline,

  /// 说不清。
  other,
}

/// 按**描述文本**判种类（Chromium 的 `net::ERR_*` 串最忠实；数字码各平台不一致）。
ComicLoadErrorKind classifyComicLoadError({int? code, String? description}) {
  final d = (description ?? '').toUpperCase();
  if (d.contains('ERR_INTERNET_DISCONNECTED')) return ComicLoadErrorKind.offline;
  if (d.contains('ERR_NAME_NOT_RESOLVED')) {
    return ComicLoadErrorKind.nameNotResolved;
  }
  if (d.contains('ERR_CONNECTION_RESET') ||
      d.contains('ERR_CONNECTION_ABORTED') ||
      d.contains('ERR_CONNECTION_CLOSED')) {
    return ComicLoadErrorKind.connectionReset;
  }
  if (d.contains('ERR_CONNECTION')) return ComicLoadErrorKind.connectionOther;
  if (d.contains('ERR_TIMED_OUT') || d.contains('TIMEOUT')) {
    return ComicLoadErrorKind.timeout;
  }
  // 描述读不出来时，退回数字码（Android 旧表：-6 连接失败、-8 超时）。
  switch (code) {
    case -6:
      return ComicLoadErrorKind.connectionOther;
    case -7:
    case -8:
      return ComicLoadErrorKind.timeout;
    case -2:
      return ComicLoadErrorKind.nameNotResolved;
  }
  return ComicLoadErrorKind.other;
}

/// 这种错误值不值得再试一次（同地址重试或换镜像）。
bool comicLoadErrorRetryable(ComicLoadErrorKind kind) =>
    kind != ComicLoadErrorKind.offline;

/// 人话说明（报给用户的就是这句）。
String comicLoadErrorText({int? code, String? description}) {
  final kind = classifyComicLoadError(code: code, description: description);
  final raw = (description ?? '').trim();
  final suffix = raw.isEmpty ? '' : '（$raw）';
  return switch (kind) {
    ComicLoadErrorKind.connectionReset => '连接被重置$suffix',
    ComicLoadErrorKind.connectionOther => '连接失败$suffix',
    ComicLoadErrorKind.timeout => '超时$suffix',
    ComicLoadErrorKind.nameNotResolved => '域名解析失败$suffix',
    ComicLoadErrorKind.offline => '这台手机当前没有网络$suffix',
    ComicLoadErrorKind.other => '加载失败${code == null ? '' : '（错误码 $code）'}$suffix',
  };
}
