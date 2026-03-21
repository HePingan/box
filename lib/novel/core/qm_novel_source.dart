import 'dart:convert';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import 'models.dart';
import 'novel_source.dart';

class QmNovelSource implements NovelSource {
  QmNovelSource({
    required this.baseUrl,
    Map<String, String>? headers,
  }) : headers = headers ??
            const {
              'User-Agent': 'okhttp/4.9.2',
            };

  final String baseUrl;
  final Map<String, String> headers;

  // ruleToc.chapterName 的清洗规则
  static final RegExp _chapterTitleCleaner = RegExp(
    r'正文卷\.|正文\.|VIP卷\.|默认卷\.|卷_|VIP章节\.|免费章节\.|章节目录\.|最新章节\.|[\(（【].*?[求更票谢乐发订合补加架字修Kk].*?[】）\)]',
  );

  // ruleContent.replaceRegex
  static final RegExp _contentNoiseCleaner = RegExp(r'一秒记住.*精彩阅读。|7017k');

  Uri _resolve(String pathOrUrl) {
    final value = pathOrUrl.trim();
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return Uri.parse(value);
    }
    return Uri.parse(baseUrl).resolve(value);
  }

  String _absUrl(String value) {
    final text = value.trim();
    if (text.isEmpty) return '';
    try {
      return _resolve(text).toString();
    } catch (_) {
      return text;
    }
  }

  Future<String> _fetchBody(String pathOrUrl) async {
    final response = await http.get(_resolve(pathOrUrl), headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode} @ $pathOrUrl');
    }
    return response.body;
  }

  dynamic _tryDecodeJson(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _toMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  List<Map<String, dynamic>> _toMapList(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value.map(_toMap).whereType<Map<String, dynamic>>().toList();
  }

  String _string(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }

  Map<String, dynamic> _lowerMap(Map<String, dynamic> raw) {
    final out = <String, dynamic>{};
    raw.forEach((k, v) {
      out[k.toString().toLowerCase()] = v;
    });
    return out;
  }

  String _pick(Map<String, dynamic> lowerMap, List<String> keys, {String fallback = ''}) {
    for (final key in keys) {
      final value = lowerMap[key.toLowerCase()];
      final text = _string(value);
      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }
    return fallback;
  }

  bool _isBookMap(Map<String, dynamic> raw) {
    final map = _lowerMap(raw);
    final name = _pick(map, ['novelname', 'bookname', 'title', 'name']);
    final id = _pick(map, ['novelid', 'bookid', 'id']);
    final summary = _pick(map, ['summary', 'intro', 'desc']);
    return name.isNotEmpty && (id.isNotEmpty || summary.isNotEmpty);
  }

  bool _isChapterMap(Map<String, dynamic> raw) {
    final map = _lowerMap(raw);
    final title = _pick(map, ['chaptername', 'chaptertitle', 'title', 'name']);
    final path = _pick(map, ['path', 'chapterurl', 'url', 'href']);
    return title.isNotEmpty && path.isNotEmpty;
  }

  List<Map<String, dynamic>> _findMaps(
    dynamic node,
    bool Function(Map<String, dynamic>) matcher,
  ) {
    final out = <Map<String, dynamic>>[];

    void walk(dynamic current) {
      final map = _toMap(current);
      if (map != null) {
        if (matcher(map)) out.add(map);
        for (final v in map.values) {
          if (v is Map || v is List) walk(v);
        }
        return;
      }

      if (current is List) {
        for (final item in current) {
          if (item is Map || item is List) walk(item);
        }
      }
    }

    walk(node);
    return out;
  }

  String _extractTag(dynamic value) {
    if (value == null) return '';

    if (value is List) {
      final parts = value.map(_extractTag).where((e) => e.isNotEmpty).toList();
      return parts.join('/');
    }

    if (value is Map) {
      final map = _lowerMap(Map<String, dynamic>.from(value));
      final direct = _pick(map, ['tagname', 'name', 'title']);
      if (direct.isNotEmpty) return direct;
      final parts = map.values.map(_extractTag).where((e) => e.isNotEmpty).toList();
      return parts.join('/');
    }

    return _string(value);
  }

  String _normalizeStatus(dynamic value) {
    final text = _string(value);
    if (text.isEmpty) return '';
    final lower = text.toLowerCase();

    if (lower == '1' || lower == 'true' || text.contains('完')) return '完结';
    if (lower == '0' || lower == 'false' || text.contains('连')) return '连载';
    return text;
  }

  String _normalizeWordCount(dynamic value) {
    final text = _string(value);
    if (text.isEmpty) return '';

    final number = int.tryParse(text);
    if (number == null) return text;
    if (number >= 10000) {
      final wan = number / 10000;
      final fixed = wan >= 100 ? wan.toStringAsFixed(0) : wan.toStringAsFixed(1);
      return '${fixed}万字';
    }
    return '$number字';
  }

  String _extractNovelIdFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';

    final queryId =
        uri.queryParameters['novelId'] ?? uri.queryParameters['bookId'] ?? uri.queryParameters['id'];
    if (queryId != null && queryId.trim().isNotEmpty) return queryId.trim();

    final segments = uri.pathSegments.where((e) => e.trim().isNotEmpty).toList();
    if (segments.isEmpty) return '';

    final novelIndex = segments.indexOf('novel');
    if (novelIndex >= 0 && novelIndex + 1 < segments.length) {
      return segments[novelIndex + 1];
    }

    return segments.last;
  }

  NovelBook? _bookFromMap(
    Map<String, dynamic> raw, {
    String fallbackId = '',
    String sourcePath = '',
  }) {
    final map = _lowerMap(raw);

    var id = _pick(map, ['novelid', 'bookid', 'id']);
    var title = _pick(map, ['novelname', 'bookname', 'title', 'name']);

    final author = _pick(map, ['authorname', 'author', 'writer']);
    final intro = _pick(map, ['summary', 'intro', 'description', 'desc']);

    final coverUrl = _absUrl(_pick(map, ['cover', 'coverurl', 'image', 'img', 'pic', 'thumb']));

    var detailUrl = _pick(map, ['bookurl', 'detailurl', 'url', 'href']);
    if (detailUrl.isEmpty && id.isNotEmpty) {
      detailUrl = '/novel/$id?isSearch=1';
    }
    if (detailUrl.isEmpty && sourcePath.isNotEmpty) {
      detailUrl = sourcePath;
    }
    detailUrl = _absUrl(detailUrl);

    if (id.isEmpty && detailUrl.isNotEmpty) {
      id = _extractNovelIdFromUrl(detailUrl);
    }
    if (id.isEmpty) id = fallbackId;

    if (title.isEmpty && id.isNotEmpty) {
      title = id;
    }

    if (id.isEmpty && title.isEmpty) return null;

    var tag = _extractTag(map['tagname']);
    if (tag.isEmpty) tag = _extractTag(map['taglist']);
    if (tag.isEmpty) tag = _extractTag(map['tags']);

    final className = _pick(map, ['classname', 'class_name', 'categoryname', 'category']);
    final categoryParts = <String>[
      if (className.isNotEmpty) className,
      if (tag.isNotEmpty) tag,
    ];

    return NovelBook(
      id: id,
      title: title,
      author: author,
      intro: intro,
      coverUrl: coverUrl,
      detailUrl: detailUrl,
      category: categoryParts.join(' / '),
      status: _normalizeStatus(map['iscomplete'] ?? map['status']),
      wordCount: _normalizeWordCount(map['wordnum'] ?? map['wordcount'] ?? map['words']),
    );
  }

  String _cleanChapterTitle(String raw) {
    final title = raw.trim();
    if (title.isEmpty) return '';
    final cleaned = title.replaceAll(_chapterTitleCleaner, '').trim();
    return cleaned.isEmpty ? title : cleaned;
  }

  String _normalizeBase64(String value) {
    var text = value.trim().replaceAll(' ', '+').replaceAll('-', '+').replaceAll('_', '/');
    final mod = text.length % 4;
    if (mod != 0) {
      text = text.padRight(text.length + (4 - mod), '=');
    }
    return text;
  }

  String? _decryptAesPath(String encrypted) {
    try {
      final key = enc.Key.fromUtf8('f041c49714d39908');
      final iv = enc.IV.fromUtf8('0123456789abcdef');
      final aes = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

      final plain = aes.decrypt64(_normalizeBase64(encrypted), iv: iv);
      var text = plain.replaceAll(r'\/', '/').replaceAll('"', '').trim();
      text = text.replaceAll(RegExp(r'[\u0000-\u001F]'), '').trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  bool _isAbsoluteOrRootPath(String value) {
    return value.startsWith('http://') || value.startsWith('https://') || value.startsWith('/');
  }

  String _decodeMaybeEncryptedPath(String rawPath) {
    var path = _string(rawPath);
    if (path.isEmpty) return '';

    try {
      path = Uri.decodeComponent(path);
    } catch (_) {}

    if (_isAbsoluteOrRootPath(path)) return path;

    final decrypted = _decryptAesPath(path);
    if (decrypted != null && decrypted.isNotEmpty) {
      path = decrypted;
    }

    if (_isAbsoluteOrRootPath(path)) return path;
    return '/$path';
  }

  NovelChapter? _chapterFromMap(Map<String, dynamic> raw) {
    final map = _lowerMap(raw);

    final rawTitle = _pick(
      map,
      ['chaptername', 'chapter_name', 'chaptertitle', 'chapter_title', 'title', 'name'],
    );
    if (rawTitle.isEmpty) return null;

    final rawPath = _pick(map, ['path', 'chapterurl', 'chapter_url', 'url', 'href']);
    if (rawPath.isEmpty) return null;

    final decodedPath = _decodeMaybeEncryptedPath(rawPath);
    final url = _absUrl(decodedPath);
    if (url.isEmpty) return null;

    return NovelChapter(
      title: _cleanChapterTitle(rawTitle),
      url: url,
    );
  }

  List<Map<String, dynamic>> _extractBookMapsFromResponse(dynamic decoded) {
    final root = _toMap(decoded);
    if (root != null) {
      final data = root['data'];

      final directList = _toMapList(data);
      if (directList.isNotEmpty) return directList;

      final dataMap = _toMap(data);
      if (dataMap != null) {
        for (final key in ['list', 'records', 'items']) {
          final list = _toMapList(dataMap[key]);
          if (list.isNotEmpty) return list;
        }
        if (_isBookMap(dataMap)) return <Map<String, dynamic>>[dataMap];
      }
    }

    return _findMaps(decoded, _isBookMap);
  }

  Map<String, dynamic>? _extractDetailMapFromResponse(dynamic decoded, String expectedId) {
    final root = _toMap(decoded);
    if (root != null) {
      final dataMap = _toMap(root['data']);
      if (dataMap != null) {
        final lower = _lowerMap(dataMap);
        final hasId = _pick(lower, ['novelid', 'bookid', 'id']).isNotEmpty;
        if (_isBookMap(dataMap) || hasId) return dataMap;
      }
    }

    final maps = _findMaps(decoded, _isBookMap);
    if (maps.isEmpty) return null;

    if (expectedId.trim().isNotEmpty) {
      for (final map in maps) {
        final id = _pick(_lowerMap(map), ['novelid', 'bookid', 'id']);
        if (id == expectedId) return map;
      }
    }

    return maps.first;
  }

  List<Map<String, dynamic>> _extractChapterMapsFromResponse(dynamic decoded) {
    final root = _toMap(decoded);
    if (root != null) {
      final dataMap = _toMap(root['data']);

      if (dataMap != null) {
        for (final key in ['list', 'chapterlist', 'chapters', 'items']) {
          final list = _toMapList(dataMap[key]);
          if (list.isNotEmpty) return list;
        }
      }

      for (final key in ['list', 'chapterlist', 'chapters']) {
        final list = _toMapList(root[key]);
        if (list.isNotEmpty) return list;
      }
    }

    return _findMaps(decoded, _isChapterMap);
  }

  List<NovelBook> _booksFromMaps(
    List<Map<String, dynamic>> maps, {
    String sourcePath = '',
  }) {
    final out = <NovelBook>[];
    final seen = <String>{};

    for (final item in maps) {
      final book = _bookFromMap(item, sourcePath: sourcePath);
      if (book == null) continue;

      final key = book.id.isNotEmpty ? book.id : book.detailUrl;
      if (key.isEmpty || !seen.add(key)) continue;

      out.add(book);
    }

    return out;
  }

  List<NovelChapter> _chaptersFromMaps(List<Map<String, dynamic>> maps) {
    final out = <NovelChapter>[];
    final seen = <String>{};

    for (final item in maps) {
      final chapter = _chapterFromMap(item);
      if (chapter == null) continue;
      if (!seen.add(chapter.url)) continue;
      out.add(chapter);
    }

    return out;
  }

  List<NovelBook> _parseBooksFromHtml(String body) {
    final doc = html_parser.parse(body);
    final cards = doc.querySelectorAll(
      '.book-item, .rank-item, .novel-item, .list-item, .book-list li',
    );

    final out = <NovelBook>[];
    final seen = <String>{};

    for (final card in cards) {
      final link = card.querySelector('a[href]');
      final href = link?.attributes['href']?.trim() ?? '';
      final detailUrl = href.isNotEmpty ? _absUrl(href) : '';

      final title = (card.querySelector('h3, .title, .book-title, .name')?.text ??
              link?.attributes['title'] ??
              link?.text ??
              '')
          .trim();

      var id = (card.attributes['data-book-id'] ?? card.attributes['data-id'] ?? '').trim();
      if (id.isEmpty && detailUrl.isNotEmpty) {
        id = _extractNovelIdFromUrl(detailUrl);
      }

      if (id.isEmpty && title.isEmpty) continue;

      final key = id.isNotEmpty ? id : detailUrl;
      if (key.isEmpty || !seen.add(key)) continue;

      final img = card.querySelector('.cover img, .book-cover img, img');
      final cover = (img?.attributes['src'] ?? img?.attributes['data-src'] ?? '').trim();

      final author =
          (card.querySelector('.author, .book-author, .writer, .author-name')?.text ?? '').trim();
      final intro =
          (card.querySelector('.intro, .desc, .summary, .book-desc')?.text ?? '').trim();
      final category = (card.querySelector('.category, .type, .tag')?.text ?? '').trim();
      final status = _normalizeStatus((card.querySelector('.status, .state')?.text ?? '').trim());
      final wordCount = _normalizeWordCount(
        (card.querySelector('.word-count, .words, .count, .num')?.text ?? '').trim(),
      );

      out.add(
        NovelBook(
          id: id,
          title: title,
          author: author,
          intro: intro,
          coverUrl: _absUrl(cover),
          detailUrl: detailUrl,
          category: category,
          status: status,
          wordCount: wordCount,
        ),
      );
    }

    return out;
  }

  List<String> _detailCandidates(String bookId, String? detailUrl) {
    final set = <String>{};

    void add(String value) {
      final text = value.trim();
      if (text.isNotEmpty) set.add(text);
    }

    if (detailUrl != null) add(detailUrl);
    add('/novel/$bookId?isSearch=1');
    add('/novel/$bookId');
    add('/book/$bookId');

    return set.toList();
  }

  Future<List<NovelChapter>> _fetchToc(String novelId) async {
    if (novelId.trim().isEmpty) return const <NovelChapter>[];

    final paths = <String>[
      '/novel/$novelId/chapters?readNum=1',
      '/novel/$novelId/chapters',
      '/book/$novelId/chapters?readNum=1',
      '/book/$novelId/chapters',
    ];

    for (final path in paths) {
      try {
        final body = await _fetchBody(path);
        final decoded = _tryDecodeJson(body);
        if (decoded == null) continue;

        final maps = _extractChapterMapsFromResponse(decoded);
        final chapters = _chaptersFromMaps(maps);
        if (chapters.isNotEmpty) return chapters;
      } catch (_) {
        // 尝试下一个目录接口
      }
    }

    return const <NovelChapter>[];
  }

  String? _extractFirstString(dynamic node, List<String> keys) {
    final keySet = keys.map((e) => e.toLowerCase()).toSet();

    String? walk(dynamic current) {
      final map = _toMap(current);
      if (map != null) {
        final lower = _lowerMap(map);
        for (final key in keySet) {
          final value = _string(lower[key]);
          if (value.isNotEmpty && value.toLowerCase() != 'null') {
            return value;
          }
        }
        for (final v in map.values) {
          final found = walk(v);
          if (found != null && found.isNotEmpty) return found;
        }
        return null;
      }

      if (current is List) {
        for (final item in current) {
          final found = walk(item);
          if (found != null && found.isNotEmpty) return found;
        }
      }

      return null;
    }

    return walk(node);
  }

  String? _extractScriptContent(String html) {
    final patterns = <RegExp>[
      RegExp(r'"content"\s*:\s*"(.+?)"', dotAll: true),
      RegExp(r'"chapterContent"\s*:\s*"(.+?)"', dotAll: true),
      RegExp(r'chapterContent\s*=\s*"(.+?)"', dotAll: true),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      final raw = match?.group(1);
      if (raw == null || raw.isEmpty) continue;

      return raw
          .replaceAll(r'\\n', '\n')
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\"', '"')
          .replaceAll(r"\'", "'")
          .replaceAll(r'\/', '/');
    }

    return null;
  }

String _cleanContent(String raw) {
    var text = raw;

    text = text.replaceAll(_contentNoiseCleaner, '');
    text = text
        .replaceAll(r'\\n', '\n')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\n')
        .replaceAll('\r\n', '\n');

    // 👉 修复报错：去掉了 (?i) 和 (?is)，改用标准的 caseSensitive 和 dotAll 属性，完美兼容 Web 和 App
    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'</p>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'<p[^>]*>', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'<script.*?</script>', caseSensitive: false, dotAll: true), '');
    text = text.replaceAll(RegExp(r'<style.*?</style>', caseSensitive: false, dotAll: true), '');
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');

    final plain = html_parser.parseFragment(text).text ?? '';
    final lines = plain
        .replaceAll('\u00A0', ' ')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');

    final out = <String>[];
    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty) {
        if (out.isNotEmpty && out.last != '') out.add('');
        continue;
      }
      out.add(t);
    }

    return out.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }


  List<String> _chapterCandidates(String chapterUrl) {
    final set = <String>{};
    final raw = chapterUrl.trim();
    if (raw.isEmpty) return const <String>[];

    set.add(raw);

    final uri = Uri.tryParse(raw);
    if (uri != null && uri.hasScheme) {
      final path = '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
      if (path.isNotEmpty) set.add(path);
    }

    if (raw.startsWith('/')) {
      final sep = raw.contains('?') ? '&' : '?';
      set.add('$raw${sep}readNum=1');
    }

    return set.toList();
  }

  @override
  Future<List<NovelBook>> searchBooks(String keyword, {int page = 1}) async {
    final key = Uri.encodeComponent(keyword.trim());
    if (key.isEmpty) return const <NovelBook>[];

    final paths = <String>[
      '/search?page=$page&keyword=$key',
      '/search?keyword=$key&page=$page',
      '/search?page=$page&key=$key',
      '/search?key=$key&page=$page',
    ];

    for (final path in paths) {
      try {
        final books = await fetchByPath(path);
        if (books.isNotEmpty) return books;
      } catch (_) {
        // 尝试下一个搜索接口
      }
    }

    return const <NovelBook>[];
  }

  @override
  Future<List<NovelBook>> fetchByPath(String path) async {
    final body = await _fetchBody(path);
    final decoded = _tryDecodeJson(body);

    if (decoded != null) {
      final maps = _extractBookMapsFromResponse(decoded);
      final books = _booksFromMaps(maps, sourcePath: path);
      if (books.isNotEmpty) return books;
    }

    return _parseBooksFromHtml(body);
  }

  @override
  Future<NovelDetail> fetchDetail({
    required String bookId,
    String? detailUrl,
  }) async {
    final candidates = _detailCandidates(bookId, detailUrl);
    Object? lastError;

    for (final target in candidates) {
      try {
        final body = await _fetchBody(target);
        final decoded = _tryDecodeJson(body);

        if (decoded != null) {
          final detailMap = _extractDetailMapFromResponse(decoded, bookId);
          final embeddedChapters = _chaptersFromMaps(_extractChapterMapsFromResponse(decoded));

          final parsedBook = detailMap == null
              ? null
              : _bookFromMap(
                  detailMap,
                  fallbackId: bookId,
                  sourcePath: target,
                );

          final resolvedBookId = parsedBook?.id.isNotEmpty == true ? parsedBook!.id : bookId;
          final tocChapters = embeddedChapters.isNotEmpty
              ? embeddedChapters
              : await _fetchToc(resolvedBookId);

          if (parsedBook != null || tocChapters.isNotEmpty) {
            final book = parsedBook ??
                NovelBook(
                  id: resolvedBookId,
                  title: '',
                  author: '',
                  intro: '',
                  coverUrl: '',
                  detailUrl: _absUrl(target),
                );

            return NovelDetail(
              book: book,
              chapters: tocChapters,
            );
          }
        }
      } catch (e) {
        lastError = e;
      }
    }

    final tocOnly = await _fetchToc(bookId);
    if (tocOnly.isNotEmpty) {
      return NovelDetail(
        book: NovelBook(
          id: bookId,
          title: '',
          author: '',
          intro: '',
          coverUrl: '',
          detailUrl: _absUrl('/novel/$bookId?isSearch=1'),
        ),
        chapters: tocOnly,
      );
    }

    throw Exception('详情解析失败: ${lastError ?? '目录为空'}');
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
    final candidates = _chapterCandidates(chapter.url);
    Object? lastError;

    for (final target in candidates) {
      try {
        final body = await _fetchBody(target);
        final decoded = _tryDecodeJson(body);

        if (decoded != null) {
          final rawContent = _extractFirstString(
            decoded,
            const ['content', 'chaptercontent', 'chapter_content', 'body', 'txt', 'text'],
          );

          if (rawContent != null && rawContent.trim().isNotEmpty) {
            final cleaned = _cleanContent(rawContent);
            if (cleaned.isNotEmpty) {
              final title = _extractFirstString(
                    decoded,
                    const ['chaptername', 'chaptertitle', 'title', 'name'],
                  ) ??
                  chapter.title;

              return ChapterContent(
                title: title,
                content: cleaned,
                chapterIndex: chapterIndex,
                sourceUrl: _absUrl(target),
              );
            }
          }
        }

        final doc = html_parser.parse(body);
        final node = doc.querySelector(
          '#content, .content, .chapter-content, .read-content, #txt, .txt, article',
        );

        var raw = node?.innerHtml ?? '';
        if (raw.trim().isEmpty) {
          raw = _extractScriptContent(doc.outerHtml) ?? '';
        }

        if (raw.trim().isNotEmpty) {
          final cleaned = _cleanContent(raw);
          if (cleaned.isNotEmpty) {
            final htmlTitle =
                (doc.querySelector('h1, .chapter-title, .title, title')?.text ?? '').trim();

            return ChapterContent(
              title: htmlTitle.isNotEmpty ? htmlTitle : chapter.title,
              content: cleaned,
              chapterIndex: chapterIndex,
              sourceUrl: _absUrl(target),
            );
          }
        }
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception('正文解析失败: ${lastError ?? chapter.url}');
  }
}