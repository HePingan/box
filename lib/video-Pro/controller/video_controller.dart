import 'package:flutter/material.dart';
import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../services/video_api_service.dart';

/// 文件功能：视频模块全局状态管理 (使用 ChangeNotifier)
/// 管理：当前选择的资源源、视频列表数据、加载状态
class VideoController extends ChangeNotifier {
  // 所有的资源源列表 (来自 GitHub JSON)
  List<VideoSource> _sources = [];
  List<VideoSource> get sources => _sources;

  // 当前选中的源站
  VideoSource? _currentSource;
  VideoSource? get currentSource => _currentSource;

  // 视频列表数据
  List<VodItem> _videoList = [];
  List<VodItem> get videoList => _videoList;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  int _currentPage = 1;

  // 1. 初始化加载所有源 (截图 2 逻辑)
  Future<void> initSources(String configUrl) async {
    _isLoading = true;
    notifyListeners();

    _sources = await VideoApiService.fetchSources(configUrl);
    if (_sources.isNotEmpty) {
      _currentSource = _sources[0]; // 默认选中第一个
    }

    _isLoading = false;
    notifyListeners();
  }

  // 2. 切换当前源站
  void setCurrentSource(VideoSource source) {
    _currentSource = source;
    _currentPage = 1;
    _videoList = []; // 切换源后清空旧数据
    fetchVideoList(); // 立即获取新源的数据
    notifyListeners();
  }

  // 3. 加载视频列表 (截图 3 逻辑)
  Future<void> fetchVideoList({bool isRefresh = false}) async {
    if (_currentSource == null || _isLoading) return;

    if (isRefresh) {
      _currentPage = 1;
      _videoList = [];
    }

    _isLoading = true;
    notifyListeners();

    List<VodItem> newList = await VideoApiService.fetchVideoList(
      baseUrl: _currentSource!.url,
      page: _currentPage,
    );

    if (newList.isNotEmpty) {
      _videoList.addAll(newList);
      _currentPage++;
    }

    _isLoading = false;
    notifyListeners();
  }
}