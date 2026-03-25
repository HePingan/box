import 'dart:async';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import 'models.dart';
import 'novel_source.dart';
import 'source_rules.dart';

class HtmlNovelSource implements NovelSource {
  HtmlNovelSource({
    required this.baseUrl,
    required this.rules,
    Map<String, String>? headers,
  }) : headers = headers ?? const {
              'User-Agent': 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
              'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
            };

  final String baseUrl;
  final SourceRules rules;
  final Map<String, String> headers;

  Uri _resolve(String urlOrPath) {
    if (urlOrPath.startsWith('http://') || urlOrPath.startsWith('https://')) {
      return Uri.parse(urlOrPath);
    }
    return Uri.parse(baseUrl).resolve(urlOrPath);
  }

  String _absUrl(String value) {
    if (value.trim().isEmpty) return '';
    return _resolve(value).toString();
  }

  Future<dom.Document> _fetchDoc(String urlOrPath) async {
    // 加入 timeout 防止挂死
    final response = await http.get(_resolve(urlOrPath), headers: headers).timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('网络请求失败: ${response.statusCode}');
    }
    return html_parser.parse(response.body);
  }

  dom.Element? _first(dynamic root, List<String> selectors) {
    for (final selector in selectors) {
      final node = root.querySelector(selector);
      if (node != null) return node;
    }
    return null;
  }

  List<dom.Element> _all(dynamic root, List<String> selectors) {
    for (final selector in selectors) {
      final nodes = root.querySelectorAll(selector);
      if (nodes.isNotEmpty) return nodes;
    }
    return const <dom.Element>[];
  }

  String _text(dynamic root, List<String> selectors, {String fallback = ''}) {
    final value = _first(root, selectors)?.text.trim() ?? '';
    return value.isEmpty ? fallback : value;
  }

  String _attr(dynamic root, List<String> selectors, String name) {
    for (final selector in selectors) {
      final value = root.querySelector(selector)?.attributes[name]?.trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _deriveId(String href) {
    if (href.trim().isEmpty) return '';
    final uri = Uri.parse(_absUrl(href));
    final segments = uri.pathSegments.where((e) => e.trim().isNotEmpty).toList();
    if (segments.isEmpty) return href;
    return segments.last;
  }

  bool _isValidChapterLink(String title, String href) {
    if (title.isEmpty || href.isEmpty || href == '#' || href.startsWith('javascript:')) return false;
    if (RegExp(r'^(上一章|下一章|目录|首页|返回|书架|登录)$').hasMatch(title)) return false;
    return true;
  }

  String _cleanContent(String html) {
    var text = html.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
                   .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
                   .replaceAll(RegExp(r'<p[^>]*>', caseSensitive: false), '')
                   .replaceAll(RegExp(r'<script.*?</script>', caseSensitive: false, dotAll: true), '')
                   .replaceAll(RegExp(r'<style.*?</style>', caseSensitive: false, dotAll: true), '')
                   .replaceAll(RegExp(r'<[^>]+>'), '');

    final decoded = html_parser.parseFragment(text).text ?? '';
    final lines = decoded.replaceAll('\u00A0', ' ').replaceAll('\r\n', '\n').split('\n');
    final result = <String>[];
    final noisePatterns = [RegExp(r'^\s*$'), RegExp(r'^请收藏'), RegExp(r'^最新章节'), RegExp(r'^本章未完'), RegExp(r'^广告'), RegExp(r'^手机用户请'), RegExp(r'^下载.*阅读')];

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) {
        if (result.isNotEmpty && result.last != '') result.add('');
        continue;
      }
      if (noisePatterns.any((p) => p.hasMatch(line))) continue;
      result.add(line);
    }
    // 移除连续多行空行
    return result.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  /// 公共抽取的列表解析逻辑
  List<NovelBook> _parseBookListFromDoc(dom.Document doc) {
    final items = _all(doc, rules.searchItemSelectors);
    final books = <NovelBook>[];

    for (final item in items) {
      final linkNode = _first(item, rules.searchLinkSelectors) ?? item.querySelector('a');
      if (linkNode == null) continue;

      final href = linkNode.attributes['href']?.trim() ?? '';
      if (href.isEmpty) continue;

      final title = _text(item, rules.searchTitleSelectors, fallback: linkNode.text.trim());
      if (title.isEmpty) continue;

      books.add(NovelBook(
        id: _deriveId(href),
        title: title,
        author: _text(item, rules.searchAuthorSelectors, fallback: '未知作者'),
        intro: _text(item, rules.searchIntroSelectors),
        coverUrl: _absUrl(_attr(item, rules.searchCoverSelectors, 'src')),
        detailUrl: _absUrl(href),
        category: _text(item, rules.searchCategorySelectors),
        status: _text(item, rules.searchStatusSelectors),
        wordCount: _text(item, rules.searchWordCountSelectors),
      ));
    }
    return books;
  }

  // 1. 修复：补充了缺失的 searchBooks 可选参数 {int page = 1}
  @override
  Future<List<NovelBook>> searchBooks(String keyword, {int page = 1}) async {
    final doc = await _fetchDoc(rules.searchPathBuilder(keyword));
    return _parseBookListFromDoc(doc);
  }

  // 2. 修复：补充了缺失的 fetchByPath 实现
  @override
  Future<List<NovelBook>> fetchByPath(String path) async {
    final doc = await _fetchDoc(path);
    return _parseBookListFromDoc(doc);
  }

  // 3. 修复：恢复了与接口一致的命名参数 {required String bookId, String? detailUrl}
  @override
  Future<NovelDetail> fetchDetail({
    required String bookId,
    String? detailUrl,
  }) async {
    // 优先使用给定的详情页 URL 进行请求
    final requestUrl = detailUrl != null && detailUrl.isNotEmpty 
        ? detailUrl 
        : rules.detailPathBuilder(bookId);

    final doc = await _fetchDoc(requestUrl);

    final book = NovelBook(
      id: bookId,
      title: _text(doc, rules.detailTitleSelectors, fallback: '未知书名'),
      author: _text(doc, rules.detailAuthorSelectors, fallback: '未知作者'),
      intro: _text(doc, rules.detailIntroSelectors),
      coverUrl: _absUrl(_attr(doc, rules.detailCoverSelectors, 'src')),
      detailUrl: _absUrl(requestUrl),
      category: _text(doc, rules.detailCategorySelectors),
      status: _text(doc, rules.detailStatusSelectors),
      wordCount: _text(doc, rules.detailWordCountSelectors),
    );

    final chapterRoot = _first(doc, rules.chapterListSelectors) ?? doc;
    final seen = <String>{};
    final chapters = <NovelChapter>[];

    for (final a in chapterRoot.querySelectorAll('a')) {
      final href = a.attributes['href']?.trim() ?? '';
      final title = a.text.trim();

      if (!_isValidChapterLink(title, href)) continue;

      final url = _absUrl(href);
      if (seen.add(url)) {
        chapters.add(NovelChapter(title: title, url: url));
      }
    }

    return NovelDetail(book: book, chapters: chapters);
  }

  @override
  Future<ChapterContent> fetchChapter({
    required NovelDetail detail,
    required int chapterIndex,
  }) async {
    if (chapterIndex < 0 || chapterIndex >= detail.chapters.length) {
      throw RangeError('章节索引越界');
    }

    final chapter = detail.chapters[chapterIndex];
    final doc = await _fetchDoc(chapter.url);

    final title = _text(doc, rules.chapterTitleSelectors, fallback: chapter.title);
    final contentNode = _first(doc, rules.contentSelectors);

    if (contentNode == null) {
      throw Exception('未找到正文节点，请调整 contentSelectors');
    }

    final content = _cleanContent(contentNode.innerHtml);
    if (content.isEmpty) {
      throw Exception('正文解析为空，请调整 contentSelectors 或清洗规则');
    }

    return ChapterContent(
      title: title,
      content: content,
      chapterIndex: chapterIndex,
      sourceUrl: chapter.url,
    );
  }
}