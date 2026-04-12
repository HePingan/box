import 'package:flutter/foundation.dart';

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
        'isLoading=$isLoading';
  }

  // =========================
  // 对外 API
  // =========================

  /// 初始化片源目录
  ///
  /// 典型调用场景：
  /// - 首页首次进入
  /// - 手动刷新首页
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

      final selectedSource =
          _findMatchingSource(_sources, _currentSource) ?? _sources.first;

      await _loadSourceData(
        source: selectedSource,
        token: token,
        reloadCategories: true,
        resetCategory: true,
        append: false,
        page: 1,
      );
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
    _videoList.clear();       // 瞬间清空旧列表 (如果你的变量没下划线，就填 videos.clear())
    notifyListeners();
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
    _videoList.clear();      // 瞬间清空当前分类的旧视频
    notifyListeners();
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
      Future<List<VideoCategory>>? categoriesFuture;
      List<VideoCategory> newCategories = _categories;
      int? selectedTypeId = resetCategory ? null : _currentTypeId;

      // 🏆 优化：如果需要拉取分类，我们先不去 await 它，而是把它变成一个 Future 任务挂起
      if (reloadCategories) {
        categoriesFuture = _repository.loadCategories(source);
      } else {
        selectedTypeId = _normalizeTypeId(selectedTypeId, _categories);
      }

      // 🏆 优化：并发请求！同时拉取“分类”和“视频列表”
      // 只有在不用刷新分类，或者重置分类(selectedTypeId为null)时才能完美并发
      final videosFuture = _repository.loadVideos(source, typeId: selectedTypeId, page: page);

      List<VodItem> videos;

      if (categoriesFuture != null) {
        // 等待两者同时完成！时间消耗 = max(分类接口时间, 视频列表接口时间)
        final results = await Future.wait([categoriesFuture, videosFuture]);
        if (_isStale(token)) return;

        newCategories = results[0] as List<VideoCategory>;
        videos = results[1] as List<VodItem>;
        
        // 并发完之后再统一校准 TypeId
        if (!resetCategory) selectedTypeId = _normalizeTypeId(selectedTypeId, newCategories);
      } else {
        videos = await videosFuture;
        if (_isStale(token)) return;
      }

      // ========= 后续数据绑定不变 =========
      if (append) {
        _videoList.addAll(videos);
      } else {
        _videoList..clear()..addAll(videos);
      }
      
      if (reloadCategories) {
        _categories..clear()..addAll(newCategories);
      }

      _currentSource = source;
      _currentTypeId = selectedTypeId;
      _currentPage = page;
      _hasMore = videos.length >= _repository.pageSize;

      _errorMessage = null;
      _setLoading(false);
      notifyListeners();
    } catch (e, st) {
      if (_isStale(token)) return;
      AppLogger.instance.logError(e, st, 'VIDEO_CONTROLLER');
      _errorMessage = '加载失败：$e';
      _setLoading(false);
      notifyListeners();
    }
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