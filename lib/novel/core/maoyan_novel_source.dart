import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'text_cleaner.dart';
import 'models.dart';
import 'novel_exceptions.dart';
import 'novel_http_client.dart';
import 'novel_source.dart';

/// 猫眼看书（优++）书源
///
/// 处理 YSFly 格式的 data:;base64,... URL 和 @js: 嵌入认证逻辑。
/// 原始 JSON 中的 JS 代码负责：
///   1. 多域名轮询（13个备用域名）
///   2. 动态生成 client-device（MD5(aesKey)）和 Authorization Bearer Token
///   3. AES/CBC 解密章节路径
/// 本实现在 Dart 侧直接完成以上操作，无需 JavaScript 引擎。
class MaoYanNovelSource implements NovelSource {
  MaoYanNovelSource({
    required this.baseUrl,
    required this.headers,
    required this.searchUrl,
    required this.exploreUrl,
    required this.ruleSearch,
    required this.ruleBookInfo,
    required this.ruleToc,
    required this.ruleContent,
    required this.domains,
    required this.aesKeys,
    required this.authTokens,
    NovelHttpClient? httpClient,
  }) : _httpClient = httpClient ?? NovelHttpClient.create();

  factory MaoYanNovelSource.fromBookSourceJson(Map<String, dynamic> json) {
    final comment = '${json['bookSourceComment'] ?? ''}';
    final extracted = extractAuthFromComment(comment);

    final baseHeaders = _parseHeader(json['header']);
    final domains = extracted.$1;
    final aesKeys = extracted.$2;
    final authTokens = extracted.$3;

    // 选第一个可用域名为默认 baseUrl
    final firstDomain = domains.isNotEmpty
        ? 'http://api.${domains.first.$1}.com'
        : '${json['bookSourceUrl'] ?? ''}';

    // 给 header 补充认证信息（用第一个 domain 对应的 token）
    if (domains.isNotEmpty) {
      final firstType = domains.first.$2;
      if (firstType < authTokens.length) {
        baseHeaders['client-device'] = md5
            .convert(utf8.encode(aesKeys[firstType]))
            .toString();
        baseHeaders['Authorization'] = authTokens[firstType];
      }
    }

    return MaoYanNovelSource(
      baseUrl: firstDomain,
      headers: baseHeaders,
      searchUrl: '${json['searchUrl'] ?? ''}',
      exploreUrl: '${json['exploreUrl'] ?? ''}',
      ruleSearch: _asMap(json['ruleSearch']),
      ruleBookInfo: _asMap(json['ruleBookInfo']),
      ruleToc: _asMap(json['ruleToc']),
      ruleContent: _asMap(json['ruleContent']),
      domains: domains,
      aesKeys: aesKeys,
      authTokens: authTokens,
    );
  }

  static bool supportsBookSourceJson(Map<String, dynamic> json) {
    final comment = '${json['bookSourceComment'] ?? ''}';
    return comment.contains('maoyankanshu') ||
        comment.contains('myweipin') ||
        '${json['bookSourceName'] ?? ''}'.contains('猫眼');
  }

  final String baseUrl;
  final Map<String, String> headers;
  final String searchUrl;
  final String exploreUrl;
  final Map<String, dynamic> ruleSearch;
  final Map<String, dynamic> ruleBookInfo;
  final Map<String, dynamic> ruleToc;
  final Map<String, dynamic> ruleContent;
  final List<(String, int)> domains;
  final List<String> aesKeys;
  final List<String> authTokens;
  final NovelHttpClient _httpClient;

  static Duration get _timeout =>
      kIsWeb ? const Duration(seconds: 8) : const Duration(seconds: 20);

  /// Convert an absolute URL to a proxy URL for same-origin CORS bypass on web
  static String _toProxyUrl(String fullUrl) {
    final uri = Uri.parse(fullUrl);
    final query = uri.hasQuery ? '?${uri.query}' : '';
    return '/api-proxy/${uri.scheme}/${uri.host}${uri.path}$query';
  }

  /// Web 端限制并发尝试域名的数量
  static int get _maxDomainAttempts => kIsWeb ? 3 : 999;

  // ── 解析 data:;base64,... URL ──

  /// 从 `data:;base64,<base64_path>,{"type":"maoyankanshu"}` 中提取实际路径
  static String decodeDataUrl(String url) {
    final trimmed = url.trim();
    if (!trimmed.startsWith('data:;base64,')) return trimmed;

    final afterPrefix = trimmed.substring('data:;base64,'.length);
    // 提取 base64 部分（到第一个 ",{" 为止）
    final commaIdx = afterPrefix.indexOf(',');
    final base64Part = commaIdx > 0
        ? afterPrefix.substring(0, commaIdx)
        : afterPrefix;

    try {
      final decoded = utf8.decode(
        base64Decode(base64Part),
        allowMalformed: true,
      );
      return decoded;
    } catch (_) {
      return trimmed;
    }
  }

  /// 将路径包装为 data:;base64,... URL
  static String encodeDataUrl(String path) {
    final encoded = base64Encode(utf8.encode(path));
    return 'data:;base64,$encoded,{"type":"maoyankanshu"}';
  }

  // ── 认证信息提取 ──

  static (List<(String, int)>, List<String>, List<String>)
  extractAuthFromComment(String comment) {
    final domains = <(String, int)>[];
    final aesKeys = <String>[];
    final authTokens = <String>[];

    // 提取域名
    final domainRegex = RegExp(r'\["([a-z]+)",\s*(\d)\]');
    for (final m in domainRegex.allMatches(comment)) {
      domains.add((m.group(1)!, int.parse(m.group(2)!)));
    }

    // 提取 aesKey + Authorization 对
    // 格式: ["f041c49714d39908", "bearer eyJ..."]
    final authRegex = RegExp(r'\["([a-f0-9]+)",\s*"([^"]+)"\]');
    for (final m in authRegex.allMatches(comment)) {
      aesKeys.add(m.group(1)!);
      var token = m.group(2)!;
      // 标准化 token 前缀
      if (!token.toLowerCase().startsWith('bearer')) {
        token = 'Bearer $token';
      } else {
        // 按 HTTP 规范首字母大写
        token = 'Bearer ${token.substring(6)}';
      }
      authTokens.add(token.trim());
    }

    return (domains, aesKeys, authTokens);
  }

  static Map<String, String> _parseHeader(dynamic raw) {
    final out = <String, String>{'User-Agent': 'okhttp/4.9.2'};
    if (raw == null) return out;

    try {
      Map<String, dynamic> map;
      if (raw is String) {
        map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } else if (raw is Map) {
        map = Map<String, dynamic>.from(raw);
      } else {
        return out;
      }
      for (final e in map.entries) {
        out[e.key] = '${e.value}'.trim();
      }
    } catch (_) {}
    return out;
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  // ── HTTP 请求 ──

  // ── HTTP 请求 ──

  Future<String> _request(
    String url, {
    Map<String, String>? extraHeaders,
  }) async {
    final path = decodeDataUrl(url);
    final uri = Uri.tryParse(path);
    if (uri == null) throw HttpException('无法解析 URL: $path');

    // 手动对路径中的非 ASCII 字符做百分号编码
    final safePath = _percentEncodePath(path);

    final mergedHeaders = Map<String, String>.from(headers);
    if (extraHeaders != null) mergedHeaders.addAll(extraHeaders);

    // Web 端：并行竞速（解决串行轮询跨域挂起问题）
    // 原生端：串行轮询（避免海量并发请求）
    if (kIsWeb) {
      return _requestParallel(safePath, mergedHeaders);
    }

    // --- 原生平台：串行轮询 ---
    final attempted = <String>[];
    for (final (domain, uType) in domains) {
      for (final scheme in ['https', 'http']) {
        final host = '$scheme://api.$domain.com';
        final fullUrl = safePath.startsWith('http')
            ? safePath
            : '$host$safePath';

        final domainHeaders = Map<String, String>.from(mergedHeaders);
        if (uType < aesKeys.length && uType < authTokens.length) {
          domainHeaders['client-device'] = md5
              .convert(utf8.encode(aesKeys[uType]))
              .toString();
          domainHeaders['Authorization'] = authTokens[uType];
        }

        final tmpUri = Uri.tryParse(fullUrl);
        if (tmpUri == null) continue;
        final requestUri = tmpUri;
        final attemptKey = '$scheme://$domain';
        if (!attempted.contains(attemptKey)) attempted.add(attemptKey);

        try {
          final response = await _httpClient.get(
            requestUri,
            headers: domainHeaders,
            timeout: _timeout,
          );
          if (response.statusCode == 200) {
            return response.body;
          }
          debugPrint(
            '[MaoYan] _request $attemptKey -> HTTP ${response.statusCode}',
          );
        } catch (e) {
          debugPrint('[MaoYan] _request $attemptKey -> ERROR: $e');
        }
      }
    }

    // 兜底
    for (final scheme in ['https', 'http']) {
      final fallbackBase = baseUrl.replaceFirst(
        RegExp(r'^https?://'),
        '$scheme://',
      );
      final fullFallbackUrl = safePath.startsWith('http')
          ? safePath
          : '$fallbackBase$safePath';
      final fallbackHeaders = Map<String, String>.from(mergedHeaders);
      if (domains.isNotEmpty && aesKeys.isNotEmpty && authTokens.isNotEmpty) {
        final firstType = domains.first.$2;
        if (firstType < aesKeys.length && firstType < authTokens.length) {
          fallbackHeaders['client-device'] = md5
              .convert(utf8.encode(aesKeys[firstType]))
              .toString();
          fallbackHeaders['Authorization'] = authTokens[firstType];
        }
      }
      final fbUri = Uri.tryParse(fullFallbackUrl);
      if (fbUri == null) continue;
      try {
        final response = await _httpClient.get(
          fbUri,
          headers: fallbackHeaders,
          timeout: _timeout,
        );
        if (response.statusCode == 200) return response.body;
        debugPrint(
          '[MaoYan] _request兜底 $scheme -> HTTP ${response.statusCode}',
        );
      } catch (e) {
        debugPrint('[MaoYan] _request兜底 $scheme -> ERROR: $e');
      }
    }

    final triedList = attempted.isEmpty ? baseUrl : attempted.join(', ');
    throw NovelSourceException('所有章节接口请求均失败（已尝试：$triedList）');
  }

  /// Web 端并行竞速：限制域名数量，任一成功立即返回，不等待其它请求超时。
  Future<String> _requestParallel(
    String safePath,
    Map<String, String> mergedHeaders,
  ) async {
    final attempts = <(Uri, Map<String, String>, String)>[];
    var domainCount = 0;

    // Web 通过代理，上游只支持 HTTP，跳过 HTTPS 避免超时
    final schemes = kIsWeb ? ['http'] : ['https', 'http'];

    for (final (domain, uType) in domains) {
      if (domainCount >= _maxDomainAttempts) break;
      domainCount++;

      for (final scheme in schemes) {
        final host = '$scheme://api.$domain.com';
        final fullUrl = safePath.startsWith('http')
            ? safePath
            : '$host$safePath';
        final requestUrl = kIsWeb ? _toProxyUrl(fullUrl) : fullUrl;

        final domainHeaders = Map<String, String>.from(mergedHeaders);
        if (uType < aesKeys.length && uType < authTokens.length) {
          domainHeaders['client-device'] = md5
              .convert(utf8.encode(aesKeys[uType]))
              .toString();
          domainHeaders['Authorization'] = authTokens[uType];
        }

        final tmpUri = Uri.tryParse(requestUrl);
        if (tmpUri == null) continue;
        attempts.add((tmpUri, domainHeaders, '$scheme://$domain'));
      }
    }

    if (attempts.isEmpty) throw NovelSourceException('没有可用的域名配置');

    final completer = Completer<String>();
    var remaining = attempts.length;
    Object? lastError;
    bool cancelled = false;

    void failOne(Object error) {
      if (cancelled) return;
      lastError = error;
      remaining--;
      if (remaining <= 0 && !completer.isCompleted) {
        completer.completeError(
          NovelSourceException('所有章节接口请求均失败: $lastError'),
        );
      }
    }

    void cancelAll() {
      if (cancelled) return;
      cancelled = true;
      // 标记所有未完成请求为已取消，让它们快速失败
      remaining = 0;
    }

    for (final (requestUri, reqHeaders, key) in attempts) {
      unawaited(
        _httpClient
            .get(requestUri, headers: reqHeaders, timeout: _timeout)
            .then((response) {
              if (cancelled || completer.isCompleted) return;
              if (response.statusCode == 200 && response.body.isNotEmpty) {
                cancelAll();
                completer.complete(response.body);
                return;
              }
              failOne('[$key] HTTP ${response.statusCode}');
            })
            .catchError((e) {
              debugPrint('[MaoYan] _request $key -> $e');
              if (!cancelled && !completer.isCompleted) failOne(e);
            }),
      );
    }

    try {
      return await completer.future.timeout(
        _timeout + const Duration(seconds: 1),
      ).whenComplete(() => cancelAll());
    } catch (_) {
      // 主域名池失败后，兜底尝试 baseUrl（仅 2 次）。
    }

    for (final scheme in ['https', 'http']) {
      final fallbackBase = baseUrl.replaceFirst(
        RegExp(r'^https?://'),
        '$scheme://',
      );
      final fullFallbackUrl = safePath.startsWith('http')
          ? safePath
          : '$fallbackBase$safePath';
      final fbRequestUrl = kIsWeb ? _toProxyUrl(fullFallbackUrl) : fullFallbackUrl;
      final fallbackHeaders = Map<String, String>.from(mergedHeaders);
      if (domains.isNotEmpty && aesKeys.isNotEmpty && authTokens.isNotEmpty) {
        final firstType = domains.first.$2;
        if (firstType < aesKeys.length && firstType < authTokens.length) {
          fallbackHeaders['client-device'] = md5
              .convert(utf8.encode(aesKeys[firstType]))
              .toString();
          fallbackHeaders['Authorization'] = authTokens[firstType];
        }
      }
      final fbUri = Uri.tryParse(fbRequestUrl);
      if (fbUri == null) continue;
      try {
        final response = await _httpClient.get(
          fbUri,
          headers: fallbackHeaders,
          timeout: _timeout,
        );
        if (response.statusCode == 200 && response.body.isNotEmpty) {
          return response.body;
        }
      } catch (_) {}
    }

    final triedDomains = attempts.map((a) => a.$3).toSet().join(', ');
    throw NovelSourceException('所有章节接口请求均失败（已尝试：$triedDomains）');
  }

  /// 对路径中的非 ASCII 字符做百分号编码
  static String _percentEncodePath(String path) {
    final buffer = StringBuffer();
    for (final cp in path.runes) {
      if (cp < 128) {
        buffer.writeCharCode(cp);
      } else {
        // 非 ASCII → percent-encode
        final bytes = utf8.encode(String.fromCharCode(cp));
        for (final b in bytes) {
          buffer.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
        }
      }
    }
    return buffer.toString();
  }

  // ── AES 解密（章节路径） ──

  static String decryptChapterPath(String encrypted, String aesKey) {
    try {
      const iv = '0123456789abcdef';
      final encrypter = enc.Encrypter(
        enc.AES(
          enc.Key.fromUtf8(aesKey),
          mode: enc.AESMode.cbc,
          padding: 'PKCS7',
        ),
      );
      return encrypter.decrypt64(encrypted, iv: enc.IV.fromUtf8(iv));
    } catch (_) {
      return encrypted;
    }
  }

  // ── 工具方法 ──

  String _str(dynamic v) => v == null ? '' : v.toString().trim();

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

  dynamic _mapValue(dynamic node, String key) {
    if (node is! Map) return null;
    if (node.containsKey(key)) return node[key];
    final lower = key.toLowerCase();
    for (final e in node.entries) {
      if (e.key.toString().toLowerCase() == lower) return e.value;
    }
    return null;
  }

  String _cleanText(String input) {
    if (input.isEmpty) return '';

    // 1. 先剥离 HTML 标签（保留换行语义）
    var text = input
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<p[^>]*>', caseSensitive: false), '')
        .replaceAll(
          RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<[^>]+>'), '');

    // 2. 解码 HTML 实体（&amp; &lt; &gt; &quot; &nbsp; &#12345; 等）
    //    html 包的 parse 会把内容放在 <html><body> 里，我们取 body 的 text
    final document = html_parser.parse(text);
    final body = document.body;
    if (body != null) {
      // 用递归方式提取 text，保留换行
      text = _extractTextWithNewlines(body);
    }

    // 3. 合并多余换行和空白
    text = TextCleaner.normalizeWhitespace(text);

    return text;
  }

  /// 从 DOM 节点递归提取文本，块级元素后插入换行
  String _extractTextWithNewlines(dynamic node) {
    final buffer = StringBuffer();
    _walkNodes(node, buffer);
    return buffer.toString();
  }

  void _walkNodes(dynamic node, StringBuffer buffer) {
    if (node is dom.Text) {
      buffer.write(node.text);
      return;
    }
    if (node is! dom.Element) return;

    const blockTags = {
      'p',
      'div',
      'br',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'li',
      'tr',
      'blockquote',
      'pre',
      'section',
      'article',
    };

    final tagName = node.localName?.toLowerCase() ?? '';

    if (tagName == 'br') {
      buffer.write('\n');
      return;
    }

    for (final child in node.nodes) {
      _walkNodes(child, buffer);
    }

    if (blockTags.contains(tagName)) {
      buffer.write('\n');
    }
  }

  // ── NovelSource 实现 ──

  @override
  Future<List<NovelBook>> searchBooks(String keyword, {int page = 1}) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return [];

    // 搜索 URL
    final searchPath = '/search?keyword=${Uri.encodeComponent(kw)}&page=$page';
    final body = await _request(searchPath);
    final decoded = jsonDecode(body);
    final dataList = _readPath(decoded, ['data']);
    if (dataList is! List) return [];

    final books = <NovelBook>[];
    for (final item in dataList) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final novelId = _str(map['novelId']);
      final novelName = _str(map['novelName']);
      final authorName = _str(map['authorName']);
      if (novelId.isEmpty || novelName.isEmpty) continue;

      // 封面 URL 需要替换域名
      var coverUrl = _str(map['cover']);
      for (final (domain, _) in domains) {
        coverUrl = coverUrl.replaceAll(
          RegExp(r'http://api\.([a-z]+)\.com', caseSensitive: false),
          'http://api.$domain.com',
        );
        break;
      }

      books.add(
        NovelBook(
          id: novelId,
          title: novelName,
          author: authorName,
          intro: _str(map['summary'] ?? map['rankInfo']),
          coverUrl: coverUrl,
          detailUrl: encodeDataUrl('/novel/$novelId'),
          category: _str(map['className']),
          status: _str(map['status']).contains('完') ? '已完结' : '连载',
          wordCount: _str(map['wordNum']),
        ),
      );
    }

    return books;
  }

  @override
  Future<List<NovelBook>> fetchByPath(String path) async {
    // 探索页暂不支持 JS 生成
    return [];
  }

  @override
  Future<NovelDetail> fetchDetail({
    required String bookId,
    String? detailUrl,
  }) async {
    final id = bookId.trim();
    if (id.isEmpty) throw NovelSourceException('书籍 ID 为空');

    // 尝试使用 detailUrl（如果提供），否则用 bookId
    String detailPath;
    if (detailUrl != null && detailUrl.isNotEmpty) {
      detailPath = decodeDataUrl(detailUrl);
      if (detailPath.startsWith('http')) {
        // 已经是完整 URL 了，传给 _request 时会保持
      } else if (!detailPath.startsWith('/')) {
        detailPath = '/$detailPath';
      }
    } else {
      detailPath = '/novel/$id';
    }

    // 先请求详情
    String body;
    try {
      body = await _request(detailPath);
    } catch (e) {
      // 如果 detailPath 失败，尝试用 /novel/$id
      if (detailPath != '/novel/$id') {
        try {
          body = await _request('/novel/$id');
        } catch (e2) {
          throw NovelSourceException('详情接口请求失败: $e2');
        }
      } else {
        rethrow;
      }
    }

    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw NovelSourceException(
        '详情接口返回格式错误：不是 JSON 对象，而是 ${decoded.runtimeType}',
      );
    }

    // 尝试多种可能的 data 路径
    dynamic data;
    for (final key in ['data', 'result', 'novel', 'info']) {
      data = _readPath(decoded, [key]);
      if (data is Map) break;
    }
    // 如果没找到任何子字段，就用整个 decoded 对象
    data ??= decoded;
    if (data is! Map) {
      final snippet = body.length > 200 ? body.substring(0, 200) : body;
      throw NovelSourceException('Detail response format error: $snippet');
    }

    final map = Map<String, dynamic>.from(data);

    // 尝试多个可能的字段名
    String pickField(List<String> keys) {
      for (final k in keys) {
        final v = _str(map[k]);
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    // 封面 URL 替换域名
    var coverUrl = pickField(['cover', 'coverUrl', 'cover_url']);
    if (domains.isNotEmpty) {
      coverUrl = coverUrl.replaceAll(
        RegExp(r'http://api\.([a-z]+)\.com', caseSensitive: false),
        'http://api.${domains.first.$1}.com',
      );
    }

    // 从详情响应中提取真正的 novelId（可能与搜索结果的 bookId 不同）
    final detailNovelId = _str(
      map['novelId'] ??
          map['novel_id'] ??
          map['bookId'] ??
          map['id'] ??
          map['book_id'],
    );
    // 重点：用详情 API 返回的 novelId 构建章节 URL，而非搜索结果的 bookId
    final tocBookId = detailNovelId.isNotEmpty ? detailNovelId : id;

    // 状态字段兼容处理
    final statusRaw = map['status'] ?? map['state'] ?? '';
    final statusStr = statusRaw is String ? statusRaw : statusRaw.toString();

    final book = NovelBook(
      // 章节 ID 用详情 API 的 novelId
      id: tocBookId,
      title: _str(
        map['novelName'] ??
            map['novel_name'] ??
            map['bookName'] ??
            map['name'] ??
            map['book_name'] ??
            map['title'],
      ),
      author: _str(map['authorName'] ?? map['author'] ?? map['author_name']),
      intro: _str(
        map['summary'] ?? map['intro'] ?? map['description'] ?? map['desc'],
      ),
      coverUrl: coverUrl,
      detailUrl: detailUrl ?? encodeDataUrl('/novel/$tocBookId'),
      category: _str(
        map['category'] ?? map['className'] ?? map['class_name'] ?? map['kind'],
      ),
      status: statusStr.contains('完') ? '已完结' : '连载',
      wordCount: _str(
        map['wordNum'] ?? map['word_num'] ?? map['wordCount'] ?? map['words'],
      ),
    );

    // 获取章节列表 — 优先从详情响应中提取
    List<NovelChapter> chapters = _extractChaptersFromMap(map);

    // 详情响应中没有章节，尝试独立的章节目录接口
    if (chapters.isEmpty) {
      try {
        chapters = await _fetchChapters(id);
      } catch (e) {
        debugPrint('[MaoYan] Chapter endpoint failed: $e');
        // 不是致命错误 — 返回详情但不含章节列表，让用户知晓
      }
    }

    return NovelDetail(book: book, chapters: chapters);
  }

  /// 从详情响应 map 中提取章节列表（如果 API 直接返回了）
  List<NovelChapter> _extractChaptersFromMap(Map<String, dynamic> map) {
    // 检查 map 中是否有章节列表 — 优++ 书源用 data.list, 所以顶层也要搜 list
    for (final key in [
      'chapters',
      'chapterList',
      'list',
      'toc',
      'chapter_list',
      'items',
      'chapterItems',
    ]) {
      final val = map[key];
      if (val is List && val.isNotEmpty) {
        final chapters = _buildChaptersFromList(val);
        if (chapters.isNotEmpty) return chapters;
      }
    }
    // 检查嵌套字段（data → list, result → list 等）
    for (final outer in ['data', 'result', 'book', 'novel']) {
      final val = map[outer];
      if (val is Map) {
        for (final inner in [
          'chapters',
          'chapterList',
          'list',
          'items',
          'records',
        ]) {
          final innerVal = val[inner];
          if (innerVal is List && innerVal.isNotEmpty) {
            final chapters = _buildChaptersFromList(innerVal);
            if (chapters.isNotEmpty) return chapters;
          }
        }
      }
    }
    // 再试一层嵌套：data.data.list 之类的三层结构
    for (final outer1 in ['data', 'result']) {
      final v1 = map[outer1];
      if (v1 is Map) {
        for (final outer2 in ['data', 'result']) {
          final v2 = v1[outer2];
          if (v2 is Map) {
            for (final inner in ['chapters', 'chapterList', 'list', 'items']) {
              final innerVal = v2[inner];
              if (innerVal is List && innerVal.isNotEmpty) {
                final chapters = _buildChaptersFromList(innerVal);
                if (chapters.isNotEmpty) return chapters;
              }
            }
          }
        }
      }
    }
    return [];
  }

  Future<List<NovelChapter>> _fetchChapters(String bookId) async {
    Map<String, dynamic>? decoded;
    String? lastError;
    String? rawBody;

    // 尝试多个可能的章节路径格式
    final paths = [
      '/novel/$bookId/chapters',
      '/novel/$bookId/toc',
      '/novel/$bookId/chapterList',
      '/book/$bookId/chapters',
      // 额外尝试
      '/api/novel/$bookId/chapters',
      '/chapters?novelId=$bookId',
      '/novel/chapters?bookId=$bookId',
      '/api/chapters?bookId=$bookId',
      '/toc?bookId=$bookId',
    ];

    for (final path in paths) {
      try {
        final body = await _request(path);
        rawBody = body.length > 500 ? '${body.substring(0, 500)}...' : body;
        if (body.isEmpty) {
          lastError = 'empty body from $path';
          continue;
        }
        final parsed = jsonDecode(body);

        // 可能是 JSON 数组直接返回
        if (parsed is List) {
          final chapters = _buildChaptersFromList(parsed);
          if (chapters.isNotEmpty) return chapters;
          lastError = 'no valid chapters in array from $path';
          continue;
        }

        // 是 JSON 对象，搜索嵌套结构
        if (parsed is Map) {
          decoded = Map<String, dynamic>.from(parsed);
          final list = _deepFindList(decoded);
          if (list != null && list.isNotEmpty) {
            return _buildChaptersFromList(list);
          }
          lastError =
              'no list found in $path response: ${body.length > 200 ? '${body.substring(0, 200)}...' : body}';
          continue;
        }

        lastError = 'unexpected type (${parsed.runtimeType}) from $path';
      } catch (e) {
        lastError = '$path: $e';
        continue;
      }
    }

    // All paths failed — diagnostic
    final msg = '章节独立接口全部失败，已尝试: ${paths.join(", ")}. 最后错误: $lastError';
    debugPrint('[MaoYan] $msg');
    if (rawBody != null) debugPrint('[MaoYan] Raw response snippet: $rawBody');
    return [];
  }

  /// 从已找到的列表构建 Chapter 对象
  List<NovelChapter> _buildChaptersFromList(List<dynamic> list) {
    final chapters = <NovelChapter>[];
    for (final item in list) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);

      final chapterName = _pickField(map, [
        'chapterName',
        'chapter_name',
        'name',
        'title',
      ]);
      var rawPath = _pickField(map, [
        'path',
        'url',
        'chapterUrl',
        'chapter_url',
        'link',
        'href',
      ]);

      if (chapterName.isEmpty || rawPath.isEmpty) continue;

      // 尝试用 aesKey 解密章节路径
      var decrypted = _tryDecryptAll(rawPath);
      if (decrypted != null) rawPath = decrypted;

      // 清理 URL 中的域名部分
      rawPath = rawPath.replaceAll(
        RegExp(r'https?://api\.([a-z]+)\.com', caseSensitive: false),
        '',
      );

      // 确保没有多余前缀
      if (!rawPath.startsWith('/') && !rawPath.startsWith('http')) {
        rawPath = '/$rawPath';
      }

      chapters.add(
        NovelChapter(
          title: chapterName,
          url: rawPath.startsWith('http') ? rawPath : encodeDataUrl(rawPath),
        ),
      );
    }
    return chapters;
  }

  /// 递归搜索 JSON 中第一个看起来像章节列表的数组
  dynamic _deepFindList(Map? root, [int depth = 0]) {
    if (root == null) return null;
    if (depth > 3) return null;

    // 优先搜索的键路径
    const prioritized = [
      ['data', 'list'],
      ['data', 'chapters'],
      ['data', 'chapterList'],
      ['data', 'items'],
      ['data', 'records'],
      ['data', 'rows'],
      ['data', 'data'],
      ['result', 'list'],
      ['result', 'chapters'],
      ['chapters'],
      ['list'],
      ['items'],
      ['records'],
      ['chapterList'],
      ['data', 'result', 'list'],
      ['data', 'result', 'chapters'],
    ];

    for (final path in prioritized) {
      dynamic val = root;
      bool ok = true;
      for (final seg in path) {
        if (val is Map) {
          val = _mapValue(val, seg);
          if (val == null) {
            ok = false;
            break;
          }
        } else {
          ok = false;
          break;
        }
      }
      if (ok && val is List && val.isNotEmpty) return val;
    }

    // 搜索任何 Map 值下的 list/chapters 字段
    for (final entry in root.entries) {
      if (entry.value is Map) {
        final result = _deepFindList(entry.value as Map, depth + 1);
        if (result is List && result.isNotEmpty) return result;
      }
      // 直接是数组的顶层字段
      if (entry.value is List) {
        final list = entry.value as List;
        if (list.isNotEmpty && list.first is Map) return list;
      }
    }

    return null;
  }

  /// 尝试用所有已知 aesKey 解密
  String? _tryDecryptAll(String encrypted) {
    for (final aesKey in aesKeys) {
      try {
        const iv = '0123456789abcdef';
        final encrypter = enc.Encrypter(
          enc.AES(
            enc.Key.fromUtf8(aesKey),
            mode: enc.AESMode.cbc,
            padding: 'PKCS7',
          ),
        );
        final decrypted = encrypter.decrypt64(
          encrypted,
          iv: enc.IV.fromUtf8(iv),
        );
        if (decrypted.isNotEmpty && !decrypted.contains(' ')) return decrypted;
      } catch (_) {}
    }
    return null;
  }

  String _pickField(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      final v = _str(map[k]);
      if (v.isNotEmpty) return v;
    }
    return '';
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
    final contentUrl = decodeDataUrl(chapter.url);
    final body = await _request(contentUrl);
    final decoded = jsonDecode(body);

    String content = '';
    String chapterTitle = chapter.title;

    if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);

      // 深度递归搜索正文内容（最多 4 层）
      content = _deepFindContent(decoded, 0, 4) ?? '';

      // 尝试提取章节标题
      for (final key in ['title', 'chapterTitle', 'chapter_name', 'name']) {
        final v = _str(map[key]);
        if (v.isNotEmpty) {
          chapterTitle = v;
          break;
        }
        // 在 data 子树中找
        final sub = map['data'];
        if (sub is Map) {
          final sv = _str(sub[key]);
          if (sv.isNotEmpty) {
            chapterTitle = sv;
            break;
          }
        }
      }
    } else if (decoded is String) {
      content = decoded;
    }

    if (content.isEmpty) {
      final snippet = body.length > 300 ? body.substring(0, 300) : body;
      throw NovelSourceException('章节内容为空，响应摘要: $snippet');
    }

    return ChapterContent(
      title: chapterTitle,
      content: _cleanText(content),
      chapterIndex: chapterIndex,
      sourceUrl: chapter.url,
      fromCache: false,
    );
  }

  /// 深度递归搜索 JSON 树中的字符串内容字段
  String? _deepFindContent(dynamic node, int depth, int maxDepth) {
    if (depth > maxDepth) return null;
    if (node is String) {
      // 找到足够长的字符串就认为是正文
      if (node.trim().length > 20) return node;
      return null;
    }
    if (node is Map) {
      final map = Map<String, dynamic>.from(node);
      // 优先检查常见内容字段名
      for (final key in [
        'content',
        'text',
        'body',
        'chapterContent',
        'chapter_content',
        'value',
        'data',
      ]) {
        final v = map[key];
        if (v is String && v.trim().length > 20) return v;
      }
      // 递归搜索所有值
      for (final entry in map.entries) {
        final result = _deepFindContent(entry.value, depth + 1, maxDepth);
        if (result != null) return result;
      }
    }
    if (node is List) {
      for (final item in node) {
        final result = _deepFindContent(item, depth + 1, maxDepth);
        if (result != null) return result;
      }
    }
    return null;
  }
}
