// 文件路径: lib/video/core/tvbox_video_source.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'video_source.dart';

class TvBoxVideoSource implements VideoSource {
  /// TVBox 配置地址 (可以替换为您获取到的最新地址)
  final String configUrl;
  
  String _apiBaseUrl = ''; // 实际解析出来的 CMS API 地址
  String _siteName = 'TVBox 源';
  bool _initialized = false;

  TvBoxVideoSource({
    this.configUrl = 'http://饭太硬.com/tv/', // 默认使用饭太硬的源
  });

  @override
  String get sourceName => _siteName;

  /// 初始化：从配置地址获取第一个有效的站点 API
  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      final res = await http.get(Uri.parse(configUrl));
      final decoded = jsonDecode(res.body);
      final sites = decoded['sites'] as List;
      
      // 寻找第一个 type 为 1 (CMS) 的站点
      final site = sites.firstWhere((s) => s['type'] == 1 || s['type'] == 0);
      _apiBaseUrl = site['api'];
      _siteName = site['name'] ?? 'TVBox 站点';
      _initialized = true;
    } catch (e) {
      throw '初始化 TVBox 接口失败: $e';
    }
  }

  @override
  List<VideoCategory> get categories => const [
        VideoCategory(id: '1', title: '电影', query: '1'),
        VideoCategory(id: '2', title: '剧集', query: '2'),
        VideoCategory(id: '3', title: '综艺', query: '3'),
        VideoCategory(id: '4', title: '动漫', query: '4'),
      ];

  @override
  Future<List<VideoItem>> searchVideos(String keyword, {int page = 1}) async {
    await _ensureInitialized();
    // 苹果 CMS 标准搜索参数: ?ac=videolist&wd=关键字&pg=页码
    final url = '$_apiBaseUrl?ac=videolist&wd=${Uri.encodeComponent(keyword)}&pg=$page';
    return _fetchCmsList(url);
  }

  @override
  Future<List<VideoItem>> fetchByPath(String path, {int page = 1}) async {
    await _ensureInitialized();
    // 苹果 CMS 标准分类参数: ?ac=videolist&t=分类ID&pg=页码
    final url = '$_apiBaseUrl?ac=videolist&t=$path&pg=$page';
    return _fetchCmsList(url);
  }
@override
  Future<VideoDetail> fetchDetail({required String videoId, String? detailUrl}) async {
    await _ensureInitialized();
    // 获取详情参数: ?ac=videolist&ids=视频ID
    final url = '$_apiBaseUrl?ac=videolist&ids=$videoId';
    final res = await http.get(Uri.parse(url));
    final decoded = jsonDecode(res.body);
    
    // 同样进行类型转换修复
    final data = Map<String, dynamic>.from((decoded['list'] as List).first);

    final item = _toVideoItem(data);
    
    // 解析播放地址 (CMS 格式通常是: 名字$链接#名字$链接)
    List<VideoEpisode> episodes = [];
    final playUrlStr = data['vod_play_url'] ?? '';
    
    // 使用 r'' 原始字符串解决 $ 报错问题
    final groups = playUrlStr.split(r'$$$'); 
    final mainLine = groups[0].split('#'); 
    
    for (var i = 0; i < mainLine.length; i++) {
        final pair = mainLine[i].split(r'$'); // 这里也改用 r'$'
        if (pair.length >= 2) {
            episodes.add(VideoEpisode(
                title: pair[0],
                url: pair[1],
                index: i,
            ));
        } else if (pair.isNotEmpty && pair[0].toString().contains('http')) {
            episodes.add(VideoEpisode(
                title: '正片 ${i+1}',
                url: pair[0],
                index: i,
            ));
        }
    }

    return VideoDetail(
      item: item,
      creator: data['vod_director'] ?? '未知',
      description: data['vod_content'] ?? item.intro,
      tags: (data['vod_type'] ?? '').toString().split('/'),
      episodes: episodes,
      sourceUrl: _apiBaseUrl,
    );
  }

  /// 通用的数据解析
  Future<List<VideoItem>> _fetchCmsList(String url) async {
    try {
      final res = await http.get(Uri.parse(url));
      final decoded = jsonDecode(res.body);
      final list = decoded['list'] as List;
      return list.map((e) => _toVideoItem(e)).toList();
    } catch (e) {
      print('CMS 请求出错: $e');
      return [];
    }
  }

  VideoItem _toVideoItem(Map<String, dynamic> doc) {
    return VideoItem(
      id: doc['vod_id'].toString(),
      title: doc['vod_name'] ?? '未知标题',
      coverUrl: doc['vod_pic'] ?? '',
      detailUrl: '',
      intro: doc['vod_remarks'] ?? '',
      category: doc['type_name'] ?? '',
      yearText: doc['vod_year'] ?? '',
      sourceName: _siteName,
    );
  }
}