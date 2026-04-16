import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_logger.dart';
import '../models/video_category.dart';
import '../models/video_source.dart';
import '../models/vod_item.dart';
import 'video_catalog_repository.dart';

class VideoController extends ChangeNotifier {
  VideoController({
    VideoCatalogRepository? repository,
  }) : _repository = repository ?? const VideoCatalogRepository();

  final VideoCatalogRepository _repository;

  static const String _prefLastSourceKey = 'last_video_source_key';

  static const List<String> _preferredDefaultSourceKeywords = [
    '量子影视',
    '量子资源',
    '量子',
  ];

  final List<VideoSource> _sources = <VideoSource>[];
  final List<VideoCategory> _categories = <VideoCategory>[];
  final List<VodItem> _videoList = <VodItem>[];

  VideoSource? _currentSource;
  int? _currentTypeId;

  bool _isLoading = false;
  bool _hasMore = false;
  int _currentPage = 1;
  String? _errorMessage;

  int _requestToken = 0;
  bool _disposed = false;

  // =========================
  // 对外 getters
  // =========================

  List<VideoSource> get sources => List.unmodifiable(_sources);
  List<VideoCategory> get categories => List.unmodifiable(_categories);
  List<VodItem> get videoList => List.unmodifiable(_videoList);

  VideoSource? get currentSource => _currentSource;
  int? get currentTypeId => _currentTypeId;

  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;

  String? get errorMessage => _errorMessage;

  int get currentPage => _currentPage;

  String get debugSummary {
    return 'sources=${_sources.length}, '
        'categories=${_categories.length}, '
        'videos=${_videoList.length}, '
        'currentSource=${_currentSource?.name ?? '-'}, '
        'currentTypeId=${_currentTypeId?.toString() ?? 'all'}, '
        'page=$_currentPage, '
        'hasMore=$hasMore, '
        'isLoading=$isLoading, '
        'error=${_errorMessage ?? '-'}';
  }

  // =========================
  // 对外 API
  // =========================

  /// 初始化片源目录
  ///
  /// 优先级：
  /// 1. 恢复上次使用的源
  /// 2. 默认进入“量子影视/量子资源/量子”
  /// 3. 匹配当前源
  /// 4. 兜底第一个源
  Future<void> initSources(String catalogUrl) async {
    if (_disposed) return;

    final token = _beginRequest();

    _setLoading(true);
    _errorMessage = null;
    notifyListeners();

    try {
      final sources = await _repository.loadSources(catalogUrl);
      if (_isStale(token)) return;

      _sources
        ..clear()
        ..addAll(_dedupeSources(sources));

      if (_sources.isEmpty) {
        _currentSource = null;
        _categories.clear();
        _videoList.clear();
        _currentTypeId = null;
        _currentPage = 1;
        _hasMore = false;
        _errorMessage = '暂无可用视频源';
        _setLoading(false);
        notifyListeners();
        return;
      }

      // 1) 先尝试恢复上次选择的源
      final savedSourceKey = await _loadLastSourceKey();
      if (_isStale(token)) return;

      VideoSource? selectedSource;
      if (savedSourceKey != null && savedSourceKey.isNotEmpty) {
        selectedSource = _findSourceByKey(_sources, savedSourceKey);
      }

      // 2) 再尝试默认源
      selectedSource ??= _findDefaultSource(_sources);

      // 3) 再尝试匹配当前源
      selectedSource ??= _findMatchingSource(_sources, _currentSource);

      // 4) 最后兜底第一个
      selectedSource ??= _sources.first;

      await _loadSourceData(
        source: selectedSource,
        token: token,
        reloadCategories: true,
        resetCategory: true,
        append: false,
        page: 1,
      );

      if (_isStale(token)) return;

      // 只有成功加载后再保存，避免把坏源写进缓存
      if (_errorMessage == null && selectedSource != null) {
        await _saveLastSourceKey(_sourceKey(selectedSource));
      }
    } catch (e, st) {
      if (_isStale(token)) return;

      AppLogger.instance.logError(e, st, 'VIDEO_CONTROLLER');
      _errorMessage = '初始化片源失败：$e';
      _setLoading(false);
      notifyListeners();
    }
  }

  /// 切换当前片源
  Future<void> setCurrentSource(VideoSource source) async {
    if (_disposed) return;
    if (_currentSource != null && _sameSource(_currentSource!, source)) {
      return;
    }

    final token = _beginRequest();

    _currentSource = source;
    _currentTypeId = null;
    _videoList.clear();
    _currentPage = 1;
    _hasMore = false;
    _errorMessage = null;
    _setLoading(true);
    notifyListeners();

    await _loadSourceData(
      source: source,
      token: token,
      reloadCategories: true,
      resetCategory: true,
      append: false,
      page: 1,
    );

    if (_isStale(token)) return;

    if (_errorMessage == null) {
      await _saveLastSourceKey(_sourceKey(source));
    }
  }

  /// 刷新当前片源
  ///
  /// 不会强制切换分类，默认保留当前分类。
  Future<void> refreshCurrentSource() async {
    if (_disposed) return;
    final source = _currentSource;
    if (source == null) return;

    final token = _beginRequest();

    _errorMessage = null;
    _setLoading(true);
    notifyListeners();

    await _loadSourceData(
      source: source,
      token: token,
      reloadCategories: true,
      resetCategory: false,
      append: false,
      page: 1,
    );
  }

  /// 切换分类
  ///
  /// typeId = null 表示全部
  Future<void> setCategory(int? typeId) async {
    if (_disposed) return;

    final source = _currentSource;
    if (source == null) return;

    final token = _beginRequest();

    _currentTypeId = typeId;
    _videoList.clear();
    _currentPage = 1;
    _hasMore = false;
    _errorMessage = null;
    _setLoading(true);
    notifyListeners();

    await _loadSourceData(
      source: source,
      token: token,
      reloadCategories: false,
      resetCategory: false,
      append: false,
      page: 1,
    );
  }

  /// 加载更多
  Future<void> loadMore() async {
    if (_disposed) return;
    if (_isLoading || !_hasMore) return;

    final source = _currentSource;
    if (source == null) return;

    final nextPage = _currentPage + 1;
    final token = _beginRequest();

    _setLoading(true);
    _errorMessage = null;
    notifyListeners();

    await _loadSourceData(
      source: source,
      token: token,
      reloadCategories: false,
      resetCategory: false,
      append: true,
      page: nextPage,
    );
  }

  /// 清掉错误状态
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // =========================
  // 内部实现
  // =========================

  Future<void> _loadSourceData({
    required VideoSource source,
    required int token,
    required bool reloadCategories,
    required bool resetCategory,
    required bool append,
    required int page,
  }) async {
    try {
      List<VideoCategory> newCategories = _categories;

      // 1) 先加载分类（如果需要）
      if (reloadCategories) {
        try {
          newCategories = await _repository.loadCategories(source);
          if (_isStale(token)) return;
        } catch (e, st) {
          // 分类失败不应该阻断视频加载
          AppLogger.instance.logError(e, st, 'VIDEO_CONTROLLER');
          newCategories = <VideoCategory>[];
        }
      }

      // 2) 决定最终使用的分类 ID
      int? effectiveTypeId;
      if (resetCategory) {
        effectiveTypeId = null;
      } else {
        effectiveTypeId = _normalizeTypeId(_currentTypeId, newCategories);
      }

      // 3) 拉视频
      final videos = await _loadVideosWithFallback(
        source: source,
        typeId: effectiveTypeId,
        page: page,
      );

      if (_isStale(token)) return;

      if (append) {
        _videoList.addAll(videos);
      } else {
        _videoList
          ..clear()
          ..addAll(videos);
      }

      if (reloadCategories) {
        _categories
          ..clear()
          ..addAll(newCategories);
      }

      _currentSource = source;
      _currentTypeId = effectiveTypeId;
      _currentPage = page;
      _hasMore = videos.length >= _repository.pageSize;
      _errorMessage = null;
    } catch (e, st) {
      if (_isStale(token)) return;

      AppLogger.instance.logError(e, st, 'VIDEO_CONTROLLER');
      _errorMessage = '加载失败：$e';
    } finally {
      if (_isStale(token)) return;

      _setLoading(false);
      notifyListeners();
    }
  }

  /// 先按分类加载；如果第一页按分类没数据，自动回退到“全部”
  Future<List<VodItem>> _loadVideosWithFallback({
    required VideoSource source,
    required int? typeId,
    required int page,
  }) async {
    final videos = await _repository.loadVideos(
      source,
      typeId: typeId,
      page: page,
    );

    // 只有第一页才允许回退到“全部”，避免 loadMore 混入别的分类
    if (videos.isNotEmpty || typeId == null || page != 1) {
      return videos;
    }

    return await _repository.loadVideos(
      source,
      typeId: null,
      page: page,
    );
  }

  Future<String?> _loadLastSourceKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefLastSourceKey);
  }

  Future<void> _saveLastSourceKey(String key) async {
    if (_disposed) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefLastSourceKey, key);
  }

  VideoSource? _findDefaultSource(List<VideoSource> sources) {
    for (final keyword in _preferredDefaultSourceKeywords) {
      for (final source in sources) {
        if (source.name.contains(keyword)) {
          return source;
        }
      }
    }
    return null;
  }

  VideoSource? _findSourceByKey(List<VideoSource> sources, String key) {
    for (final source in sources) {
      if (_sourceKey(source) == key) {
        return source;
      }
    }
    return null;
  }

  int? _normalizeTypeId(int? typeId, List<VideoCategory> categories) {
    if (typeId == null) return null;

    final exists = categories.any((e) => e.typeId == typeId);
    return exists ? typeId : null;
  }

  int _beginRequest() {
    _requestToken += 1;
    return _requestToken;
  }

  bool _isStale(int token) {
    return _disposed || token != _requestToken;
  }

  void _setLoading(bool value) {
    _isLoading = value;
  }

  List<VideoSource> _dedupeSources(List<VideoSource> sources) {
    final result = <VideoSource>[];
    final seen = <String>{};

    for (final source in sources) {
      final key = _sourceKey(source);
      if (seen.contains(key)) continue;
      seen.add(key);
      result.add(source);
    }

    return result;
  }

  VideoSource? _findMatchingSource(
    List<VideoSource> sources,
    VideoSource? target,
  ) {
    if (target == null) return null;

    for (final source in sources) {
      if (_sameSource(source, target)) return source;
    }
    return null;
  }

  bool _sameSource(VideoSource a, VideoSource b) {
    return _sourceKey(a) == _sourceKey(b);
  }

  String _sourceKey(VideoSource source) {
    final id = source.id.toString().trim();
    if (id.isNotEmpty && id != 'null') {
      return 'id:$id';
    }

    final url = source.url.trim();
    if (url.isNotEmpty) {
      return 'url:$url';
    }

    final detailUrl = source.detailUrl.trim();
    if (detailUrl.isNotEmpty) {
      return 'detail:$detailUrl';
    }

    return 'name:${source.name.trim()}';
  }
}