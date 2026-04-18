import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:box/utils/app_logger.dart';

import '../models/video_category.dart';
import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../services/vod_detail_fill_service.dart';
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

  static Future<SharedPreferences>? _prefsFuture;

  final List<VideoSource> _sources = <VideoSource>[];
  final List<VideoCategory> _categories = <VideoCategory>[];
  final List<VodItem> _videoList = <VodItem>[];

  late final UnmodifiableListView<VideoSource> _sourcesView =
      UnmodifiableListView<VideoSource>(_sources);
  late final UnmodifiableListView<VideoCategory> _categoriesView =
      UnmodifiableListView<VideoCategory>(_categories);
  late final UnmodifiableListView<VodItem> _videoListView =
      UnmodifiableListView<VodItem>(_videoList);

  VideoSource? _currentSource;
  int? _currentTypeId;

  bool _isLoading = false;
  bool _hasMore = false;
  int _currentPage = 1;
  String? _errorMessage;

  int _requestToken = 0;
  bool _disposed = false;

  bool _coverPrefetchRunning = false;
  bool _coverPrefetchQueued = false;

  // =========================
  // 对外 getters
  // =========================

  List<VideoSource> get sources => _sourcesView;
  List<VideoCategory> get categories => _categoriesView;
  List<VodItem> get videoList => _videoListView;

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
        'hasMore=$_hasMore, '
        'isLoading=$_isLoading, '
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

    _isLoading = true;
    _errorMessage = null;
    _notify();

    try {
      final url = catalogUrl.trim();
      if (url.isEmpty) {
        _sources.clear();
        _categories.clear();
        _videoList.clear();
        _currentSource = null;
        _currentTypeId = null;
        _currentPage = 1;
        _hasMore = false;
        _errorMessage = '目录地址为空';
        return;
      }

      final sources = await _repository.loadSources(url);
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
        return;
      }

      final savedSourceKey = await _loadLastSourceKey();
      if (_isStale(token)) return;

      VideoSource? selectedSource;

      if (savedSourceKey != null && savedSourceKey.isNotEmpty) {
        selectedSource = _findSourceByKey(_sources, savedSourceKey);
      }

      selectedSource ??= _findDefaultSource(_sources);
      selectedSource ??= _findMatchingSource(_sources, _currentSource);
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

      if (_errorMessage == null && selectedSource != null) {
        await _saveLastSourceKey(_sourceKey(selectedSource));
      }
    } catch (e, st) {
      if (_isStale(token)) return;

      AppLogger.instance.logError(e, st, 'VIDEO_CONTROLLER');
      _errorMessage = '初始化片源失败：$e';
    } finally {
      if (_isStale(token)) return;
      _isLoading = false;
      _notify();
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
    _isLoading = true;
    _notify();

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
  Future<void> refreshCurrentSource() async {
    if (_disposed) return;

    final source = _currentSource;
    if (source == null) {
      return;
    }

    final token = _beginRequest();

    _errorMessage = null;
    _isLoading = true;
    _notify();

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
    if (source == null) {
      return;
    }

    final token = _beginRequest();

    _currentTypeId = typeId;
    _videoList.clear();
    _currentPage = 1;
    _hasMore = false;
    _errorMessage = null;
    _isLoading = true;
    _notify();

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

    if (_isLoading || !_hasMore) {
      return;
    }

    final source = _currentSource;
    if (source == null) {
      return;
    }

    final nextPage = _currentPage + 1;
    final token = _beginRequest();

    _isLoading = true;
    _errorMessage = null;
    _notify();

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
    if (_errorMessage == null) return;
    _errorMessage = null;
    _notify();
  }

  /// 替换当前列表中的某一条视频
  ///
  /// 只更新当前列表，不会改片源
  void replaceVideoItem(VodItem updated) {
    final changed = _replaceVideoItemByVodId(updated);
    if (!changed) return;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _requestToken++;
    _coverPrefetchRunning = false;
    _coverPrefetchQueued = false;
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

      final effectiveTypeId = resetCategory
          ? null
          : _normalizeTypeId(_currentTypeId, newCategories);

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

      _scheduleCoverPrefetch(
        source,
        token: token,
        items: videos,
        limit: page == 1 ? 20 : 10,
      );
    } catch (e, st) {
      if (_isStale(token)) return;

      AppLogger.instance.logError(e, st, 'VIDEO_CONTROLLER');
      _errorMessage = '加载失败：$e';
    } finally {
      if (_isStale(token)) return;

      _isLoading = false;
      _notify();
    }
  }

  /// 先按分类加载；如果第一页分类没数据，自动回退到“全部”
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

    if (videos.isNotEmpty || typeId == null || page != 1) {
      return videos;
    }

    final fallbackVideos = await _repository.loadVideos(
      source,
      typeId: null,
      page: page,
    );

    return fallbackVideos;
  }

  void _scheduleCoverPrefetch(
    VideoSource source, {
    required int token,
    List<VodItem>? items,
    int limit = 20,
  }) {
    if (_disposed) return;

    if (_coverPrefetchRunning) {
      _coverPrefetchQueued = true;
      return;
    }

    unawaited(
      _prefetchMissingCovers(
        source: source,
        token: token,
        items: items,
        limit: limit,
      ),
    );
  }

  /// 异步补齐封面
  ///
  /// 注意：
  /// - 使用 token 防止切源 / 切分类后旧任务继续改当前列表
  /// - 只在全部处理完成后统一 notify，减少 UI 抖动
  Future<void> _prefetchMissingCovers({
    required VideoSource source,
    required int token,
    List<VodItem>? items,
    int limit = 20,
  }) async {
    if (_disposed || _isStale(token)) return;

    if (_coverPrefetchRunning) {
      _coverPrefetchQueued = true;
      return;
    }

    _coverPrefetchRunning = true;
    bool anyChanged = false;

    try {
      final activeSource = _currentSource;
      if (activeSource == null || !_sameSource(activeSource, source)) {
        return;
      }

      final snapshot = List<VodItem>.from(items ?? _videoList);
      final targetItems = snapshot
          .where((v) => !_hasText(v.vodPic))
          .take(limit)
          .toList(growable: false);

      if (targetItems.isEmpty) {
        return;
      }

      final indexByVodId = <int, int>{};
      for (int i = 0; i < _videoList.length; i++) {
        indexByVodId[_videoList[i].vodId] = i;
      }

      const int batchSize = 4;

      for (int i = 0; i < targetItems.length; i += batchSize) {
        if (_disposed || _isStale(token)) break;

        final batch = targetItems.skip(i).take(batchSize).toList(growable: false);

        final results = await Future.wait<VodItem?>(
          batch.map(
            (item) => VodDetailFillService.instance.fill(
              source: source,
              vodId: item.vodId,
              baseItem: item,
            ),
          ),
        );

        if (_disposed || _isStale(token)) break;

        final currentSource = _currentSource;
        if (currentSource == null || !_sameSource(currentSource, source)) {
          break;
        }

        for (final filled in results) {
          if (_disposed || _isStale(token) || filled == null) {
            continue;
          }

          if (!_hasText(filled.vodPic)) {
            continue;
          }

          final index = indexByVodId[filled.vodId];
          if (index == null || index < 0 || index >= _videoList.length) {
            continue;
          }

          if (_videoList[index].vodId != filled.vodId) {
            continue;
          }

          _videoList[index] = filled;
          anyChanged = true;
        }
      }
    } catch (e, st) {
      AppLogger.instance.logError(e, st, 'VIDEO_CONTROLLER');
    } finally {
      _coverPrefetchRunning = false;

      if (_coverPrefetchQueued && !_disposed && !_isStale(token)) {
        _coverPrefetchQueued = false;
        final currentSource = _currentSource;
        if (currentSource != null) {
          unawaited(
            _prefetchMissingCovers(
              source: currentSource,
              token: _requestToken,
              items: List<VodItem>.from(_videoList),
              limit: limit,
            ),
          );
        }
      } else {
        _coverPrefetchQueued = false;
      }

      if (anyChanged && !_disposed && !_isStale(token)) {
        _notify();
      }
    }
  }

  bool _replaceVideoItemByVodId(VodItem updated) {
    final index = _videoList.indexWhere((e) => e.vodId == updated.vodId);
    if (index < 0) return false;

    _videoList[index] = updated;
    return true;
  }

  Future<String?> _loadLastSourceKey() async {
    final prefs = await _sharedPrefs();
    return prefs.getString(_prefLastSourceKey);
  }

  Future<void> _saveLastSourceKey(String key) async {
    if (_disposed) return;

    final prefs = await _sharedPrefs();
    await prefs.setString(_prefLastSourceKey, key);
  }

  static Future<SharedPreferences> _sharedPrefs() {
    return _prefsFuture ??= SharedPreferences.getInstance();
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

  int? _normalizeTypeId(int? typeId, List<VideoCategory> categories) {
    if (typeId == null) return null;

    final exists = categories.any((e) => e.typeId == typeId);
    return exists ? typeId : null;
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

  int _beginRequest() {
    _requestToken += 1;
    return _requestToken;
  }

  bool _isStale(int token) {
    return _disposed || token != _requestToken;
  }

  bool _hasText(String? value) {
    if (value == null) return false;
    final text = value.trim();
    return text.isNotEmpty && text.toLowerCase() != 'null';
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }
}