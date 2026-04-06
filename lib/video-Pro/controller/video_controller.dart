import 'package:flutter/foundation.dart';

import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../services/video_api_service.dart';

class VideoController extends ChangeNotifier {
  List<VideoSource> _sources = [];
  List<VideoSource> get sources => _sources;

  VideoSource? _currentSource;
  VideoSource? get currentSource => _currentSource;

  List<VodItem> _videoList = [];
  List<VodItem> get videoList => _videoList;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// 当前是否还能继续加载更多
  bool _hasMore = true;
  bool get hasMore => _hasMore;

  /// 当前页码，从 1 开始
  int _currentPage = 1;
  int get currentPage => _currentPage;

  /// 最近一次错误信息，供页面展示
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// 请求版本号，用来丢弃旧请求结果
  int _requestVersion = 0;

  /// 是否已经被 dispose
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// 初始化视频源，并默认加载第一个源的首页数据
  Future<void> initSources(String configUrl) async {
    final int taskVersion = ++_requestVersion;

    _setLoading(true);
    _errorMessage = null;
    _sources = [];
    _currentSource = null;
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
      _videoList = [];
      _currentPage = 1;
      _hasMore = true;
      _errorMessage = null;
      _safeNotify();

      if (_currentSource != null) {
        await _loadVideoListInternal(
          taskVersion: taskVersion,
          source: _currentSource!,
          page: 1,
          append: false,
        );
      } else {
        _errorMessage = '未解析到可用视频源';
      }
    } catch (e) {
      if (!_isTaskActive(taskVersion)) return;

      _sources = [];
      _currentSource = null;
      _videoList = [];
      _currentPage = 1;
      _hasMore = true;
      _errorMessage = '初始化视频源失败：$e';
    } finally {
      if (_isTaskActive(taskVersion)) {
        _setLoading(false);
        _safeNotify();
      }
    }
  }

  /// 切换当前视频源，并自动加载该源的第一页
  Future<void> setCurrentSource(VideoSource source) async {
    final int taskVersion = ++_requestVersion;

    _currentSource = source;
    _videoList = [];
    _currentPage = 1;
    _hasMore = true;
    _errorMessage = null;
    _setLoading(true);
    _safeNotify();

    try {
      await _loadVideoListInternal(
        taskVersion: taskVersion,
        source: source,
        page: 1,
        append: false,
      );
    } finally {
      if (_isTaskActive(taskVersion)) {
        _setLoading(false);
        _safeNotify();
      }
    }
  }

  /// 刷新当前源
  Future<void> refreshCurrentSource() async {
    await fetchVideoList(isRefresh: true, force: true);
  }

  /// 拉取视频列表
  ///
  /// [isRefresh] = true 时会重新从第一页开始加载
  /// [force] = true 时即使当前已有加载任务，也会强行发起新请求
  Future<void> fetchVideoList({
    bool isRefresh = false,
    bool force = false,
  }) async {
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
      final int pageToLoad = _currentPage;
      await _loadVideoListInternal(
        taskVersion: taskVersion,
        source: source,
        page: pageToLoad,
        append: !isRefresh,
      );
    } finally {
      if (_isTaskActive(taskVersion)) {
        _setLoading(false);
        _safeNotify();
      }
    }
  }

  /// 加载更多
  Future<void> loadMore() async {
    final source = _currentSource;
    if (source == null) return;
    if (_isLoading) return;
    if (!_hasMore) return;

    final int taskVersion = ++_requestVersion;
    final int pageToLoad = _currentPage;

    _errorMessage = null;
    _setLoading(true);
    _safeNotify();

    try {
      await _loadVideoListInternal(
        taskVersion: taskVersion,
        source: source,
        page: pageToLoad,
        append: true,
      );
    } finally {
      if (_isTaskActive(taskVersion)) {
        _setLoading(false);
        _safeNotify();
      }
    }
  }

  /// 内部加载视频列表
  Future<void> _loadVideoListInternal({
    required int taskVersion,
    required VideoSource source,
    required int page,
    required bool append,
  }) async {
    try {
      final List<VodItem> newList = await VideoApiService.fetchVideoList(
        baseUrl: source.url,
        page: page,
      );

      if (!_isTaskActive(taskVersion)) return;

      // 如果用户已经切到别的源了，这次结果直接丢弃
      if (_currentSource?.id != source.id) return;

      if (!append) {
        _videoList = [];
      }

      if (newList.isEmpty) {
        // 当前页没数据，认为后面也没有更多了
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

      // 首屏失败时，保留空列表；分页失败时，保留已有列表
      if (!append && _videoList.isEmpty) {
        _videoList = [];
      }
    }
  }

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