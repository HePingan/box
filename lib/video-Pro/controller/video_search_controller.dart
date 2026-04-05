import 'package:flutter/material.dart';
import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../services/video_api_service.dart';

/// 文件功能：搜索模块状态管理
/// 实现：针对指定源进行关键词检索、保存搜索历史（可选）
class VideoSearchController extends ChangeNotifier {
  List<VodItem> _searchResults = [];
  List<VodItem> get searchResults => _searchResults;

  bool _isSearching = false;
  bool get isSearching => _isSearching;

  // 执行搜索
  Future<void> search(VideoSource source, String keyword) async {
    if (keyword.isEmpty) return;

    _isSearching = true;
    _searchResults = []; // 开始新搜索前清空旧结果
    notifyListeners();

    // 调用之前在 VideoApiService 中定义的 searchVideo 方法
    // 苹果CMS 标准：baseUrl?ac=list&wd=关键词
    _searchResults = await VideoApiService.searchVideo(source.url, keyword);

    _isSearching = false;
    notifyListeners();
  }

  // 清空搜索结果
  void clearSearch() {
    _searchResults = [];
    notifyListeners();
  }
}