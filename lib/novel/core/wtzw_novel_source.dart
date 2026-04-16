import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:http/http.dart' as http;

import 'models.dart';
import 'novel_source.dart';

class WtzwNovelSource implements NovelSource {
  WtzwNovelSource({
    required this.name,
    required this.baseUrl,
    required this.exploreUrl,
  });

  factory WtzwNovelSource.fromBookSourceJson(Map<String, dynamic> json) {
    return WtzwNovelSource(
      name: '${json['bookSourceName'] ?? '阅读助手'}'.trim(),
      baseUrl: '${json['bookSourceUrl'] ?? 'https://api-bc.wtzw.com'}'.trim(),
      exploreUrl: '${json['exploreUrl'] ?? ''}'.trim(),
    );
  }

  static bool supportsBookSourceJson(Map<String, dynamic> json) {
    final baseUrl = '${json['bookSourceUrl'] ?? ''}'.toLowerCase();
    final searchUrl = '${json['searchUrl'] ?? ''}';
    final ruleContent = json['ruleContent'];
    final contentRule = ruleContent is Map ? '${ruleContent['content'] ?? ''}' : '';

    return baseUrl.contains('wtzw.com') ||
        searchUrl.contains('/api/v5/search/words') ||
        contentRule.contains('242ccb8230d709e1');
  }

  final String name;
  final String baseUrl;
  final String exploreUrl;

  static const Duration _timeout = Duration(seconds: 20);

  static const String _signKey = 'd3dGiJc651gSQ8w1';
  static const String _chapterContentKey = '242ccb8230d709e1';
  static const String _imeiIp = '2937357107';

  static const String _apiBcBase = 'https://api-bc.wtzw.com';
  static const String _apiKsBase = 'https://api-ks.wtzw.com';

  static const Map<String, String> _baseHeaders = {
    'app-version': '51110',
    'platform': 'android',
    'reg': '0',
    'AUTHORIZATION': '',
    'application-id': 'com.****.reader',
    'net-env': '1',
    'channel': 'unknown',
    'qm-params': '',
  };

  static final RegExp _htmlTag = RegExp(r'<[^>]+>');

  String _str(dynamic value) => value == null ? '' : value.toString().trim();

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  List<dynamic> _asList(dynamic value) {
    if (value is List) return value;
    if (value is Map) return [value];
    return const [];
  }

  dynamic _mapValue(dynamic node, String key) {
    if (node is! Map) return null;
    if (node.containsKey(key)) return node[key];

    final lower = key.toLowerCase();
    for (final entry in node.entries) {
      if (entry.key.toString().toLowerCase() == lower) {
        return entry.value;
      }
    }
    return null;
  }

  dynamic _readPath(dynamic root, List<String> path) {
    dynamic current = root;
    for (final segment in path) {
      if (current is Map) {
        current = _mapValue(current, segment);
      } else {
        return null;
      }
    }
    return current;
  }

  List<dynamic> _readListPath(dynamic root, List<String> path) {
    return _asList(_readPath(root, path));
  }

  Map<String, dynamic> _readMapPath(dynamic root, List<String> path) {
    return _asMap(_readPath(root, path));
  }

  String _md5Sign(Map<String, dynamic> data) {
    final normalized = <String, String>{};
    for (final entry in data.entries) {
      if (entry.value == null) continue;
      normalized[entry.key] = '${entry.value}';
    }

    final keys = normalized.keys.toList()..sort();
    final raw = StringBuffer();
    for (final key in keys) {
      raw.write('$key=${normalized[key] ?? ''}');
    }
    raw.write(_signKey);

    return md5.convert(utf8.encode(raw.toString())).toString();
  }

  Map<String, String> _signedHeaders() {
    final headers = Map<String, String>.from(_baseHeaders);
    headers['sign'] = _md5Sign(headers);
    return headers;
  }

  Map<String, String> _withParamSign(Map<String, dynamic> params) {
    final normalized = <String, String>{};
    for (final entry in params.entries) {
      if (entry.value == null) continue;
      normalized[entry.key] = '${entry.value}';
    }

    normalized['sign'] = _md5Sign(normalized);
    return normalized;
  }

  String _encodeQuery(Map<String, String> params) {
    return params.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
  }

  Uri _buildUri(
    String url, {
    Map<String, String>? queryParameters,
  }) {
    final raw = url.trim();
    final full = raw.startsWith('http://') || raw.startsWith('https://')
        ? raw
        : '$baseUrl${raw.startsWith('/') ? '' : '/'}$raw';

    if (queryParameters == null || queryParameters.isEmpty) {
      return Uri.parse(full);
    }

    return Uri.parse('$full?${_encodeQuery(queryParameters)}');
  }

  Future<String> _getText(
    String url, {
    Map<String, String>? queryParameters,
    Map<String, String>? headers,
  }) async {
    final uri = _buildUri(url, queryParameters: queryParameters);
    final response =
        await http.get(uri, headers: headers ?? _signedHeaders()).timeout(_timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode} for $uri');
    }

    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  Future<Map<String, dynamic>> _getJsonMap(
    String url, {
    Map<String, String>? queryParameters,
    Map<String, String>? headers,
  }) async {
    final text = await _getText(
      url,
      queryParameters: queryParameters,
      headers: headers,
    );

    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);

    throw Exception('接口返回不是 JSON 对象');
  }

  String _extractTags(dynamic value) {
    if (value == null) return '';

    if (value is String) {
      return value.trim();
    }

    if (value is List) {
      final items = <String>[];
      for (final item in value) {
        if (item is Map) {
          final title = _str(item['title']);
          final name = _str(item['name']);
          final text = title.isNotEmpty ? title : name;
          if (text.isNotEmpty) items.add(text);
        } else {
          final text = _str(item);
          if (text.isNotEmpty) items.add(text);
        }
      }
      return items.join(', ');
    }

    if (value is Map) {
      final title = _str(value['title']);
      final name = _str(value['name']);
      return title.isNotEmpty ? title : name;
    }

    return _str(value);
  }

  String _cleanText(String input) {
    var text = input
        .replaceAll('&nbsp;', ' ')
        .replaceAll('\u3000', ' ')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<p[^>]*>', caseSensitive: false), '')
        .replaceAll(
          RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'<style[\s\S]*?</style>', caseSensitive: false),
          '',
        )
        .replaceAll(_htmlTag, '');

    text = text.replaceAll(RegExp(r'\r\n?'), '\n');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  String _buildIntro({
    required String intro,
    String tags = '',
  }) {
    final cleanIntro = _cleanText(intro);
    final cleanTags = tags.trim();

    if (cleanTags.isEmpty) return cleanIntro;
    if (cleanIntro.isEmpty) return '🏷️ 标签：$cleanTags';

    return '🏷️ 标签：$cleanTags\n🔖 简介：$cleanIntro';
  }

  String _detailUrl(String bookId) {
    final params = _withParamSign({
      'id': bookId,
      'imei_ip': _imeiIp,
      'teeny_mode': '0',
    });
    return '$_apiBcBase/api/v4/book/detail?${_encodeQuery(params)}';
  }

  String _chapterContentUrl(String bookId, String chapterId) {
    final params = _withParamSign({
      'id': bookId,
      'chapterId': chapterId,
    });
    return '$_apiKsBase/api/v1/chapter/content?${_encodeQuery(params)}';
  }

  String _extractBookId({
    required String bookId,
    String? detailUrl,
  }) {
    final rawBookId = bookId.trim();
    if (rawBookId.isNotEmpty) return rawBookId;

    final rawDetailUrl = detailUrl?.trim() ?? '';
    if (rawDetailUrl.isEmpty) return '';

    final uri = Uri.tryParse(rawDetailUrl);
    if (uri != null) {
      final id = uri.queryParameters['id'];
      if (id != null && id.isNotEmpty) return id;
    }

    final pseudo = _extractLooseParams(rawDetailUrl);
    return pseudo['id'] ?? '';
  }

  String _extractChapterId(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return '';

    if (RegExp(r'^\d+$').hasMatch(raw)) {
      return raw;
    }

    final uri = Uri.tryParse(raw);
    if (uri != null) {
      final chapterId = uri.queryParameters['chapterId'];
      if (chapterId != null && chapterId.isNotEmpty) return chapterId;

      if (uri.pathSegments.isNotEmpty) {
        final last = uri.pathSegments.last.trim();
        if (RegExp(r'^\d+$').hasMatch(last)) return last;
      }
    }

    final pseudo = _extractLooseParams(raw);
    return pseudo['chapterId'] ?? '';
  }

  Map<String, String> _extractLooseParams(String input) {
    final out = <String, String>{};

    for (final match in RegExp(r'([A-Za-z_]+)=([^&]+)').allMatches(input)) {
      final key = match.group(1)?.trim();
      final value = match.group(2)?.trim();
      if (key == null || key.isEmpty || value == null || value.isEmpty) {
        continue;
      }
      out[key] = Uri.decodeComponent(value);
    }

    return out;
  }

  NovelBook? _bookFromSearchItem(Map<String, dynamic> item) {
    final id = _str(item['id']);
    final title = _str(item['original_title']).isNotEmpty
        ? _str(item['original_title'])
        : _str(item['title']);
    if (id.isEmpty || title.isEmpty) return null;

    final author = _str(item['original_author']).isNotEmpty
        ? _str(item['original_author'])
        : _str(item['author']);
    final coverUrl = _str(item['image_link']);
    final tags = _extractTags(item['ptags']);
    final intro = _buildIntro(
      intro: _str(item['intro']),
      tags: tags,
    );

    return NovelBook(
      id: id,
      title: title,
      author: author,
      intro: intro,
      coverUrl: coverUrl,
      detailUrl: _detailUrl(id),
      category: tags,
      status: '',
      wordCount: _str(item['words_num']),
    );
  }

  NovelBook? _bookFromExploreItem(Map<String, dynamic> item) {
    final id = _str(item['id']);
    final title = _str(item['title']).isNotEmpty
        ? _str(item['title'])
        : _str(item['original_title']);
    if (id.isEmpty || title.isEmpty) return null;

    final author = _str(item['author']).isNotEmpty
        ? _str(item['author'])
        : _str(item['original_author']);
    final coverUrl = _str(item['image_link']);
    final tags = _extractTags(item['ptags']);
    final intro = _buildIntro(
      intro: _str(item['intro']),
      tags: tags,
    );

    return NovelBook(
      id: id,
      title: title,
      author: author,
      intro: intro,
      coverUrl: coverUrl,
      detailUrl: _detailUrl(id),
      category: tags,
      status: '',
      wordCount: _str(item['words_num']),
    );
  }

  NovelBook _bookFromDetail(Map<String, dynamic> book) {
    final id = _str(book['id']);
    final title = _str(book['title']);
    final author = _str(book['author']);
    final coverUrl = _str(book['image_link']);
    final tags = _extractTags(book['book_tag_list']);
    final intro = _buildIntro(
      intro: _str(book['intro']),
      tags: tags,
    );

    return NovelBook(
      id: id,
      title: title.isNotEmpty ? title : id,
      author: author,
      intro: intro,
      coverUrl: coverUrl,
      detailUrl: _detailUrl(id),
      category: tags,
      status: '',
      wordCount: _str(book['words_num']),
    );
  }

  List<NovelBook> _uniqueBooks(List<NovelBook> books) {
    final out = <NovelBook>[];
    final seen = <String>{};

    for (final book in books) {
      final key = book.id.isNotEmpty ? 'id:${book.id}' : 'url:${book.detailUrl}';
      if (seen.add(key)) {
        out.add(book);
      }
    }

    return out;
  }

  String _decryptChapterContent(String encodedContent) {
    try {
      final raw = encodedContent.trim();
      if (raw.isEmpty) return '';

      final allBytes = base64Decode(raw);
      if (allBytes.length <= 16) return raw;

      final ivBytes = Uint8List.fromList(allBytes.sublist(0, 16));
      final cipherBytes = Uint8List.fromList(allBytes.sublist(16));

      final encrypter = enc.Encrypter(
        enc.AES(
          enc.Key.fromUtf8(_chapterContentKey),
          mode: enc.AESMode.cbc,
          padding: 'PKCS7',
        ),
      );

      return encrypter.decrypt(
        enc.Encrypted(cipherBytes),
        iv: enc.IV(ivBytes),
      );
    } catch (_) {
      return encodedContent;
    }
  }

  @override
  Future<List<NovelBook>> searchBooks(String keyword, {int page = 1}) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return [];

    final headers = _signedHeaders();
    final params = _withParamSign({
      'gender': '3',
      'imei_ip': _imeiIp,
      'page': '$page',
      'wd': kw,
    });

    final json = await _getJsonMap(
      '$_apiBcBase/api/v5/search/words',
      queryParameters: params,
      headers: headers,
    );

    final books = _readListPath(json, ['data', 'books']);
    final result = <NovelBook>[];

    for (final item in books) {
      final map = _asMap(item);
      final book = _bookFromSearchItem(map);
      if (book != null) {
        result.add(book);
      }
    }

    return _uniqueBooks(result);
  }

  @override
  Future<List<NovelBook>> fetchByPath(String path) async {
    final raw = path.trim();
    if (raw.isEmpty) return [];

    final headers = _signedHeaders();
    final looseParams = _extractLooseParams(raw);

    final isCategory = raw.contains('/category') || looseParams.containsKey('category_id');
    final isTag = raw.contains('/tag') || looseParams.containsKey('tag_id');

    if (!isCategory && !isTag) {
      return [];
    }

    late final String endpoint;
    late final Map<String, String> params;

    if (isCategory) {
      endpoint = '$_apiBcBase/api/v4/category/get-list';
      params = _withParamSign({
        'gender': looseParams['gender'] ?? '2',
        'category_id': looseParams['category_id'] ?? '',
        'need_filters': looseParams['need_filters'] ?? '1',
        'page': looseParams['page'] ?? '1',
        'need_category': looseParams['need_category'] ?? '1',
      });
    } else {
      endpoint = '$_apiBcBase/api/v4/tag/index';
      params = _withParamSign({
        'gender': looseParams['gender'] ?? '2',
        'need_filters': looseParams['need_filters'] ?? '1',
        'page': looseParams['page'] ?? '1',
        'tag_id': looseParams['tag_id'] ?? '',
      });
    }

    final json = await _getJsonMap(
      endpoint,
      queryParameters: params,
      headers: headers,
    );

    final books = _readListPath(json, ['data', 'books']);
    final result = <NovelBook>[];

    for (final item in books) {
      final map = _asMap(item);
      final book = _bookFromExploreItem(map);
      if (book != null) {
        result.add(book);
      }
    }

    return _uniqueBooks(result);
  }

  @override
  Future<NovelDetail> fetchDetail({
    required String bookId,
    String? detailUrl,
  }) async {
    final id = _extractBookId(
      bookId: bookId,
      detailUrl: detailUrl,
    );

    if (id.isEmpty) {
      throw Exception('书籍 ID 为空，无法获取详情');
    }

    final headers = _signedHeaders();

    final detailParams = _withParamSign({
      'id': id,
      'imei_ip': _imeiIp,
      'teeny_mode': '0',
    });

    final detailJson = await _getJsonMap(
      '$_apiBcBase/api/v4/book/detail',
      queryParameters: detailParams,
      headers: headers,
    );

    final bookMap = _readMapPath(detailJson, ['data', 'book']);
    if (bookMap.isEmpty) {
      throw Exception('详情接口返回为空');
    }

    final book = _bookFromDetail(bookMap);

    final tocParams = _withParamSign({
      'id': id,
    });

    final tocJson = await _getJsonMap(
      '$_apiKsBase/api/v1/chapter/chapter-list',
      queryParameters: tocParams,
      headers: headers,
    );

    final chapterList = _readListPath(tocJson, ['data', 'chapter_lists']);
    final chapters = <NovelChapter>[];

    for (final item in chapterList) {
      final map = _asMap(item);
      final chapterId = _str(map['id']);
      final title = _str(map['title']);

      if (chapterId.isEmpty || title.isEmpty) continue;

      chapters.add(
        NovelChapter(
          title: title,
          url: _chapterContentUrl(id, chapterId),
        ),
      );
    }

    return NovelDetail(
      book: book,
      chapters: chapters,
    );
  }

  @override
  Future<ChapterContent> fetchChapter({
    required NovelDetail detail,
    required int chapterIndex,
  }) async {
    if (chapterIndex < 0 || chapterIndex >= detail.chapters.length) {
      throw RangeError.index(chapterIndex, detail.chapters);
    }

    final chapter = detail.chapters[chapterIndex];
    final headers = _signedHeaders();

    String requestUrl = chapter.url;
    String chapterId = _extractChapterId(chapter.url);

    if (requestUrl.trim().isEmpty || !requestUrl.startsWith('http')) {
      final bookId = detail.book.id.trim();
      if (bookId.isEmpty) {
        throw Exception('书籍 ID 为空，无法请求章节正文');
      }

      if (chapterId.isEmpty) {
        chapterId = chapter.url.trim();
      }

      if (chapterId.isEmpty) {
        throw Exception('章节 ID 为空，无法请求章节正文');
      }

      requestUrl = _chapterContentUrl(bookId, chapterId);
    }

    final json = await _getJsonMap(
      requestUrl,
      headers: headers,
    );

    final encryptedContent =
        _str(_readPath(json, ['data', 'content']));
    final plainText = _decryptChapterContent(encryptedContent);
    final content = _cleanText(plainText);

    return ChapterContent(
      title: chapter.title,
      content: content,
      chapterIndex: chapterIndex,
      sourceUrl: requestUrl,
      fromCache: false,
    );
  }
}