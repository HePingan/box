import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import 'models.dart';
import 'video_source.dart';

class ArchiveVideoSource implements VideoSource {
  ArchiveVideoSource({
    String baseUrl = 'https://archive.org',
    this.pageSize = 20,
    Map<String, String>? headers,
  })  : baseUrl = baseUrl.replaceAll(RegExp(r'/$'), ''),
        _headers = headers ??
            const {
              'User-Agent': 'Mozilla/5.0 (Flutter Box Video)',
              'Accept': 'application/json,text/plain,*/*',
            };

  final String baseUrl;
  final int pageSize;
  final Map<String, String> _headers;

  static const String _providerKey = 'archive';

  @override
  String get sourceName => 'Internet Archive';

  @override
  List<VideoCategory> get categories => const [
        VideoCategory(
          id: 'classic-film',
          title: '经典电影',
          query: 'classic film',
          description: '公共版权经典电影',
        ),
        VideoCategory(
          id: 'documentary',
          title: '纪录片',
          query: 'documentary',
          description: '纪录、教育、自然类视频',
        ),
        VideoCategory(
          id: 'tv-series',
          title: '电视剧集',
          query: 'tv episode',
          description: '老电视节目 / 剧集',
        ),
        VideoCategory(
          id: 'short-film',
          title: '短片',
          query: 'short film',
          description: '短片、样片、实验视频',
        ),
      ];

  @override
  Future<List<VideoItem>> searchVideos(String keyword, {int page = 1}) {
    final q = keyword.trim().isEmpty ? 'classic film' : keyword.trim();
    return _search(q, page: page);
  }

  @override
  Future<List<VideoItem>> fetchByPath(String path, {int page = 1}) {
    final q = path.trim().isEmpty ? 'classic film' : path.trim();
    return _search(q, page: page);
  }

  @override
  Future<VideoDetail> fetchDetail({
    required VideoItem item,
  }) async {
    final identifier = _extractIdentifier(item);

    if (identifier.isEmpty) {
      throw StateError('视频标识为空，无法获取详情');
    }

    final uri = Uri.parse('$baseUrl/metadata/$identifier');
    final response = await http.get(uri, headers: _headers);

    if (response.statusCode != 200) {
      throw StateError('获取视频详情失败: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('详情数据格式错误');
    }

    final metadataRaw = decoded['metadata'];
    final metadata = metadataRaw is Map
        ? Map<String, dynamic>.from(metadataRaw)
        : <String, dynamic>{};

    final filesRaw = decoded['files'];
    final files = filesRaw is List
        ? filesRaw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];

    final mergedItem = _itemFromMetadata(identifier, metadata, item.detailUrl).copyWith(
      title: item.title.isNotEmpty ? item.title : _readText(metadata['title'], fallback: item.title),
      intro: _stripHtml(_readText(metadata['description'])).isNotEmpty
          ? _stripHtml(_readText(metadata['description']))
          : item.intro,
    );

    final episodes = _buildEpisodes(identifier, files);
    if (episodes.isEmpty) {
      throw StateError('未找到可播放文件');
    }

    final creator = _readText(metadata['creator']).isNotEmpty
        ? _readText(metadata['creator'])
        : _readText(metadata['director']).isNotEmpty
            ? _readText(metadata['director'])
            : _readText(metadata['uploader']);

    final description = _stripHtml(_readText(metadata['description']));
    final tags = <String>{
      ..._stringList(metadata['subject']),
      ..._stringList(metadata['collection']),
    }.toList();

    return VideoDetail(
      item: mergedItem,
      cover: mergedItem.cover,
      creator: creator,
      description: description.isNotEmpty ? description : mergedItem.intro,
      tags: tags,
      playSources: [
        VideoPlaySource(
          name: '主片源',
          episodes: episodes,
        ),
      ],
      sourceUrl: item.detailUrl.isNotEmpty ? item.detailUrl : '$baseUrl/details/$identifier',
    );
  }

  Future<List<VideoItem>> _search(String query, {required int page}) async {
    try {
      final expression = _buildSearchExpression(query);

      final uri = Uri.parse('$baseUrl/advancedsearch.php').replace(
        queryParameters: {
          'q': [expression],
          'fl[]': [
            'identifier',
            'title',
            'description',
            'year',
            'subject',
            'collection',
            'creator',
          ],
          'rows': ['$pageSize'],
          'page': ['$page'],
          'output': ['json'],
          'sort[]': ['downloads desc'],
        },
      );

      final response = await http.get(uri, headers: _headers);

      if (response.statusCode != 200) return const [];

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const [];

      final resp = decoded['response'];
      if (resp is! Map) return const [];

      final docs = resp['docs'];
      if (docs is! List) return const [];

      return docs
          .whereType<Map>()
          .map((e) => _docToItem(Map<String, dynamic>.from(e)))
          .whereType<VideoItem>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  String _buildSearchExpression(String query) {
    final q = query.replaceAll('"', ' ').trim();
    if (q.isEmpty) {
      return 'mediatype:(movies)';
    }
    return '(title:("$q") OR description:("$q") OR subject:("$q")) AND mediatype:(movies)';
  }

  VideoItem? _docToItem(Map<String, dynamic> doc) {
    final identifier = _readText(doc['identifier']);
    if (identifier.isEmpty) return null;

    final title = _readText(doc['title'], fallback: identifier);
    final intro = _stripHtml(_readText(doc['description']));
    final yearText = _readText(doc['year']);
    final category =
        _firstText(doc['subject']) ?? _firstText(doc['collection']) ?? '公共版权视频';

    return VideoItem(
      id: '$_providerKey::$identifier',
      title: title,
      intro: intro,
      cover: 'https://archive.org/services/img/$identifier',
      detailUrl: '$baseUrl/details/$identifier',
      category: category,
      yearText: yearText,
      sourceName: sourceName,
      providerKey: _providerKey,
    );
  }

  VideoItem _itemFromMetadata(
    String identifier,
    Map<String, dynamic> metadata,
    String? detailUrl,
  ) {
    final title = _readText(metadata['title'], fallback: identifier);
    final intro = _stripHtml(_readText(metadata['description']));
    final yearText = _readText(metadata['year']);
    final category =
        _firstText(metadata['subject']) ?? _firstText(metadata['collection']) ?? '公共版权视频';

    return VideoItem(
      id: '$_providerKey::$identifier',
      title: title,
      intro: intro,
      cover: 'https://archive.org/services/img/$identifier',
      detailUrl: detailUrl ?? '$baseUrl/details/$identifier',
      category: category,
      yearText: yearText,
      sourceName: sourceName,
      providerKey: _providerKey,
    );
  }

  List<VideoEpisode> _buildEpisodes(
    String identifier,
    List<Map<String, dynamic>> files,
  ) {
    final playable = files.where(_isPlayableFile).toList()
      ..sort((a, b) {
        final scoreA = _scoreFile(a);
        final scoreB = _scoreFile(b);
        if (scoreA != scoreB) return scoreA.compareTo(scoreB);

        final sizeA = _toInt(a['size']);
        final sizeB = _toInt(b['size']);
        return sizeB.compareTo(sizeA);
      });

    final seenNames = <String>{};
    final episodes = <VideoEpisode>[];

    for (final file in playable) {
      final name = _readText(file['name']);
      if (name.isEmpty || !seenNames.add(name)) continue;

      episodes.add(
        VideoEpisode(
          title: _episodeTitle(file, episodes.length),
          url: '$baseUrl/download/$identifier/${_encodePath(name)}',
          index: episodes.length,
          durationText: _readText(file['length']),
        ),
      );
    }

    return episodes;
  }

  bool _isPlayableFile(Map<String, dynamic> file) {
    final name = _readText(file['name']).toLowerCase();
    final format = _readText(file['format']).toLowerCase();
    final mime = _readText(file['mimetype']).toLowerCase();

    if (name.isEmpty) return false;

    final extOk = name.endsWith('.mp4') ||
        name.endsWith('.m4v') ||
        name.endsWith('.webm') ||
        name.endsWith('.ogv') ||
        name.endsWith('.mov');

    final formatOk = format.contains('mpeg4') ||
        format.contains('h.264') ||
        format.contains('h264') ||
        format.contains('webm') ||
        format.contains('quicktime') ||
        format.contains('ogg video');

    final mimeOk = mime.startsWith('video/');

    return extOk || formatOk || mimeOk;
  }

  int _scoreFile(Map<String, dynamic> file) {
    final name = _readText(file['name']).toLowerCase();
    final format = _readText(file['format']).toLowerCase();

    if (name.endsWith('.mp4') || format.contains('mpeg4') || format.contains('h.264')) return 0;
    if (name.endsWith('.m4v')) return 1;
    if (name.endsWith('.webm')) return 2;
    if (name.endsWith('.ogv')) return 3;
    if (name.endsWith('.mov')) return 4;
    return 9;
  }

  String _episodeTitle(Map<String, dynamic> file, int index) {
    final title = _readText(file['title']);
    if (title.isNotEmpty) return title;

    final name = _readText(file['name']);
    if (name.isNotEmpty) return name.split('/').last;

    return '片源 ${index + 1}';
  }

  String _encodePath(String raw) {
    return raw.split('/').map(Uri.encodeComponent).join('/');
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(_readText(value)) ?? 0;
  }

  String _stripHtml(String text) {
    if (text.trim().isEmpty) return '';
    try {
      return html_parser.parseFragment(text).text?.trim() ?? text.trim();
    } catch (_) {
      return text.trim();
    }
  }

  String _readText(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    if (value is String) {
      final v = value.trim();
      return v.isEmpty ? fallback : v;
    }
    if (value is num || value is bool) return value.toString();
    if (value is List && value.isNotEmpty) {
      final first = _readText(value.first);
      return first.isNotEmpty ? first : fallback;
    }
    final v = value.toString().trim();
    return v.isEmpty ? fallback : v;
  }

  String? _firstText(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    if (value is List) {
      for (final item in value) {
        final text = _readText(item);
        if (text.isNotEmpty) return text;
      }
    }
    return null;
  }

  List<String> _stringList(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      return value
          .split(RegExp(r'[;,]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (value is List) {
      return value
          .map((e) => _readText(e))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  String _extractIdentifier(VideoItem item) {
    if (item.id.contains('::')) {
      return item.id.split('::').last.trim();
    }

    if (item.detailUrl.trim().isEmpty) return '';
    final uri = Uri.tryParse(item.detailUrl);
    if (uri == null) return '';

    final segments = uri.pathSegments;
    if (segments.isEmpty) return '';

    final detailsIndex = segments.indexOf('details');
    if (detailsIndex >= 0 && detailsIndex + 1 < segments.length) {
      return segments[detailsIndex + 1];
    }

    return segments.last;
  }
}