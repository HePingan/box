import 'dart:async';
import 'dart:convert';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:http/http.dart' as http;

import 'models.dart';
import 'novel_source.dart';

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
  })  : name = name.trim(),
        baseUrl = _normalizeBaseUrlInput(baseUrl),
        searchUrl = searchUrl.trim(),
        exploreUrl = exploreUrl.trim(),
        ruleSearch = ruleSearch ?? const {},
        ruleExplore = ruleExplore ?? const {},
        ruleBookInfo = ruleBookInfo ?? const {},
        ruleToc = ruleToc ?? const {},
        ruleContent = ruleContent ?? const {},
        headers = {
          'User-Agent': 'okhttp/4.9.2',
          if (headers != null) ...headers,
        };

  factory RuleNovelSource.fromBookSourceJson(Map<String, dynamic> json) {
    final headerMap = _parseHeader(json['header']);

    return RuleNovelSource(
      name: '${json['bookSourceName'] ?? ''}',
      baseUrl: '${json['bookSourceUrl'] ?? ''}',
      searchUrl: '${json['searchUrl'] ?? ''}',
      exploreUrl: '${json['exploreUrl'] ?? ''}',
      ruleSearch: _asMap(json['ruleSearch']),
      ruleExplore: _asMap(json['ruleExplore']),
      ruleBookInfo: _asMap(json['ruleBookInfo']),
      ruleToc: _asMap(json['ruleToc']),
      ruleContent: _asMap(json['ruleContent']),
      headers: headerMap,
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

  static const Duration _timeout = Duration(seconds: 15);

  static final RegExp _chapterTitleCleaner = RegExp(
    r'正文卷\.|正文\.|VIP卷\.|默认卷\.|卷_|VIP章节\.|免费章节\.|章节目录\.|最新章节\.|[\(（【].*?[求更票谢乐发订合补加架字修Kk].*?[】）\)]',
  );

  static final RegExp _htmlTag = RegExp(r'<[^>]+>');

  static String _normalizeBaseUrlInput(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return '';

    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }

    if (raw.startsWith('//')) {
      return 'https:$raw';
    }

    return 'http://$raw';
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static Map<String, String> _parseHeader(dynamic raw) {
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
    }

    if (raw is String && raw.trim().isNotEmpty) {
      final s = raw.trim();

      try {
        final decoded = jsonDecode(s);
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      } catch (_) {}

      try {
        final normalized = s.replaceAll("'", '"');
        final decoded = jsonDecode(normalized);
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      } catch (_) {}

      final out = <String, String>{};
      final matches =
          RegExp(r'([A-Za-z0-9_\-]+)\s*:\s*([^,\n]+)').allMatches(s);
      for (final m in matches) {
        final key = m.group(1)?.trim();
        final value = m.group(2)?.trim();
        if (key != null &&
            key.isNotEmpty &&
            value != null &&
            value.isNotEmpty) {
          out[key] = value.replaceAll(RegExp(r'''^['"]|['"]$'''), '');
        }
      }
      return out;
    }

    return <String, String>{};
  }

  bool _isAbsoluteUrl(String value) {
    final raw = value.trim();
    return raw.startsWith('http://') || raw.startsWith('https://');
  }

  bool _looksLikeRuleExpr(String text) {
    final t = text.trim();
    if (t.isEmpty) return false;

    return t.startsWith(r'$') ||
        t.startsWith('@') ||
        t.startsWith('.') ||
        t.contains(r'$.') ||
        t.contains(r'$..');
  }

  String _toAbsoluteUrl(
    String input, {
    String? base,
  }) {
    final raw = input.trim();
    if (raw.isEmpty) return raw;

    if (_isAbsoluteUrl(raw)) {
      return raw;
    }

    final anchor = (base != null && base.trim().isNotEmpty)
        ? base.trim()
        : baseUrl.trim();

    if (anchor.isEmpty) {
      throw const FormatException('bookSourceUrl 为空，无法解析相对地址');
    }

    String absoluteBase;

    if (_isAbsoluteUrl(anchor)) {
      absoluteBase = anchor;
    } else if (anchor.startsWith('//')) {
      final scheme = baseUrl.startsWith('https://') ? 'https' : 'http';
      absoluteBase = '$scheme:$anchor';
    } else {
      final root = _normalizeBaseUrlInput(baseUrl);
      if (root.isEmpty) {
        throw const FormatException('bookSourceUrl 为空，无法解析相对地址');
      }
      absoluteBase = Uri.parse(root).resolve(anchor).toString();
    }

    final baseUri = Uri.parse(absoluteBase);

    if (raw.startsWith('//')) {
      return '${baseUri.scheme}:$raw';
    }

    return baseUri.resolve(raw).toString();
  }

  Uri _resolveUri(
    String path, {
    String? base,
  }) {
    final raw = path.trim();

    if (raw.isEmpty) {
      final fallback = (base != null && base.trim().isNotEmpty)
          ? _toAbsoluteUrl(base)
          : baseUrl;
      return Uri.parse(fallback);
    }

    return Uri.parse(_toAbsoluteUrl(raw, base: base));
  }

  String _absUrl(
    String path, {
    String? base,
  }) {
    final raw = path.trim();
    if (raw.isEmpty) return '';

    try {
      return _toAbsoluteUrl(raw, base: base);
    } catch (_) {
      return raw;
    }
  }

  Future<String> _request(
    String path, {
    String? base,
  }) async {
    final uri = _resolveUri(path, base: base);

    final response = await http.get(uri, headers: headers).timeout(_timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode} for $uri');
    }

    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  dynamic _tryDecodeJson(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  String _renderTemplate(
    String input,
    dynamic context,
    dynamic root, {
    Map<String, String> vars = const {},
  }) {
    return input.replaceAllMapped(RegExp(r'\{\{(.*?)\}\}'), (match) {
      final expr = match.group(1)?.trim() ?? '';
      if (expr.isEmpty) return '';

      if (vars.containsKey(expr)) {
        return vars[expr]!;
      }

      final value = _evalExpr(
        expr,
        context: context,
        root: root,
        vars: vars,
      );

      return value;
    });
  }

  String _evalExpr(
    String expr, {
    required dynamic context,
    required dynamic root,
    Map<String, String> vars = const {},
  }) {
    if (expr.isEmpty) return '';

    if (vars.containsKey(expr)) {
      return vars[expr]!;
    }

    dynamic value;

    if (expr.startsWith(r'$') || expr.startsWith('@')) {
      value = _extractPath(context, expr);
      value ??= _extractPath(root, expr);
    } else if (context is Map) {
      value = _mapLookup(context, expr);
    }

    if (value == null && root is Map) {
      value = _mapLookup(root, expr);
    }

    if (value == null) return '';
    return value.toString();
  }

  dynamic _extractPath(dynamic root, String expr) {
    var path = expr.trim();
    if (path.isEmpty) return null;

    if (path == r'$' || path == '@') {
      return root;
    }

    if (path.startsWith(r'$..')) {
      final key = path.substring(3).trim();
      if (key.isEmpty) return null;
      return _findFirstRecursive(root, key);
    }

    if (path.startsWith(r'@..')) {
      final key = path.substring(3).trim();
      if (key.isEmpty) return null;
      return _findFirstRecursive(root, key);
    }

    if (path.startsWith(r'$.')) {
      path = path.substring(2);
    } else if (path.startsWith(r'@.')) {
      path = path.substring(2);
    } else if (path.startsWith(r'$')) {
      path = path.substring(1);
    } else if (path.startsWith('@')) {
      path = path.substring(1);
    } else if (path.startsWith('.')) {
      path = path.substring(1);
    }

    if (path.isEmpty) return root;

    final segments = path.split('.').where((e) => e.isNotEmpty).toList();
    dynamic current = root;

    for (final segment in segments) {
      current = _descend(current, segment);
      if (current == null) return null;
    }

    return current;
  }

  dynamic _descend(dynamic current, String segment) {
    final match = RegExp(r'^(.*?)(\[(\*|\d+)\])?$').firstMatch(segment);
    final key = match?.group(1) ?? segment;
    final index = match?.group(3);

    if (current is Map) {
      dynamic value = _mapLookup(current, key);

      if (index != null) {
        if (value is List) {
          if (index == '*') return value;
          final i = int.tryParse(index);
          if (i != null && i >= 0 && i < value.length) return value[i];
          return null;
        }
      }

      return value;
    }

    if (current is List) {
      if (key.isEmpty) {
        if (index == '*') return current;
        final i = int.tryParse(index ?? '');
        if (i != null && i >= 0 && i < current.length) return current[i];
        return null;
      }

      final mapped = <dynamic>[];
      for (final item in current) {
        final v = _descend(item, segment);
        if (v != null) mapped.add(v);
      }
      return mapped;
    }

    return null;
  }

  dynamic _mapLookup(Map map, String key) {
    if (map.containsKey(key)) return map[key];

    final lower = key.toLowerCase();
    for (final entry in map.entries) {
      if (entry.key.toString().toLowerCase() == lower) {
        return entry.value;
      }
    }
    return null;
  }

  dynamic _findFirstRecursive(dynamic node, String key) {
    if (node is Map) {
      final direct = _mapLookup(node, key);
      if (direct != null) return direct;

      for (final value in node.values) {
        final found = _findFirstRecursive(value, key);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final item in node) {
        final found = _findFirstRecursive(item, key);
        if (found != null) return found;
      }
    }
    return null;
  }

  String _applyRegexReplacement(
    String input,
    String pattern,
    String replacement,
  ) {
    final reg = RegExp(pattern);

    return input.replaceAllMapped(reg, (match) {
      return replacement.replaceAllMapped(RegExp(r'\$(\d+)'), (m) {
        final index = int.tryParse(m.group(1) ?? '');
        if (index == null) return m.group(0) ?? '';
        return match.group(index) ?? '';
      });
    });
  }

  dynamic _resolveDynamicRule(
    String rule, {
    required dynamic context,
    required dynamic root,
    Map<String, String> vars = const {},
  }) {
    var text = rule.trim();
    if (text.isEmpty) return '';

    text = _renderTemplate(text, context, root, vars: vars);

    final jsIndex = text.indexOf('@js:');
    if (jsIndex >= 0) {
      text = text.substring(0, jsIndex);
    }

    final regexIndex = text.indexOf('##');
    if (regexIndex >= 0) {
      text = text.substring(0, regexIndex);
    }

    final value = _extractPath(context, text) ?? _extractPath(root, text);
    if (value != null) return value;

    if (vars.containsKey(text)) return vars[text]!;

    if (context is Map) {
      final v = _mapLookup(context, text);
      if (v != null) return v;
    }

    if (root is Map) {
      final v = _mapLookup(root, text);
      if (v != null) return v;
    }

    if (_looksLikeRuleExpr(text)) {
      return '';
    }

    return text;
  }

  String _resolveStringRule(
    String rule, {
    required dynamic context,
    required dynamic root,
    Map<String, String> vars = const {},
  }) {
    var text = rule.trim();
    if (text.isEmpty) return '';

    text = _renderTemplate(text, context, root, vars: vars);

    String? jsExpr;
    final jsIndex = text.indexOf('@js:');
    if (jsIndex >= 0) {
      jsExpr = text.substring(jsIndex + 4).trim();
      text = text.substring(0, jsIndex);
    }

    final parts = text.split('##');
    final base = parts.first.trim();

    dynamic value = _resolveDynamicRule(
      base,
      context: context,
      root: root,
      vars: vars,
    );

    var out = value?.toString() ?? '';

    for (var i = 1; i < parts.length; i += 2) {
      final regex = parts[i].trim();
      final replacement = i + 1 < parts.length ? parts[i + 1] : '';
      if (regex.isEmpty) continue;

      try {
        out = _applyRegexReplacement(out, regex, replacement);
      } catch (_) {}
    }

    if (jsExpr != null && jsExpr.isNotEmpty) {
      out = _evalJs(jsExpr, out);
    }

    return out.trim();
  }

  String _evalJs(String jsExpr, String result) {
    final expr = jsExpr.trim();

    final aes = RegExp(
      r'java\.aesBase64DecodeToString\(\s*result\s*,\s*"([^"]+)"\s*,\s*"AES/CBC/PKCS5Padding"\s*,\s*"([^"]+)"\s*\)',
    ).firstMatch(expr);

    if (aes != null) {
      final key = aes.group(1) ?? '';
      final iv = aes.group(2) ?? '';
      return _aesBase64DecodeToString(result, key, iv);
    }

    return result;
  }

  String _aesBase64DecodeToString(String input, String key, String iv) {
    try {
      final normalized = _normalizeBase64(input);
      final encrypter = enc.Encrypter(
        enc.AES(
          enc.Key.fromUtf8(key),
          mode: enc.AESMode.cbc,
          padding: 'PKCS7',
        ),
      );

      final plain = encrypter.decrypt64(
        normalized,
        iv: enc.IV.fromUtf8(iv),
      );

      return plain
          .replaceAll(r'\/', '/')
          .replaceAll('\\/', '/')
          .replaceAll('"', '')
          .trim();
    } catch (_) {
      return input;
    }
  }

  String _normalizeBase64(String input) {
    var s = input.trim().replaceAll('-', '+').replaceAll('_', '/');
    final mod = s.length % 4;
    if (mod != 0) {
      s += '=' * (4 - mod);
    }
    return s;
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

  String _cleanChapterTitle(String title) {
    return title.replaceAll(_chapterTitleCleaner, '').trim();
  }

  String _cleanContent(String content) {
    var text = content;

    final replaceRegex = '${_toStr(ruleContent['replaceRegex'])}'.trim();
    if (replaceRegex.isNotEmpty) {
      final pattern = replaceRegex.startsWith('##')
          ? replaceRegex.substring(2)
          : replaceRegex;

      if (pattern.isNotEmpty) {
        try {
          text = text.replaceAll(RegExp(pattern), '');
        } catch (_) {}
      }
    }

    text = _cleanText(text);

    final lines = text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return lines.join('\n\n').trim();
  }

  String _toStr(dynamic value) => value == null ? '' : value.toString().trim();

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

        final value = _resolveStringRule(
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

  String _deriveId(
    dynamic item,
    String detailUrl,
    String title,
    String fallbackId,
  ) {
    final map =
        item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{};

    final candidates = [
      _toStr(_mapLookup(map, 'novelId')),
      _toStr(_mapLookup(map, 'bookId')),
      _toStr(_mapLookup(map, 'id')),
      _toStr(_mapLookup(map, 'novelid')),
      _toStr(_mapLookup(map, 'bookid')),
    ];

    for (final c in candidates) {
      if (c.isNotEmpty) return c;
    }

    if (detailUrl.isNotEmpty) {
      final uri = Uri.tryParse(detailUrl);
      if (uri != null) {
        final qp = uri.queryParameters['id'] ??
            uri.queryParameters['novelId'] ??
            uri.queryParameters['bookId'];
        if (qp != null && qp.isNotEmpty) return qp;

        if (uri.pathSegments.isNotEmpty) {
          final last = uri.pathSegments.last;
          if (last.isNotEmpty) return last;
        }
      }
    }

    if (fallbackId.isNotEmpty) return fallbackId;

    if (title.isNotEmpty) {
      return 'book_${title.hashCode}';
    }

    return '';
  }

  String _deriveStatus(dynamic item) {
    if (item is! Map) return '';
    final map = Map<String, dynamic>.from(item);

    final raw = _toStr(
      _mapLookup(map, 'status') ??
          _mapLookup(map, 'isComplete') ??
          _mapLookup(map, 'complete') ??
          _mapLookup(map, 'iscomplete'),
    );

    final s = raw.toLowerCase();

    if (s == '1' || s == 'true' || s.contains('完')) {
      return '完结';
    }
    if (s == '0' || s == 'false' || s.contains('连')) {
      return '连载';
    }
    return '';
  }

  String _buildCategory(dynamic item) {
    if (item is! Map) return '';
    final map = Map<String, dynamic>.from(item);

    final className =
        _toStr(_mapLookup(map, 'className') ?? _mapLookup(map, 'classname'));
    final tagName =
        _toStr(_mapLookup(map, 'tagName') ?? _mapLookup(map, 'tagname'));
    final kind = _toStr(_mapLookup(map, 'kind'));

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
    final title = _pickField(
      item,
      item,
      ruleMaps,
      ['name', 'title', 'novelName', 'bookName'],
      vars: vars,
    );

    final author = _pickField(
      item,
      item,
      ruleMaps,
      ['author', 'authorName'],
      vars: vars,
    );

    final intro = _pickField(
      item,
      item,
      ruleMaps,
      ['intro', 'summary', 'desc'],
      vars: vars,
    );

    final coverUrl = _pickField(
      item,
      item,
      ruleMaps,
      ['coverUrl', 'cover', 'img', 'thumb'],
      vars: vars,
    );

    final category = _pickField(
      item,
      item,
      ruleMaps,
      ['category', 'kind', 'className'],
      vars: vars,
    );

    final wordCount = _pickField(
      item,
      item,
      ruleMaps,
      ['wordCount', 'wordNum'],
      vars: vars,
    );

    final detailRule = _pickField(
      item,
      item,
      ruleMaps,
      ['bookUrl', 'detailUrl', 'url'],
      vars: vars,
    );

    final detailUrl =
        detailRule.isNotEmpty ? detailRule : fallbackDetailUrl;

    final finalDetailUrl = _absUrl(
      detailUrl,
      base: itemBaseUrl.isNotEmpty ? itemBaseUrl : null,
    );

    final finalId = _deriveId(item, finalDetailUrl, title, fallbackId);
    if (finalId.isEmpty && title.isEmpty) return null;

    final status = _pickField(
      item,
      item,
      ruleMaps,
      ['status'],
      vars: vars,
    );

    return NovelBook(
      id: finalId,
      title: title.isNotEmpty ? title : finalId,
      author: author,
      intro: _cleanText(intro),
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

  List<Map<String, dynamic>> _findMaps(
    dynamic node,
    bool Function(Map<String, dynamic>) matcher,
  ) {
    final out = <Map<String, dynamic>>[];

    void walk(dynamic current) {
      if (current is Map) {
        final m = Map<String, dynamic>.from(current);
        if (matcher(m)) out.add(m);
        for (final v in m.values) {
          walk(v);
        }
      } else if (current is List) {
        for (final v in current) {
          walk(v);
        }
      }
    }

    walk(node);
    return out;
  }

  List<NovelBook> _uniqueBooks(List<NovelBook> books) {
    final seen = <String>{};
    final out = <NovelBook>[];

    for (final b in books) {
      final key = b.id.isNotEmpty ? 'id:${b.id}' : 'url:${b.detailUrl}';
      if (seen.add(key)) {
        out.add(b);
      }
    }

    return out;
  }

  List<NovelChapter> _parseChapters(
    dynamic root, {
    required List<Map<String, dynamic>> ruleMaps,
    String chapterBaseUrl = '',
  }) {
    final listRule = _pickRuleString(
      ruleMaps,
      ['chapterList', 'bookList', 'list'],
    );

    List<dynamic> items = const [];

    if (listRule.isNotEmpty) {
      final raw = _resolveDynamicRule(
        listRule,
        context: root,
        root: root,
      );

      if (raw is List) {
        items = raw;
      } else if (raw is Map) {
        items = [raw];
      }
    } else {
      final maps = _findMaps(
        root,
        (m) =>
            _toStr(m['chapterName']).isNotEmpty ||
            _toStr(m['chaptername']).isNotEmpty ||
            _toStr(m['path']).isNotEmpty ||
            _toStr(m['url']).isNotEmpty ||
            _toStr(m['href']).isNotEmpty,
      );
      items = maps;
    }

    final chapterNameRule = _pickRuleString(
      ruleMaps,
      ['chapterName', 'name', 'title'],
    );

    final chapterUrlRule = _pickRuleString(
      ruleMaps,
      ['chapterUrl', 'url', 'path', 'href'],
    );

    final chapters = <NovelChapter>[];

    for (final item in items) {
      final title = chapterNameRule.isNotEmpty
          ? _resolveStringRule(
              chapterNameRule,
              context: item,
              root: item,
            )
          : _pickField(
              item,
              item,
              const [],
              ['chapterName', 'chaptername', 'title', 'name'],
            );

      var url = chapterUrlRule.isNotEmpty
          ? _resolveStringRule(
              chapterUrlRule,
              context: item,
              root: item,
            )
          : _pickField(
              item,
              item,
              const [],
              ['chapterUrl', 'url', 'path', 'href'],
            );

      final cleanTitle = _cleanChapterTitle(title);
      url = _absUrl(
        url,
        base: chapterBaseUrl.isNotEmpty ? chapterBaseUrl : null,
      );

      if (cleanTitle.isEmpty || url.isEmpty) continue;

      chapters.add(
        NovelChapter(
          title: cleanTitle,
          url: url,
        ),
      );
    }

    final seen = <String>{};
    final out = <NovelChapter>[];
    for (final c in chapters) {
      final key = '${c.title}|${c.url}';
      if (seen.add(key)) out.add(c);
    }

    return out;
  }

  dynamic _extractInit(dynamic root, Map<String, dynamic> ruleMap) {
    final initRule = _toStr(ruleMap['init']);
    if (initRule.isEmpty) return root;

    final extracted = _resolveDynamicRule(
      initRule,
      context: root,
      root: root,
    );

    return extracted ?? root;
  }

  @override
  Future<List<NovelBook>> searchBooks(String keyword, {int page = 1}) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return [];
    if (searchUrl.trim().isEmpty) return [];

    final path = _renderTemplate(
      searchUrl,
      const {},
      const {},
      vars: {
        'page': page.toString(),
        'key': Uri.encodeComponent(kw),
        'keyword': Uri.encodeComponent(kw),
      },
    );

    final body = await _request(path);
    final decoded = _tryDecodeJson(body);
    if (decoded == null) return [];

    final init = _extractInit(decoded, ruleSearch);

    final listRule = _pickRuleString(
      [ruleSearch],
      ['bookList', 'list'],
    );

    List<dynamic> items = const [];

    if (listRule.isNotEmpty) {
      final raw = _resolveDynamicRule(
        listRule,
        context: init,
        root: decoded,
      );
      if (raw is List) {
        items = raw;
      } else if (raw is Map) {
        items = [raw];
      }
    } else {
      items = _findMaps(
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
        vars: {
          'page': page.toString(),
          'key': Uri.encodeComponent(kw),
          'keyword': Uri.encodeComponent(kw),
        },
      );
      if (book != null) {
        books.add(book);
      }
    }

    return _uniqueBooks(books);
  }

  @override
  Future<List<NovelBook>> fetchByPath(String path) async {
    final p = path.trim();
    if (p.isEmpty) return [];

    if (p.contains('{{key}}') || p.contains('{key}')) {
      return [];
    }

    final body = await _request(p);
    final decoded = _tryDecodeJson(body);
    if (decoded == null) return [];

    final activeRule = ruleExplore.isNotEmpty ? ruleExplore : ruleSearch;
    final init = _extractInit(decoded, activeRule);

    final listRule = _pickRuleString(
      [activeRule],
      ['bookList', 'list'],
    );

    List<dynamic> items = const [];

    if (listRule.isNotEmpty) {
      final raw = _resolveDynamicRule(
        listRule,
        context: init,
        root: decoded,
      );
      if (raw is List) {
        items = raw;
      } else if (raw is Map) {
        items = [raw];
      }
    } else {
      items = _findMaps(
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
      if (book != null) {
        books.add(book);
      }
    }

    return _uniqueBooks(books);
  }

  @override
  Future<NovelDetail> fetchDetail({
    required String bookId,
    String? detailUrl,
  }) async {
    final candidates = <String>[
      if (detailUrl != null && detailUrl.trim().isNotEmpty) detailUrl.trim(),
      '/novel/$bookId?isSearch=1',
      '/novel/$bookId',
      '/book/$bookId',
    ];

    dynamic decoded;
    String usedPath = '';

    for (final candidate in candidates) {
      try {
        final body = await _request(candidate);
        final js = _tryDecodeJson(body);
        if (js != null) {
          decoded = js;
          usedPath = candidate;
          break;
        }
      } catch (_) {}
    }

    if (decoded == null) {
      throw Exception('详情解析失败：$bookId');
    }

    final init = _extractInit(decoded, ruleBookInfo);

    final book = _buildBook(
      item: init,
      ruleMaps: [ruleBookInfo, ruleSearch],
      fallbackId: bookId,
      fallbackDetailUrl: _absUrl(usedPath),
      itemBaseUrl: usedPath,
    );

    if (book == null) {
      throw Exception('书籍信息解析失败：$bookId');
    }

    final tocRule = _toStr(ruleBookInfo['tocUrl']);
    dynamic tocDecoded = decoded;
    String tocPath = '';

    if (tocRule.isNotEmpty) {
      tocPath = _resolveStringRule(
        tocRule,
        context: init,
        root: decoded,
      );

      if (tocPath.isNotEmpty) {
        try {
          final tocBody = await _request(
            tocPath,
            base: book.detailUrl.isNotEmpty ? book.detailUrl : usedPath,
          );
          final tocJs = _tryDecodeJson(tocBody);
          if (tocJs != null) {
            tocDecoded = tocJs;
          }
        } catch (_) {
          // tocUrl 失败时退回详情页本体解析
        }
      }
    }

    final tocInit = _extractInit(tocDecoded, ruleToc);
    final chapters = _parseChapters(
      tocInit,
      ruleMaps: [ruleToc],
      chapterBaseUrl: tocPath.isNotEmpty
          ? _absUrl(
              tocPath,
              base: book.detailUrl.isNotEmpty ? book.detailUrl : usedPath,
            )
          : (book.detailUrl.isNotEmpty ? book.detailUrl : usedPath),
    );

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
    final body = await _request(
      chapter.url,
      base: detail.book.detailUrl,
    );
    final decoded = _tryDecodeJson(body);

    dynamic contentRoot = decoded ?? body;
    contentRoot = _extractInit(contentRoot, ruleContent);

    String content = '';
    final contentRule = _toStr(ruleContent['content']);

    if (contentRule.isNotEmpty) {
      content = _resolveStringRule(
        contentRule,
        context: contentRoot,
        root: contentRoot,
      );
    }

    if (content.isEmpty && decoded != null) {
      final fallback = _findFirstRecursive(decoded, 'content');
      if (fallback != null) content = fallback.toString();

      if (content.isEmpty) {
        final fallback2 = _findFirstRecursive(decoded, 'chapterContent');
        if (fallback2 != null) content = fallback2.toString();
      }

      if (content.isEmpty) {
        final fallback3 = _findFirstRecursive(decoded, 'text');
        if (fallback3 != null) content = fallback3.toString();
      }

      if (content.isEmpty) {
        final fallback4 = _findFirstRecursive(decoded, 'txt');
        if (fallback4 != null) content = fallback4.toString();
      }
    }

    content = _cleanContent(content);

    return ChapterContent(
      title: chapter.title,
      content: content,
      chapterIndex: chapterIndex,
      sourceUrl: chapter.url,
      fromCache: false,
    );
  }
}