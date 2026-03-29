// 文件路径: lib/video/core/maoyan_video_source.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'video_source.dart';

class MaoyanVideoSource implements VideoSource {
  // 使用一个稳定、免费、国内可访问的模拟 API
  final String _baseUrl = 'https://api.netsep.io/api/v1';

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

  // API 不支持搜索，所以我们返回一个提示
  @override
  Future<List<VideoItem>> searchVideos(String keyword, {int page = 1}) async {
    // 这个模拟 API 不直接支持关键词搜索，但我们可以通过获取列表并手动筛选来模拟
    if (page > 1) return [];
    final movies = await fetchByPath('/movie/list?type=hot', page: 1);
    if (keyword.isEmpty) return movies;
    
    final lowerKeyword = keyword.toLowerCase();
    return movies.where((m) => m.title.toLowerCase().contains(lowerKeyword)).toList();
  }

  @override
  Future<List<VideoItem>> fetchByPath(String path, {int page = 1}) async {
    if (page > 1) return []; // 此 API 不支持分页

    final uri = Uri.parse('$_baseUrl$path');
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw '网络请求失败: ${response.statusCode}';
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final result = decoded['result'];
    if (result is! List) return [];

    return result.map((item) {
      return _toVideoItem(Map<String, dynamic>.from(item)); // <--- 进行类型转换
    }).toList();
  }

  @override
  Future<VideoDetail> fetchDetail({
    required String videoId,
    String? detailUrl,
  }) async {
    final uri = Uri.parse('$_baseUrl/movie/detail?id=$videoId');
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw '获取详情失败: ${response.statusCode}';
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final detail = decoded['result'];
    if (detail is! Map) throw '详情数据格式错误';

    final item = _toVideoItem(Map<String, dynamic>.from(detail)); // <--- 在这里也进行类型转换
    
    return VideoDetail(
      item: item,
      creator: _asString(detail['director']),
      description: _asString(detail['desc']),
      tags: (_asString(detail['cat']).split(',') as List<String>).map((s) => s.trim()).toList(),
      sourceUrl: 'https://maoyan.com/films/$videoId',
      episodes: [
        // **关键点**: 因为没有真实播放地址，我们借用一个样片地址来确保能播放
        const VideoEpisode(
          title: '正片 (样例播放)',
          url: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
          index: 0,
        ),
      ],
    );
  }

  // --- Helper 方法 ---

  VideoItem _toVideoItem(Map<String, dynamic> item) {
    final id = _asString(item['id']);
    return VideoItem(
      id: id,
      title: _asString(item['name']),
      coverUrl: _asString(item['poster']),
      detailUrl: 'https://maoyan.com/films/$id', // 只是一个示意 URL
      intro: _asString(item['desc']),
      category: _asString(item['cat']),
      yearText: _asString(item['year']),
      sourceName: sourceName,
    );
  }

  String _asString(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    return value.toString();
  }
}