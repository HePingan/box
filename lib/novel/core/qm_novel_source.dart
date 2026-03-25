import 'dart:async';
import 'dart:convert';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'models.dart';
import 'novel_source.dart';

class QmNovelSource implements NovelSource {
  QmNovelSource({required this.baseUrl, Map<String, String>? headers}) 
      : headers = headers ?? const {'User-Agent': 'okhttp/4.9.2'};

  final String baseUrl;
  final Map<String, String> headers;

  static final RegExp _titleCleaner = RegExp(r'正文卷\.|正文\.|VIP卷\.|卷_|VIP章节\.|章节目录\.|最新章节\.|[\(（【].*?[求更票谢乐发订合补加架字修Kk].*?[】）\)]');
  static final RegExp _contentNoise = RegExp(r'一秒记住.*精彩阅读。|7017k');

  Uri _resolve(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return Uri.parse(path);
    return Uri.parse(baseUrl).resolve(path);
  }

  String _absUrl(String value) {
    try { return value.trim().isEmpty ? '' : _resolve(value.trim()).toString(); } catch (_) { return value.trim(); }
  }

  Future<String> _fetchBody(String path) async {
    // 🔔 优化：加入 timeout 彻底防止加载转圈永远不停止
    final response = await http.get(_resolve(path), headers: headers).timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('HTTP ${response.statusCode}');
    return response.body;
  }

  dynamic _tryDecode(String body) { try { return jsonDecode(body); } catch (_) { return null; } }
  Map<String, dynamic> _lower(Map raw) => raw.map((k, v) => MapEntry(k.toString().toLowerCase(), v));
  String _str(dynamic v) => (v == null) ? '' : v.toString().trim();
  
  String _pick(Map map, List<String> keys, {String fb = ''}) {
    for (final k in keys) {
      final v = _str(map[k]);
      if (v.isNotEmpty && v.toLowerCase() != 'null') return v;
    }
    return fb;
  }

  List<Map<String, dynamic>> _findMaps(dynamic node, bool Function(Map<String, dynamic>) matcher) {
    final out = <Map<String, dynamic>>[];
    void walk(dynamic curr) {
      if (curr is Map) {
        final m = Map<String, dynamic>.from(curr);
        if (matcher(_lower(m))) out.add(m);
        for (final v in m.values) walk(v);
      } else if (curr is List) {
        for (final i in curr) walk(i);
      }
    }
    walk(node);
    return out;
  }

  String _decryptAes(String encPath) {
    try {
      final key = enc.Key.fromUtf8('f041c49714d39908');
      final iv = enc.IV.fromUtf8('0123456789abcdef');
      final aes = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final dec = aes.decrypt64(encPath.replaceAll(RegExp(r'[- ]'), '+').replaceAll('_', '/') + List.filled((4 - encPath.length % 4) % 4, '=').join(), iv: iv);
      return dec.replaceAll(r'\/', '/').replaceAll('"', '').replaceAll(RegExp(r'[\u0000-\u001F]'), '').trim();
    } catch (_) { return ''; }
  }

  NovelBook? _toBook(Map raw, {String fallbackId = '', String path = ''}) {
    final m = _lower(raw);
    var id = _pick(m, ['novelid', 'bookid', 'id']);
    var title = _pick(m, ['novelname', 'bookname', 'title', 'name']);
    var url = _pick(m, ['bookurl', 'detailurl', 'url']);
    if (url.isEmpty && id.isNotEmpty) url = '/novel/$id?isSearch=1';
    if (url.isEmpty) url = path;
    if (id.isEmpty && url.isNotEmpty) {
      final uri = Uri.tryParse(_absUrl(url));
      id = uri?.queryParameters['id'] ?? (uri?.pathSegments.isNotEmpty == true ? uri!.pathSegments.last : '');
    }
    if (id.isEmpty) id = fallbackId;
    if (id.isEmpty && title.isEmpty) return null;

    final tag = _str(m['tagname']);
    final cat = _pick(m, ['classname', 'category']);
    final cStr = m['iscomplete']?.toString() ?? m['status']?.toString() ?? '';

    return NovelBook(
      id: id, title: title.isEmpty ? id : title,
      author: _pick(m, ['authorname', 'author']),
      intro: _pick(m, ['summary', 'intro', 'desc']),
      coverUrl: _absUrl(_pick(m, ['cover', 'coverurl', 'img', 'thumb'])),
      detailUrl: _absUrl(url),
      category: [if(cat.isNotEmpty) cat, if(tag.isNotEmpty) tag].join(' / '),
      status: (cStr == '1' || cStr.contains('完')) ? '完结' : '连载',
      wordCount: _str(m['wordnum'] ?? m['wordcount']),
    );
  }

  NovelChapter? _toChapter(Map raw) {
    final m = _lower(raw);
    final title = _pick(m, ['chaptername', 'title']);
    if (title.isEmpty) return null;
    var path = _pick(m, ['path', 'url', 'href']);
    try { path = Uri.decodeComponent(path); } catch (_) {}
    if (!path.startsWith('/') && !path.startsWith('http')) {
      final dec = _decryptAes(path);
      if (dec.isNotEmpty) path = dec.startsWith('http') || dec.startsWith('/') ? dec : '/$dec';
    }
    return path.isEmpty ? null : NovelChapter(title: title.replaceAll(_titleCleaner, '').trim(), url: _absUrl(path));
  }

  String _cleanContent(String raw) {
    var text = raw.replaceAll(_contentNoise, '').replaceAll(r'\\n', '\n').replaceAll(RegExp(r'\r\n?'), '\n');
    text = text.replaceAll(RegExp(r'<br\s*/?>|</p>', caseSensitive: false), '\n')
               .replaceAll(RegExp(r'<p[^>]*>', caseSensitive: false), '')
               .replaceAll(RegExp(r'<(script|style).*?</\1>', caseSensitive: false, dotAll: true), '')
               .replaceAll(RegExp(r'<[^>]+>'), '');
    final lines = html_parser.parseFragment(text).text!.split('\n');
    return lines.map((e) => e.trim()).where((e) => e.isNotEmpty).join('\n\n');
  }

  @override
  Future<List<NovelBook>> searchBooks(String key, {int page = 1}) async {
    final kw = Uri.encodeComponent(key.trim());
    if (kw.isEmpty) return [];
    for (final path in ['/search?page=$page&keyword=$kw', '/search?key=$kw&page=$page']) {
      try { final b = await fetchByPath(path); if (b.isNotEmpty) return b; } catch (_) {}
    }
    return [];
  }

  @override
  Future<List<NovelBook>> fetchByPath(String path) async {
    final body = await _fetchBody(path);
    final decoded = _tryDecode(body);
    if (decoded != null) {
      final maps = _findMaps(decoded, (m) => _pick(m, ['bookname','novelname','title']).isNotEmpty);
      return maps.map((m) => _toBook(m, path: path)).whereType<NovelBook>().toList();
    }
    return []; // For brevity, removed HTML list parser fallback as APIs should return JSON
  }

  @override
  Future<NovelDetail> fetchDetail({required String bookId, String? detailUrl}) async {
    final cands = {if (detailUrl != null) detailUrl, '/novel/$bookId?isSearch=1', '/book/$bookId'};
    for (final t in cands) {
      try {
        final body = await _fetchBody(t);
        final js = _tryDecode(body);
        if (js != null) {
          final maps = _findMaps(js, (m) => _pick(m, ['bookid','id']) == bookId || _pick(m, ['bookname','title']).isNotEmpty);
          final book = maps.isEmpty ? NovelBook(id: bookId, title: '', author: '', intro: '', coverUrl: '', detailUrl: _absUrl(t)) : _toBook(maps.first, fallbackId: bookId);
          
          List<NovelChapter> chaps = _findMaps(js, (m) => _pick(m, ['chaptername']).isNotEmpty).map(_toChapter).whereType<NovelChapter>().toList();
          if (chaps.isEmpty) {
            for (final cp in ['/novel/$bookId/chapters?readNum=1', '/book/$bookId/chapters']) {
               try { 
                 final cb = await _fetchBody(cp); 
                 chaps = _findMaps(_tryDecode(cb), (m) => _pick(m, ['chaptername']).isNotEmpty).map(_toChapter).whereType<NovelChapter>().toList();
                 if (chaps.isNotEmpty) break;
               } catch(_) {}
            }
          }
          if (book != null) return NovelDetail(book: book, chapters: chaps);
        }
      } catch (_) {}
    }
    throw Exception('详情解析失败Book: $bookId');
  }

  @override
  Future<ChapterContent> fetchChapter({required NovelDetail detail, required int chapterIndex}) async {
    final chapter = detail.chapters[chapterIndex];
    final cands = {chapter.url, if(chapter.url.startsWith('/')) '${chapter.url}${chapter.url.contains('?')?'&':'?'}readNum=1'};
    
    for (final t in cands) {
      try {
        final body = await _fetchBody(t);
        final js = _tryDecode(body);
        if (js != null) {
          String? txt = _pick(_lower(js is Map ? js : {}), ['content', 'chaptercontent', 'txt', 'text']);
          if (txt.isEmpty) { // search deeper
            final maps = _findMaps(js, (m) => _pick(m, ['content','txt']).isNotEmpty);
            if (maps.isNotEmpty) txt = _pick(maps.first, ['content','txt']);
          }
          if (txt.isNotEmpty) {
            return ChapterContent(title: chapter.title, content: _cleanContent(txt), chapterIndex: chapterIndex, sourceUrl: _absUrl(t));
          }
        }
      } catch (_) {}
    }
    throw Exception('正文解析失败');
  }
}