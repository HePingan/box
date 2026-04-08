import 'package:flutter/foundation.dart';

import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../models/video_category.dart'; // 引入新增的分类模型
import '../services/video_api_service.dart';

class VideoController extends ChangeNotifier {
  // ==================== 源站状态 ====================
  List<VideoSource> _sources = [];
  List<VideoSource> get sources => _sources;

  VideoSource? _currentSource;
  VideoSource? get currentSource => _currentSource;

  // ==================== 分类状态 (新增) ====================
  List<VideoCategory> _categories = [];
  List<VideoCategory> get categories => _categories;

  int? _currentTypeId; // 当前选中的分类，null表示“全部”
  int? get currentTypeId => _currentTypeId;

  // ==================== 视频列表与分页状态 ====================
  List<VodItem> _videoList = [];
  List<VodItem> get videoList => _videoList;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _hasMore = true;
  bool get hasMore => _hasMore;

  int _currentPage = 1;
  int get currentPage => _currentPage;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // ==================== 安全与并发控制机制 ====================
  int _requestVersion = 0;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// 初始化视频源，并默认加载第一个源的数据和分类
  Future<void> initSources(String configUrl) async {
    final int taskVersion = ++_requestVersion;

    _setLoading(true);
    _errorMessage = null;
    _sources = [];
    _currentSource = null;
    _categories = [];
    _currentTypeId = null;
    _videoList = [];
    _currentPage = 1;
    _hasMore = true;
    _safeNotify();

    final url = configUrl.trim();
    if (url.isEmpty) {
      if (_isTaskActive(taskVersion)) {
        _setLoading(false);
        _safeNotify();
      }
      return;
    }

    try {
      final sources = await VideoApiService.fetchSources(url);

      if (!_isTaskActive(taskVersion)) return;

      _sources = sources;
      _currentSource = _sources.isNotEmpty ? _sources.first : null;
      _safeNotify();

      if (_currentSource != null) {
        // 核心：并发拉取分类和视频第一页，提升首屏速度
        await Future.wait([
          _loadCategoriesInternal(taskVersion, _currentSource!),
          _loadVideoListInternal(taskVersion, _currentSource!, 1, false),
        ]);
      } else {
        _errorMessage = '未解析到可用视频源';
      }
    } catch (e) {
      if (!_isTaskActive(taskVersion)) return;
      _errorMessage = '初始化视频源失败：$e';
    } finally {
      if (_isTaskActive(taskVersion)) {
        _setLoading(false);
        _safeNotify();
      }
    }
  }

  /// 切换当前视频源，清理分类并重新加载
  Future<void> setCurrentSource(VideoSource source) async {
    if (_currentSource?.id == source.id) return; // 防抖

    final int taskVersion = ++_requestVersion;

    _currentSource = source;
    _categories = [];
    _currentTypeId = null; // 切源默认回“全部”
    _videoList = [];
    _currentPage = 1;
    _hasMore = true;
    _errorMessage = null;
    _setLoading(true);
    _safeNotify();

    try {
      // 同样并发拉取该源的分类和视频数据
      await Future.wait([
        _loadCategoriesInternal(taskVersion, source),
        _loadVideoListInternal(taskVersion, source, 1, false),
      ]);
    } finally {
      if (_isTaskActive(taskVersion)) {
        _setLoading(false);
        _safeNotify();
      }
    }
  }

  /// 切换顶部栏分类 (新增方法)
  Future<void> setCategory(int? typeId) async {
    if (_currentTypeId == typeId) return; // 避免重复点击同一分类

    _currentTypeId = typeId;
    await fetchVideoList(isRefresh: true, force: true);
  }

  /// 刷新当前源或分类列表
  Future<void> refreshCurrentSource() async {
    await fetchVideoList(isRefresh: true, force: true);
  }

  /// 拉取视频列表
  Future<void> fetchVideoList({bool isRefresh = false, bool force = false}) async {
    final source = _currentSource;
    if (source == null) return;

    if (_isLoading && !force) return;

    final int taskVersion = ++_requestVersion;

    if (isRefresh) {
      _videoList = [];
      _currentPage = 1;
      _hasMore = true;
    }

    _errorMessage = null;
    _setLoading(true);
    _safeNotify();

    try {
      await _loadVideoListInternal(taskVersion, source, _currentPage, !isRefresh);
    } finally {
      if (_isTaskActive(taskVersion)) {
        _setLoading(false);
        _safeNotify();
      }
    }
  }

  /// 加载更多（下一页）
  Future<void> loadMore() async {
    final source = _currentSource;
    if (source == null || _isLoading || !_hasMore) return;

    final int taskVersion = ++_requestVersion;
    
    _errorMessage = null;
    _setLoading(true);
    _safeNotify();

    try {
      await _loadVideoListInternal(taskVersion, source, _currentPage, true);
    } finally {
      if (_isTaskActive(taskVersion)) {
        _setLoading(false);
        _safeNotify();
      }
    }
  }

  // ==================== 内部请求方法 ====================

  /// 内部拉取分类列表 (受并发版本号保护)
  Future<void> _loadCategoriesInternal(int taskVersion, VideoSource source) async {
    try {
      final cats = await VideoApiService.fetchCategories(source.url);
      if (!_isTaskActive(taskVersion)) return;
      if (_currentSource?.id != source.id) return;
      
      _categories = cats;
      _safeNotify();
    } catch (e) {
      debugPrint('拉取分类失败忽略: $e');
    }
  }

  /// 内部拉取视频列表 (受并发版本号保护，且带上分类ID过滤)
  Future<void> _loadVideoListInternal(int taskVersion, VideoSource source, int page, bool append) async {
    try {
      final List<VodItem> newList = await VideoApiService.fetchVideoList(
        baseUrl: source.url,
        page: page,
        typeId: _currentTypeId, // 【核心修改】：精准按选中分类查询
      );

      if (!_isTaskActive(taskVersion)) return;
      if (_currentSource?.id != source.id) return;

      if (!append) _videoList = [];

      if (newList.isEmpty) {
        _hasMore = false;
      } else {
        _videoList.addAll(newList);
        _currentPage = page + 1;
        _hasMore = true;
      }
      _errorMessage = null;
    } catch (e) {
      if (!_isTaskActive(taskVersion)) return;

      _errorMessage = '加载视频列表失败：$e';
      if (!append && _videoList.isEmpty) _videoList = [];
    }
  }

  // ==================== 保护机制辅助方法 ====================

  void _setLoading(bool value) {
    _isLoading = value;
  }

  bool _isTaskActive(int taskVersion) {
    if (_disposed) return false;
    return taskVersion == _requestVersion;
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }
}