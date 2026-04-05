import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/video_source.dart';
import '../models/vod_item.dart';

/// 文件功能：视频模块统一 API 请求类
class VideoApiService {
  
  // 1. 从 GitHub 或镜像获取所有资源站配置 (截图 2)
  static Future<List<VideoSource>> fetchSources(String configUrl) async {
    try {
      final response = await http.get(Uri.parse(configUrl));
      if (response.statusCode == 200) {
        List<dynamic> data = jsonDecode(response.body);
        return data.map((e) => VideoSource.fromJson(e)).toList();
      }
    } catch (e) {
      print("加载源配置失败: $e");
    }
    return [];
  }

  // 2. 获取具体资源站的视频列表 (截图 3)
  // ac=list 是列表，ac=detail 是获取包含播放链接的详情
  static Future<List<VodItem>> fetchVideoList({
    required String baseUrl,
    int page = 1,
    int? typeId,
  }) async {
    // 拼接苹果CMS标准接口参数
    String url = "$baseUrl?ac=list&pg=$page";
    if (typeId != null) url += "&t=$typeId";

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        Map<String, dynamic> data = jsonDecode(response.body);
        List<dynamic> list = data['list'];
        return list.map((e) => VodItem.fromJson(e)).toList();
      }
    } catch (e) {
      print("获取视频列表失败: $e");
    }
    return [];
  }

  // 3. 搜索视频
  static Future<List<VodItem>> searchVideo(String baseUrl, String keyword) async {
    String url = "$baseUrl?ac=list&wd=${Uri.encodeComponent(keyword)}";
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        Map<String, dynamic> data = jsonDecode(response.body);
        List<dynamic> list = data['list'];
        return list.map((e) => VodItem.fromJson(e)).toList();
      }
    } catch (e) {
      print("搜索失败: $e");
    }
    return [];
  }

  // 4. 获取视频播放详情 (只有 detail 接口才有 vod_play_url)
  static Future<VodItem?> fetchDetail(String baseUrl, int vodId) async {
    String url = "$baseUrl?ac=detail&ids=$vodId";
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        Map<String, dynamic> data = jsonDecode(response.body);
        return VodItem.fromJson(data['list'][0]);
      }
    } catch (e) {
      print("获取详情失败: $e");
    }
    return null;
  }
}