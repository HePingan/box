import 'book_deduplicator.dart';
import 'field_constants.dart';
import 'models.dart';
import 'novel_source.dart';
import 'rule_engine.dart';
import 'rules/rule_engine_v2.dart';
import 'text_cleaner.dart';

class RuleNovelSource implements NovelSource {
  RuleNovelSource({
    required String baseUrl,
    required String searchUrl,
    String exploreUrl = '',
    String name = '',
    Map<String, dynamic>? ruleSearch,
    Map<String, dynamic>? ruleExplore,
    Map<String, dynamic>? ruleBookInfo,
    Map<String, dynamic>? ruleToc,
    Map<String, dynamic>? ruleContent,
    Map<String, String>? headers,
    RuleEngineV2? engine,
  }) : name = name.trim(),
       baseUrl = RuleEngine.normalizeBaseUrlInput(baseUrl),
       searchUrl = searchUrl.trim(),
       exploreUrl = exploreUrl.trim(),
       ruleSearch = ruleSearch ?? const {},
       ruleExplore = ruleExplore ?? const {},
       ruleBookInfo = ruleBookInfo ?? const {},
       ruleToc = ruleToc ?? const {},
       ruleContent = ruleContent ?? const {},
       headers = {'User-Agent': 'okhttp/4.9.2', ...?headers},
       _engine = engine ?? RuleEngine.v2;

  factory RuleNovelSource.fromBookSourceJson(Map<String, dynamic> json) {
    return RuleNovelSource(
      name: '${json['bookSourceName'] ?? ''}',
      baseUrl: '${json['bookSourceUrl'] ?? ''}',
      searchUrl: '${json['searchUrl'] ?? ''}',
      exploreUrl: '${json['exploreUrl'] ?? ''}',
      ruleSearch: RuleEngine.asMap(json['ruleSearch']),
      ruleExplore: RuleEngine.asMap(json['ruleExplore']),
      ruleBookInfo: RuleEngine.asMap(json['ruleBookInfo']),
      ruleToc: RuleEngine.asMap(json['ruleToc']),
      ruleContent: RuleEngine.asMap(json['ruleContent']),
      headers: RuleEngine.parseHeader(json['header']),
    );
  }

  final String name;
  final String baseUrl;
  final String searchUrl;
  final String exploreUrl;
  final Map<String, dynamic> ruleSearch;
  final Map<String, dynamic> ruleExplore;
  final Map<String, dynamic> ruleBookInfo;
  final Map<String, dynamic> ruleToc;
  final Map<String, dynamic> ruleContent;
  final Map<String, String> headers;
  final RuleEngineV2 _engine;

  // ── 内部快捷方法 ──

  String _absUrl(String path, {String? base}) =>
      _engine.urlResolver.absUrl(path, base: base, defaultBaseUrl: baseUrl);

  /// 将关键词编码为 URL-safe 形式，返回标准搜索 vars。
  Map<String, String> _searchVars(String kw, int page) => {
        'page': page.toString(),
        'key': Uri.encodeComponent(kw),
        'keyword': Uri.encodeComponent(kw),
      };

  String _resolveStr(
    String rule, {
    required dynamic context,
    required dynamic root,
    Map<String, String> vars = const {},
  }) =>
      _engine.resolveStringRule(rule, context: context, root: root, vars: vars);

  dynamic _resolveDyn(
    String rule, {
    required dynamic context,
    required dynamic root,
    Map<String, String> vars = const {},
  }) => _engine.resolveDynamic(rule, context: context, root: root, vars: vars);

  String _toStr(dynamic value) => RuleEngine.toStr(value);

  // ── 字段选取 ──

  String _pickRuleString(
    List<Map<String, dynamic>> ruleMaps,
    List<String> keys,
  ) {
    for (final ruleMap in ruleMaps) {
      for (final key in keys) {
        final rule = _toStr(ruleMap[key]);
        if (rule.isNotEmpty) return rule;
      }
    }
    return '';
  }

  String _pickField(
    dynamic context,
    dynamic root,
    List<Map<String, dynamic>> ruleMaps,
    List<String> keys, {
    Map<String, String> vars = const {},
  }) {
    for (final ruleMap in ruleMaps) {
      for (final key in keys) {
        final rule = _toStr(ruleMap[key]);
        if (rule.isEmpty) continue;
        final value = _resolveStr(
          rule,
          context: context,
          root: root,
          vars: vars,
        );
        if (value.isNotEmpty) return value;
      }
    }
    return '';
  }

  // ── 数据推导 ──

  String _deriveId(
    dynamic item,
    String detailUrl,
    String title,
    String fallbackId,
  ) {
    final map = item is Map
        ? Map<String, dynamic>.from(item)
        : <String, dynamic>{};

    for (final c in fieldId.map((k) => _toStr(RuleEngine.mapLookup(map, k)))) {
      if (c.isNotEmpty) return c;
    }

    if (detailUrl.isNotEmpty) {
      final uri = Uri.tryParse(detailUrl);
      if (uri != null) {
        for (final k in ['id', 'novelId', 'bookId']) {
          final v = uri.queryParameters[k];
          if (v != null && v.isNotEmpty) return v;
        }
      }
    }

    if (fallbackId.isNotEmpty) return fallbackId;
    if (detailUrl.isNotEmpty) return detailUrl;
    if (title.isNotEmpty) return title;
    return '';
  }

  String _deriveStatus(dynamic item) {
    final map = item is Map
        ? Map<String, dynamic>.from(item)
        : <String, dynamic>{};
    final raw = _toStr(RuleEngine.mapLookup(map, 'status'))
        .toLowerCase();
    if (raw.contains('完') || raw.contains('end') || raw.contains('finish')) {
      return '已完结';
    }
    return '连载';
  }

  String _buildCategory(dynamic item) {
    if (item is! Map) return '';
    final map = Map<String, dynamic>.from(item);
    final className = _toStr(
      RuleEngine.mapLookup(map, 'className') ??
          RuleEngine.mapLookup(map, 'classname'),
    );
    final tagName = _toStr(
      RuleEngine.mapLookup(map, 'tagName') ??
          RuleEngine.mapLookup(map, 'tagname'),
    );
    final kind = _toStr(RuleEngine.mapLookup(map, 'kind'));
    final parts = <String>[
      if (className.isNotEmpty) className,
      if (tagName.isNotEmpty && tagName != className) tagName,
    ];
    if (parts.isNotEmpty) return parts.join(' / ');
    return kind;
  }

  NovelBook? _buildBook({
    required dynamic item,
    required List<Map<String, dynamic>> ruleMaps,
    String fallbackId = '',
    String fallbackDetailUrl = '',
    String itemBaseUrl = '',
    Map<String, String> vars = const {},
  }) {
    final title = _pickField(item, item, ruleMaps, fieldBookTitle, vars: vars);
    final author = _pickField(item, item, ruleMaps, fieldAuthor, vars: vars);
    final intro = _pickField(item, item, ruleMaps, fieldIntro, vars: vars);
    final coverUrl = _pickField(item, item, ruleMaps, fieldCover, vars: vars);
    final category = _pickField(item, item, ruleMaps, fieldCategory, vars: vars);
    final wordCount = _pickField(item, item, ruleMaps, fieldWordCount, vars: vars);
    final detailRule = _pickField(item, item, ruleMaps, fieldDetailUrl, vars: vars);
    final detailUrl = detailRule.isNotEmpty ? detailRule : fallbackDetailUrl;
    final finalDetailUrl = _absUrl(
      detailUrl,
      base: itemBaseUrl.isNotEmpty ? itemBaseUrl : null,
    );
    final finalId = _deriveId(item, finalDetailUrl, title, fallbackId);
    if (finalId.isEmpty && title.isEmpty) return null;
    final status = _pickField(item, item, ruleMaps, fieldStatus, vars: vars);

    return NovelBook(
      id: finalId,
      title: title.isNotEmpty ? title : finalId,
      author: author,
      intro: _engine.cleanText(intro),
      coverUrl: _absUrl(
        coverUrl,
        base: itemBaseUrl.isNotEmpty ? itemBaseUrl : null,
      ),
      detailUrl: finalDetailUrl,
      category: category.isNotEmpty ? category : _buildCategory(item),
      status: status.isNotEmpty ? status : _deriveStatus(item),
      wordCount: wordCount,
    );
  }

  List<NovelChapter> _parseChapters(
    dynamic root, {
    dynamic init,
    required String itemBaseUrl,
  }) {
    final listRule = _pickRuleString(
      [ruleBookInfo, ruleToc],
      fieldChapterList,
    );
    if (listRule.isEmpty) return [];

    // 章节列表规则（如 "$.data.list[*]"）是绝对路径，需要从完整的 decoded 根对象解析。
    final listRoot = listRule.startsWith(r'$') ? root : (init ?? root);
    final raw = _resolveDyn(listRule, context: listRoot, root: listRoot);
    final items = raw is List ? raw : (raw is Map ? [raw] : const []);

    // 章节字段（如 "$.chapterName"）从 item 自身解析，init/root 仅作为回退上下文。
    // init 指向 extractInit 提取后的 scope（如 $.data），比完整 decoded 更精确。
    final fieldRoot = init ?? root;
    final chapterBaseUrl = _toStr(ruleToc['chapterBaseUrl']);
    final chapters = <NovelChapter>[];

    for (final item in items) {
      final titleRule = _pickRuleString(
        [ruleToc],
        fieldChapterName,
      );
      final title = titleRule.isNotEmpty
          ? _resolveStr(titleRule, context: item, root: fieldRoot)
          : _pickField(item, fieldRoot, const [], fieldChapterName);

      final chapterUrlRule = _toStr(ruleToc['chapterUrl'] ?? ruleToc['url']);
      var url = chapterUrlRule.isNotEmpty
          ? _resolveStr(chapterUrlRule, context: item, root: fieldRoot)
          : _pickField(item, fieldRoot, const [], fieldChapterUrl);

      final cleanTitle = _engine.cleanChapterTitle(title);
      url = _absUrl(
        url,
        base: chapterBaseUrl.isNotEmpty ? chapterBaseUrl : null,
      );

      if (cleanTitle.isEmpty || url.isEmpty) continue;
      chapters.add(NovelChapter(title: cleanTitle, url: url));
    }

    // 去重
    final seen = <String>{};
    final out = <NovelChapter>[];
    for (final c in chapters) {
      if (seen.add('${c.title}|${c.url}')) out.add(c);
    }
    return out;
  }

  // ── 搜索 ──

  @override
  Future<List<NovelBook>> searchBooks(String keyword, {int page = 1}) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return [];
    if (searchUrl.trim().isEmpty) return [];

    final path = _engine.renderTemplate(
      searchUrl,
      {},
      {},
      vars: _searchVars(kw, page),
    );

    final body = await _engine.request(
      path,
      defaultBaseUrl: baseUrl,
      headers: headers,
    );
    final decoded = _engine.tryDecodeJson(body);
    if (decoded == null) return [];

    final init = _engine.extractInit(decoded, ruleSearch);
    final listRule = _pickRuleString([ruleSearch], ['bookList', 'list']);

    List<dynamic> items = const [];
    if (listRule.isNotEmpty) {
      final raw = _resolveDyn(listRule, context: init, root: decoded);
      if (raw is List) {
        items = raw;
      } else if (raw is Map) {
        items = [raw];
      }
    } else {
      items = _engine.findMaps(
        init,
        (m) =>
            _toStr(m['novelName']).isNotEmpty ||
            _toStr(m['bookName']).isNotEmpty ||
            _toStr(m['title']).isNotEmpty,
      );
    }

    final books = <NovelBook>[];
    for (final item in items) {
      final book = _buildBook(
        item: item,
        ruleMaps: [ruleSearch],
        itemBaseUrl: path,
        vars: _searchVars(kw, page),
      );
      if (book != null) books.add(book);
    }

    return _uniqueBooks(books);
  }

  // ── 发现页 ──

  @override
  Future<List<NovelBook>> fetchByPath(String path) async {
    final p = path.trim();
    if (p.isEmpty) return [];

    if (p.contains('{{key}}') || p.contains('{key}')) return [];

    final body = await _engine.request(
      p,
      defaultBaseUrl: baseUrl,
      headers: headers,
    );
    final decoded = _engine.tryDecodeJson(body);
    if (decoded == null) return [];

    final activeRule = ruleExplore.isNotEmpty ? ruleExplore : ruleSearch;
    final init = _engine.extractInit(decoded, activeRule);
    final listRule = _pickRuleString([activeRule], ['bookList', 'list']);

    List<dynamic> items = const [];
    if (listRule.isNotEmpty) {
      final raw = _resolveDyn(listRule, context: init, root: decoded);
      if (raw is List) {
        items = raw;
      } else if (raw is Map) {
        items = [raw];
      }
    } else {
      items = _engine.findMaps(
        init,
        (m) =>
            _toStr(m['novelName']).isNotEmpty ||
            _toStr(m['bookName']).isNotEmpty ||
            _toStr(m['title']).isNotEmpty,
      );
    }

    final books = <NovelBook>[];
    for (final item in items) {
      final book = _buildBook(
        item: item,
        ruleMaps: [activeRule],
        itemBaseUrl: p,
      );
      if (book != null) books.add(book);
    }

    return _uniqueBooks(books);
  }

  // ── 详情 ──

  @override
  Future<NovelDetail> fetchDetail({
    required String bookId,
    String? detailUrl,
  }) async {
    final path = detailUrl?.trim() ?? bookId;
    if (path.isEmpty) {
      return NovelDetail(
        book: NovelBook(
          id: bookId,
          title: bookId,
          author: '',
          intro: '',
          coverUrl: '',
          detailUrl: '',
        ),
        chapters: [],
      );
    }

    final body = await _engine.request(
      path,
      defaultBaseUrl: baseUrl,
      headers: headers,
    );
    final decoded = _engine.tryDecodeJson(body);
    if (decoded == null) {
      return NovelDetail(
        book: NovelBook(
          id: bookId,
          title: bookId,
          author: '',
          intro: '',
          coverUrl: '',
          detailUrl: path,
        ),
        chapters: [],
      );
    }

    final init = _engine.extractInit(decoded, ruleBookInfo);

    final title = _pickField(
      init,
      decoded,
      [ruleBookInfo],
      ['name', 'title', 'novelName', 'bookName'],
    );
    final author = _pickField(
      init,
      decoded,
      [ruleBookInfo],
      ['author', 'authorName'],
    );
    final intro = _pickField(
      init,
      decoded,
      [ruleBookInfo],
      ['intro', 'summary', 'desc'],
    );
    final coverUrl = _pickField(
      init,
      decoded,
      [ruleBookInfo],
      ['coverUrl', 'cover', 'img', 'thumb'],
    );
    final category = _pickField(
      init,
      decoded,
      [ruleBookInfo],
      ['category', 'kind', 'className'],
    );
    final wordCount = _pickField(
      init,
      decoded,
      [ruleBookInfo],
      ['wordCount', 'wordNum'],
    );
    final status = _pickField(init, decoded, [ruleBookInfo], ['status']);

    final book = NovelBook(
      id: _deriveId(init, path, title, bookId),
      title: title.isNotEmpty ? title : bookId,
      author: author,
      intro: _engine.cleanText(intro),
      coverUrl: _absUrl(coverUrl),
      detailUrl: path,
      category: category,
      status: status,
      wordCount: wordCount,
    );

    // 目录解析需要完整的 decoded 根对象（因为 ruleToc.chapterList = "$.data.list[*]" 是绝对路径），
    // 同时章节字段提取需要 init（已 scope 到 $.data）作为回退上下文。
    var chapters = _parseChapters(decoded, init: init, itemBaseUrl: path);

    // 有些书源把目录放在独立接口上（ruleBookInfo.tocUrl），详情响应里根本没有
    // 章节数据 —— 此时必须再请求一次目录接口，否则章节列表永远为空。
    // 实例：猫眼看书（优++）http://api.lfdapengu.com，搜索/详情均正常但目录空。
    if (chapters.isEmpty) {
      final tocChapters = await _fetchTocChapters(
        init: init,
        root: decoded,
        detailPath: path,
      );
      if (tocChapters.isNotEmpty) chapters = tocChapters;
    }

    return NovelDetail(book: book, chapters: chapters);
  }

  /// 请求 `ruleBookInfo.tocUrl` 指向的独立目录接口并解析章节。
  ///
  /// 适用于详情与目录分离的书源：详情响应只含书籍元信息，章节列表需要另取。
  /// tocUrl 支持模板变量（如 `/toc?novelId={{$.tocId}}`），用详情响应渲染。
  /// 目录接口失败不应让整个详情页报错，因此这里吞掉异常返回空列表。
  Future<List<NovelChapter>> _fetchTocChapters({
    required dynamic init,
    required dynamic root,
    required String detailPath,
  }) async {
    // tocUrl 按 Legado 约定只出现在 ruleBookInfo；不查 ruleToc，避免误取
    // ruleToc.chapterUrl（那是单章链接规则）当作目录接口。
    final tocRule = _pickRuleString([ruleBookInfo], fieldTocUrl);
    if (tocRule.isEmpty) return const [];

    try {
      // tocUrl 是 URL 模板（如 /toc?novelId={{$.tocId}}），先渲染 {{}} 占位符。
      var tocPath = _engine.renderTemplate(tocRule, init, root);

      // 若整条规则本身就是纯 JSONPath（如 $.tocUrl，服务端直接给出目录地址），
      // 渲染后仍是原样，此时按 JSONPath 求值。
      if (tocPath == tocRule && tocRule.startsWith(r'$')) {
        tocPath = _resolveStr(tocRule, context: init, root: root);
      }
      if (tocPath.trim().isEmpty) return const [];

      final tocBody = await _engine.request(
        tocPath,
        defaultBaseUrl: baseUrl,
        headers: headers,
      );
      final tocDecoded = _engine.tryDecodeJson(tocBody);
      if (tocDecoded == null) return const [];

      final tocInit = _engine.extractInit(tocDecoded, ruleToc);
      return _parseChapters(
        tocDecoded,
        init: tocInit,
        itemBaseUrl: tocPath,
      );
    } catch (_) {
      // 目录接口不可用时优雅退化：保留书籍信息，章节留空
      return const [];
    }
  }

  // ── 章节内容 ──

  @override
  Future<ChapterContent> fetchChapter({
    required NovelDetail detail,
    required int chapterIndex,
  }) async {
    if (chapterIndex < 0 || chapterIndex >= detail.chapters.length) {
      throw RangeError.index(chapterIndex, detail.chapters);
    }

    final chapter = detail.chapters[chapterIndex];
    final url = chapter.url.trim();
    if (url.isEmpty) {
      return ChapterContent(
        title: chapter.title,
        content: '章节链接为空',
        chapterIndex: chapterIndex,
        sourceUrl: url,
      );
    }

    final body = await _engine.request(
      url,
      defaultBaseUrl: baseUrl,
      headers: headers,
    );
    final decoded = _engine.tryDecodeJson(body);

    String rawContent;
    if (decoded != null) {
      final init = _engine.extractInit(decoded, ruleContent);
      final contentRule = _pickRuleString([ruleContent], ['content']);
      if (contentRule.isNotEmpty) {
        rawContent = _resolveStr(contentRule, context: init, root: decoded);
      } else {
        rawContent = _pickField(
          init,
          decoded,
          [ruleContent],
          ['content', 'text', 'body'],
        );
      }

      if (rawContent.isEmpty) {
        rawContent = decoded.toString();
      }
    } else {
      rawContent = body;
    }

    final content = _cleanContent(rawContent, url);

    return ChapterContent(
      title: chapter.title,
      content: content,
      chapterIndex: chapterIndex,
      sourceUrl: url,
    );
  }

  String _cleanContent(String content, String chapterUrl) {
    var text = content;

    final replaceRegex = _toStr(ruleContent['replaceRegex']).trim();
    if (replaceRegex.isNotEmpty) {
      final pattern = replaceRegex.startsWith('##')
          ? replaceRegex.substring(2)
          : replaceRegex;
      if (pattern.isNotEmpty) {
        text = _engine.regexApplier.applyRegexReplacement(text, pattern, '');
      }
    }

    // 注意：不能用 _engine.cleanText（TextCleaner.cleanRaw），它把 `\s+`
    // 折叠成单空格，而 `\s` 包含 `\n` —— 正文的段落换行会被全部消灭，
    // 整章挤成一行。正文必须走 stripHtml/normalizeWhitespace 这条保留换行的
    // 路径（cleanRaw 只适合书名、作者这类单行字段）。
    text = TextCleaner.normalizeParagraphs(text);

    final lines = text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return lines.join('\n\n').trim();
  }

  // ── 工具 ──

  List<NovelBook> _uniqueBooks(List<NovelBook> books) =>
      BookDeduplicator.deduplicate(books);
}
