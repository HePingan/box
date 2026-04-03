import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'video_source.dart';

class MaoyanVideoSource implements VideoSource {
  final String _baseUrl = 'https://api.netsep.io/api/v1';
  static const String _providerKey = 'maoyan_mock';

  @override
  String get sourceName => '猫眼电影 (模拟)';

  @override
  List<VideoCategory> get categories => const [
        VideoCategory(
          id: 'hot',
          title: '正在热映',
          query: '/movie/list?type=hot',
          description: '当前热门上映的电影',
        ),
        VideoCategory(
          id: 'coming',
          title: '即将上映',
          query: '/movie/list?type=coming',
          description: '敬请期待的影片',
        ),
      ];

  @override
  Future<List<VideoItem>> searchVideos(String keyword, {int page = 1}) async {
    if (page > 1) return const [];

    final movies = await fetchByPath('/movie/list?type=hot', page: 1);
    if (keyword.trim().isEmpty) return movies;

    final lowerKeyword = keyword.toLowerCase();
    return movies.where((m) => m.title.toLowerCase().contains(lowerKeyword)).toList();
  }

  @override
  Future<List<VideoItem>> fetchByPath(String path, {int page = 1}) async {
    if (page > 1) return const [];

    final uri = Uri.parse('$_baseUrl$path');
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('网络请求失败: ${response.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final result = decoded['result'];
    if (result is! List) return const [];

    return result
        .map((item) => _toVideoItem(Map<String, dynamic>.from(item)))
        .toList();
  }

  @override
  Future<VideoDetail> fetchDetail({
    required VideoItem item,
  }) async {
    final rawId = _extractRawId(item.id);
    final uri = Uri.parse('$_baseUrl/movie/detail?id=$rawId');
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('获取详情失败: ${response.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final detail = decoded['result'];
    if (detail is! Map) throw Exception('详情数据格式错误');

    final detailMap = Map<String, dynamic>.from(detail);
    final detailItem = _toVideoItem(detailMap);

    return VideoDetail(
      item: detailItem,
      cover: detailItem.cover,
      creator: _asString(detailMap['director']),
      description: _asString(detailMap['desc']),
      tags: _asString(detailMap['cat'])
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      sourceUrl: 'https://maoyan.com/films/$rawId',
      playSources: const [
        VideoPlaySource(
          name: '样例线路',
          episodes: [
            VideoEpisode(
              title: '正片 (样例播放)',
              url:
                  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
              index: 0,
            ),
          ],
        ),
      ],
    );
  }

  VideoItem _toVideoItem(Map<String, dynamic> item) {
    final rawId = _asString(item['id']);
    return VideoItem(
      id: '$_providerKey::$rawId',
      title: _asString(item['name']),
      cover: _asString(item['poster']),
      detailUrl: 'https://maoyan.com/films/$rawId',
      intro: _asString(item['desc']),
      category: _asString(item['cat']),
      yearText: _asString(item['year']),
      sourceName: sourceName,
      providerKey: _providerKey,
    );
  }

  String _extractRawId(String id) {
    final idx = id.lastIndexOf('::');
    if (idx >= 0 && idx + 2 < id.length) {
      return id.substring(idx + 2);
    }
    return id;
  }

  String _asString(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }
}