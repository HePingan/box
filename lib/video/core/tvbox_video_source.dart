import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'play_source_parser.dart';
import 'video_source.dart';

class TvBoxVideoSource implements VideoSource {
  final String configUrl;

  String _apiBaseUrl = '';
  String _siteName = 'TVBox 源';
  bool _initialized = false;

  TvBoxVideoSource({
    this.configUrl = 'http://饭太硬.com/tv/',
  });

  @override
  String get sourceName => _siteName;

  String get _providerKey {
    final host = Uri.tryParse(_apiBaseUrl)?.host ?? 'tvbox';
    return 'tvbox::$host';
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      final res = await http.get(Uri.parse(configUrl));
      final decoded = jsonDecode(res.body);
      final sites = decoded['sites'] as List;

      final site = sites.firstWhere((s) => s['type'] == 1 || s['type'] == 0);
      _apiBaseUrl = site['api'].toString();
      _siteName = (site['name'] ?? 'TVBox 站点').toString();
      _initialized = true;
    } catch (e) {
      throw Exception('初始化 TVBox 接口失败: $e');
    }
  }

  @override
  List<VideoCategory> get categories => const [
        VideoCategory(id: '1', title: '电影', query: '1', description: '电影内容'),
        VideoCategory(id: '2', title: '剧集', query: '2', description: '剧集内容'),
        VideoCategory(id: '3', title: '综艺', query: '3', description: '综艺内容'),
        VideoCategory(id: '4', title: '动漫', query: '4', description: '动漫内容'),
      ];

  @override
  Future<List<VideoItem>> searchVideos(String keyword, {int page = 1}) async {
    await _ensureInitialized();
    final url =
        '$_apiBaseUrl?ac=videolist&wd=${Uri.encodeComponent(keyword)}&pg=$page';
    return _fetchCmsList(url);
  }

  @override
  Future<List<VideoItem>> fetchByPath(String path, {int page = 1}) async {
    await _ensureInitialized();
    final url = '$_apiBaseUrl?ac=videolist&t=$path&pg=$page';
    return _fetchCmsList(url);
  }

  @override
  Future<VideoDetail> fetchDetail({
    required VideoItem item,
  }) async {
    await _ensureInitialized();

    final rawId = _extractRawId(item.id);
    final url = '$_apiBaseUrl?ac=videolist&ids=$rawId';
    final res = await http.get(Uri.parse(url));
    final decoded = jsonDecode(res.body);

    final list = decoded['list'];
    if (list is! List || list.isEmpty) {
      throw Exception('未找到详情数据');
    }

    final data = Map<String, dynamic>.from(list.first);
    final detailItem = _toVideoItem(data);

    final description = (data['vod_content'] ?? item.intro).toString().trim();
    final playSources = parseMacCmsPlaySources(
      playFrom: data['vod_play_from'],
      playUrl: data['vod_play_url'],
    );

    return VideoDetail(
      item: detailItem.copyWith(
        intro: description.isNotEmpty ? description : detailItem.intro,
      ),
      cover: detailItem.cover,
      creator: (data['vod_director'] ?? '未知').toString(),
      description: description,
      tags: [
        (data['vod_type'] ?? '').toString(),
        (data['vod_year'] ?? '').toString(),
        (data['vod_area'] ?? '').toString(),
      ].where((e) => e.trim().isNotEmpty).toList(),
      playSources: playSources,
      sourceUrl: _apiBaseUrl,
    );
  }

  Future<List<VideoItem>> _fetchCmsList(String url) async {
    try {
      final res = await http.get(Uri.parse(url));
      final decoded = jsonDecode(res.body);
      final list = decoded['list'] as List;
      return list
          .map((e) => _toVideoItem(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  VideoItem _toVideoItem(Map<String, dynamic> doc) {
    final rawId = (doc['vod_id'] ?? '').toString();
    return VideoItem(
      id: '$_providerKey::$rawId',
      title: (doc['vod_name'] ?? '未知标题').toString(),
      cover: (doc['vod_pic'] ?? '').toString(),
      detailUrl: _apiBaseUrl,
      intro: (doc['vod_remarks'] ?? '').toString(),
      subtitle: (doc['vod_remarks'] ?? '').toString(),
      category: (doc['type_name'] ?? '').toString(),
      yearText: (doc['vod_year'] ?? '').toString(),
      sourceName: _siteName,
      providerKey: _providerKey,
      area: (doc['vod_area'] ?? '').toString(),
      remark: (doc['vod_remarks'] ?? '').toString(),
    );
  }

  String _extractRawId(String id) {
    final idx = id.lastIndexOf('::');
    if (idx >= 0 && idx + 2 < id.length) {
      return id.substring(idx + 2);
    }
    return id;
  }
}