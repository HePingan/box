import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;
import 'package:http/http.dart' as http;

import '../core/models.dart';
import '../core/novel_exceptions.dart';
import 'novel_source.dart';
import 'rules/css_selector_parser.dart';

/// 快眼看书（优+）专用书源实现
///
/// 特点：
/// - 搜索/列表/详情/章节均为 HTML 页面（非 JSON）
/// - 规则采用 Legado 标准 class/tag 选择器格式
class KuaiYanNovelSource implements NovelSource {
  KuaiYanNovelSource({
    String? name,
    String? baseUrl,
    String? searchUrl,
    String? exploreUrl,
    Map<String, dynamic>? ruleSearch,
    Map<String, dynamic>? ruleBookInfo,
    Map<String, dynamic>? ruleToc,
    Map<String, dynamic>? ruleContent,
    Map<String, String>? headers,
  })  : name = (name ?? '').trim(),
        baseUrl = (baseUrl ?? '').trim().replaceAll(RegExp(r'/+$'), ''),
        searchUrl = (searchUrl ?? '').trim(),
        exploreUrl = (exploreUrl ?? '').trim(),
        ruleSearch = ruleSearch ?? const <String, dynamic>{},
        ruleBookInfo = ruleBookInfo ?? const <String, dynamic>{},
        ruleToc = ruleToc ?? const <String, dynamic>{},
        ruleContent = ruleContent ?? const <String, dynamic>{},
        headers = {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          if (headers != null) ...headers,
        };

  factory KuaiYanNovelSource.fromBookSourceJson(Map<String, dynamic> json) {
    return KuaiYanNovelSource(
      name: '${json['bookSourceName'] ?? ''}',
      baseUrl: '${json['bookSourceUrl'] ?? ''}',
      searchUrl: '${json['searchUrl'] ?? ''}',
      exploreUrl: '${json['exploreUrl'] ?? ''}',
      ruleSearch: _asMap(json['ruleSearch']),
      ruleBookInfo: _asMap(json['ruleBookInfo']),
      ruleToc: _asMap(json['ruleToc']),
      ruleContent: _asMap(json['ruleContent']),
      headers: _asStringMap(json['header']),
    );
  }

  static bool supportsBookSourceJson(Map<String, dynamic> json) {
    final url = '${json['bookSourceUrl'] ?? ''}'.toLowerCase();
    final name = '${json['bookSourceName'] ?? ''}';
    return url.contains('xbotaodz.com') || name.contains('快眼看书');
  }

  static Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  static Map<String, String>? _asStringMap(dynamic v) {
    if (v == null) return null;
    if (v is Map<String, String>) return v;
    if (v is Map) {
      return Map<String, String>.fromEntries(
        v.entries.where((e) => e.value is String).map(
              (e) => MapEntry(e.key.toString(), e.value.toString()),
            ),
      );
    }
    return null;
  }

  // ── 基础配置 ──

  final String name;
  final String baseUrl;
  final String searchUrl;
  final String exploreUrl;
  final Map<String, dynamic> ruleSearch;
  final Map<String, dynamic> ruleBookInfo;
  final Map<String, dynamic> ruleToc;
  final Map<String, dynamic> ruleContent;
  final Map<String, String> headers;

  // ── 网络请求 ──

  Future<String> _get(String path) async {
    if (path.startsWith('data:')) {
      throw NovelException(
        '当前书源不支持该书籍格式，正在尝试重新匹配…',
      );
    }
    final uri = path.startsWith('http://') || path.startsWith('https://')
        ? Uri.parse(path)
        : Uri.parse('$baseUrl$path');
    final resp = await http.get(uri, headers: headers).timeout(
      const Duration(seconds: 15),
    );
    if (resp.statusCode != 200) {
      throw NovelException('HTTP ${resp.statusCode}: $uri');
    }
    return _decodeBody(resp);
  }

  /// 从 HTTP 响应中提取字符编码并正确解码
  ///
  /// 优先级：
  /// 1. Content-Type header 中的 charset
  /// 2. HTML <meta charset> / <meta http-equiv Content-Type>
  /// 3. 默认 UTF-8（现代网站绝大部分是 UTF-8）
  String _decodeBody(http.Response resp) {
    // 1. Content-Type charset
    final ctCharset = _charsetFromContentType(resp.headers['content-type']);
    if (ctCharset != null) {
      try {
        return _decodeWith(resp.bodyBytes, ctCharset);
      } catch (_) {}
    }

    // 2. HTML <meta> charset —— 用 Latin-1 扫描前 3KB 找 meta 声明
    try {
      final head = latin1.decode(resp.bodyBytes.take(3072).toList());
      final metaCharset = _charsetFromMeta(head);
      if (metaCharset != null) {
        return _decodeWith(resp.bodyBytes, metaCharset);
      }
    } catch (_) {}

    // 3. 兜底 UTF-8（比 latin1 更合理）
    try {
      return utf8.decode(resp.bodyBytes);
    } catch (_) {
      return latin1.decode(resp.bodyBytes);
    }
  }

  static String? _charsetFromContentType(String? contentType) {
    if (contentType == null) return null;
    final cs = RegExp(r'charset\s*=\s*([^\s;]+)', caseSensitive: false)
        .firstMatch(contentType)
        ?.group(1);
    return cs?.trim().toLowerCase();
  }

  static String? _charsetFromMeta(String headHtml) {
    // <meta charset="utf-8">
    final m1 = RegExp(
      r'<meta\s+charset\s*=\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(headHtml);
    if (m1 != null) return m1.group(1)!.toLowerCase();

    // <meta charset='utf-8'>
    final m1b = RegExp(
      r"<meta\s+charset\s*=\s*'([^']+)'",
      caseSensitive: false,
    ).firstMatch(headHtml);
    if (m1b != null) return m1b.group(1)!.toLowerCase();

    // <meta charset=utf-8>
    final m1c = RegExp(
      r'<meta\s+charset\s*=\s*([^\s>"=]+)',
      caseSensitive: false,
    ).firstMatch(headHtml);
    if (m1c != null) return m1c.group(1)!.toLowerCase();

    // <meta http-equiv="Content-Type" content="...; charset=xxx">
    final httpEquiv = RegExp(
      r'<meta\s[^>]*http-equiv\s*=\s*"Content-Type"[^>]*>',
      caseSensitive: false,
    ).firstMatch(headHtml);
    if (httpEquiv != null) {
      final seg = httpEquiv.group(0)!;
      final cs = RegExp(
        r'charset\s*=\s*([^\s;">]+)',
        caseSensitive: false,
      ).firstMatch(seg)?.group(1);
      if (cs != null && cs.isNotEmpty) return cs.toLowerCase();
    }

    return null;
  }

  static String _decodeWith(List<int> bytes, String charset) {
    final encoding = _encodingForName(charset);
    return encoding.decode(bytes);
  }

  static Encoding _encodingForName(String name) {
    if (name == 'utf-8' || name == 'utf8') return utf8;
    if (name == 'ascii') return ascii;
    return latin1; // fallback
  }

  // ── CSS 规则解析 ──

  String _pickRule(
    Map<String, dynamic> rules,
    List<String> keys, {
    String? defaultVal,
  }) {
    for (final k in keys) {
      final v = rules[k];
      if (v is String && v.isNotEmpty) return v;
    }
    return defaultVal ?? '';
  }

  String _extractHtml(String html, String? rule) {
    if (rule == null || rule.isEmpty) return '';
    return CssSelectorParser.parse(rule, html) ?? '';
  }

  List<Element> _extractList(String html, String rule) {
    final doc = parse(html);
    final segments = rule.split('@').map((s) => s.trim()).toList();
    List<Element> candidates = doc.body?.nodes.whereType<Element>().toList() ?? [];

    for (final seg in segments) {
      if (seg.isEmpty) continue;
      final next = <Element>[];
      for (final el in candidates) {
        CssSelectorParser.selectInto(el, seg, next);
      }
      candidates = next;
      if (candidates.isEmpty) return <Element>[];
    }
    return candidates;
  }

  // ── NovelSource 实现 ──

  @override
  Future<List<NovelBook>> searchBooks(String keyword, {int page = 1}) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return <NovelBook>[];
    final path = searchUrl.replaceFirst('{{key}}', Uri.encodeComponent(kw));
    final html = await _get(path);

    final bookListRule = _pickRule(ruleSearch, ['bookList', 'list']);
    final items = <Element>[];
    if (bookListRule.isNotEmpty) {
      items.addAll(_extractList(html, bookListRule));
    }

    final books = <NovelBook>[];
    for (final el in items) {
      final book = _buildBookFromElement(el, ruleSearch, '$baseUrl$path');
      if (book != null) books.add(book);
    }
    return _uniqueBooks(books);
  }

  // ignore: override_on_non_overriding_member
  @override
  Future<List<NovelBook>> fetchByPath(String path) async {
    if (path.isEmpty) return <NovelBook>[];
    final html = await _get(path);

    final bookListRule = _pickRule(ruleSearch, ['bookList', 'list']);
    final items = <Element>[];
    if (bookListRule.isNotEmpty) {
      items.addAll(_extractList(html, bookListRule));
    }

    final books = <NovelBook>[];
    for (final el in items) {
      final book = _buildBookFromElement(el, ruleSearch, path);
      if (book != null) books.add(book);
    }
    return _uniqueBooks(books);
  }

  @override
  Future<NovelDetail> fetchDetail({
    required String bookId,
    String? detailUrl,
  }) async {
    final url = detailUrl ?? bookId;
    final html = await _get(url);

    final title = _extractHtml(html, _pickRule(ruleBookInfo, ['name']));
    final author = _extractHtml(html, _pickRule(ruleBookInfo, ['author']));
    final intro = _extractHtml(html, _pickRule(ruleBookInfo, ['intro']));
    final cover = _extractHtml(html, _pickRule(ruleBookInfo, ['coverUrl']));

    final chapters = await fetchChapters(detailUrl: url);

    return NovelDetail(
      book: NovelBook(
        id: url,
        title: title.isEmpty ? '未知书名' : title,
        author: author,
        intro: intro,
        coverUrl: _abs(cover),
        detailUrl: url,
        category: '',
        status: '',
        wordCount: '',
      ),
      chapters: chapters,
    );
  }

  Future<List<NovelChapter>> fetchChapters({
    required String detailUrl,
  }) async {
    final html = await _get(detailUrl);
    final tocRule = _pickRule(ruleToc, ['chapterList']);
    if (tocRule.isEmpty) return <NovelChapter>[];

    final items = _extractList(html, tocRule);
    final chapters = <NovelChapter>[];
    final seen = <String>{};

    for (final el in items) {
      final t = _elementText(el);
      final href = el.attributes['href'] ?? '';
      if (t.isEmpty || href.isEmpty) continue;
      final key = '$t|$href';
      if (!seen.add(key)) continue;
      chapters.add(NovelChapter(title: t, url: _abs(href)));
    }
    return chapters;
  }

  @override
  Future<ChapterContent> fetchChapter({
    required NovelDetail detail,
    required int chapterIndex,
  }) async {
    if (chapterIndex < 0 || chapterIndex >= detail.chapters.length) {
      return ChapterContent(
        title: '',
        content: '章节索引越界',
        chapterIndex: chapterIndex,
        sourceUrl: '',
      );
    }

    final ch = detail.chapters[chapterIndex];
    final html = await _get(ch.url);
    final contentRule = _pickRule(ruleContent, ['content']);

    String content;
    if (contentRule.isEmpty) {
      content = _parseBodyText(html);
    } else if (contentRule.contains('textNodes')) {
      content = _parseTextNodes(html, contentRule);
    } else {
      content = _extractHtml(html, contentRule);
    }

    return ChapterContent(
      title: ch.title,
      content: content.trim(),
      chapterIndex: chapterIndex,
      sourceUrl: ch.url,
    );
  }

  // ── 内部工具 ──

  NovelBook? _buildBookFromElement(
    Element el,
    Map<String, dynamic> rules,
    String baseHref,
  ) {
    final fragment = el.outerHtml;
    final title = _extractHtml(fragment, _pickRule(rules, ['name']));
    if (title.isEmpty) return null;

    final author = _extractHtml(fragment, _pickRule(rules, ['author']));
    final cover = _extractHtml(fragment, _pickRule(rules, ['coverUrl']));
    final url = _extractHtml(fragment, _pickRule(rules, ['bookUrl']));
    final last = _extractHtml(fragment, _pickRule(rules, ['lastChapter']));

    return NovelBook(
      id: url.isEmpty ? title : url,
      title: title,
      author: author,
      intro: '',
      coverUrl: _abs(cover),
      detailUrl: _abs(url),
      category: '',
      status: last,
      wordCount: '',
    );
  }

  String _abs(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    if (path.startsWith('//')) return 'https:$path';
    // 用 Uri.resolve 正确解析相对路径
    return Uri.parse(baseUrl).resolve(path).toString();
  }

  static String _elementText(Element el) => el.text.trim();

  static String _parseBodyText(String html) {
    final doc = parse(html);
    final body = doc.body;
    if (body == null) return '';
    final buffer = StringBuffer();
    _extractTextRecursive(body, buffer);
    return buffer.toString().trim();
  }

  /// 递归提取文本，块级元素后插入换行
  static void _extractTextRecursive(Node node, StringBuffer buffer) {
    if (node is Text) {
      buffer.write(node.text);
      return;
    }
    if (node is Element) {
      final tag = node.localName?.toLowerCase() ?? '';
      final isBlock = _blockTags.contains(tag);
      final isBr = tag == 'br';

      if (isBr) {
        buffer.write('\n');
        return;
      }

      // 块级元素：在内容前插入换行（除非在开头）
      if (isBlock && buffer.isNotEmpty && !buffer.toString().endsWith('\n')) {
        buffer.write('\n');
      }

      for (final child in node.nodes) {
        _extractTextRecursive(child, buffer);
      }
    }
  }

  static const Set<String> _blockTags = {
    'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
    'li', 'ol', 'ul', 'blockquote', 'section', 'article',
    'nav', 'header', 'footer', 'aside', 'main', 'figure',
    'figcaption', 'details', 'summary', 'pre', 'hr',
  };

  static String _parseTextNodes(String html, String rule) {
    final segs = rule.split('@').map((s) => s.trim()).toList();
    final doc = parse(html);
    List<Element> candidates = doc.body?.nodes.whereType<Element>().toList() ?? [];

    for (final seg in segs) {
      if (seg == 'textNodes') break;
      if (seg.isEmpty) continue;
      final next = <Element>[];
      for (final el in candidates) {
        CssSelectorParser.selectInto(el, seg, next);
      }
      candidates = next;
      if (candidates.isEmpty) return '';
    }

    final buffer = StringBuffer();
    for (final el in candidates) {
      for (final node in el.nodes) {
        if (node is Text) buffer.write(node.text);
      }
    }
    return buffer.toString().trim();
  }

  static List<NovelBook> _uniqueBooks(List<NovelBook> books) {
    final seen = <String>{};
    final out = <NovelBook>[];
    for (final b in books) {
      final key = b.detailUrl.isNotEmpty ? b.detailUrl : b.id;
      if (key.isEmpty || seen.add(key)) out.add(b);
    }
    return out;
  }
}
