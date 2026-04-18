import 'dart:async';

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

  bool _coverPrefetchRunning = false;
  bool _coverPrefetchQueued = false;

  // =========================
  // 日志辅助
  // =========================

  void _log(String message) {
    if (kDebugMode) {
      AppLogger.instance.log(message, tag: 'VIDEO_CONTROLLER');
    }
  }

  String _briefSource(VideoSource? source) {
    if (source == null) return 'null';
    return 'name=${source.name}, id=${source.id}, url=${source.url}, detail=${source.detailUrl}';
  }

  String _briefCategories(List<VideoCategory> categories, {int limit = 8}) {
    if (categories.isEmpty) return '[]';
    return categories
        .take(limit)
        .map((e) => '${e.typeId}:${e.typeName}')
        .join(' | ');
  }

  String _briefVideos(List<VodItem> videos, {int limit = 3}) {
    if (videos.isEmpty) return '[]';
    return videos
        .take(limit)
        .map((e) => '${e.vodId}:${e.vodName}:pic=${e.vodPic ?? "null"}')
        .join(' | ');
  }

  bool _hasText(String? value) {
    if (value == null) return false;
    final text = value.trim();
    return text.isNotEmpty && text.toLowerCase() != 'null';
  }

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

    _log('[initSources] start catalogUrl=$catalogUrl');
    _setLoading(true);
    _errorMessage = null;
    notifyListeners();

    try {
      final sources = await _repository.loadSources(catalogUrl);
      if (_isStale(token)) {
        _log('[initSources] stale after loadSources token=$token');
        return;
      }

      _log(
        '[initSources] loadSources result count=${sources.length} '
        'sample=${sources.take(3).map((e) => e.name).join(" | ")}',
      );

      _sources
        ..clear()
        ..addAll(_dedupeSources(sources));

      _log(
        '[initSources] deduped sources=${_sources.length} '
        'sample=${_sources.take(5).map((e) => e.name).join(" | ")}',
      );

      if (_sources.isEmpty) {
        _currentSource = null;
        _categories.clear();
        _videoList.clear();
        _currentTypeId = null;
        _currentPage = 1;
        _hasMore = false;
        _errorMessage = '暂无可用视频源';
        _setLoading(false);
        _log('[initSources] no sources available');
        notifyListeners();
        return;
      }

      // 1) 先尝试恢复上次选择的源
      final savedSourceKey = await _loadLastSourceKey();
      if (_isStale(token)) {
        _log('[initSources] stale after _loadLastSourceKey token=$token');
        return;
      }

      _log('[initSources] savedSourceKey=${savedSourceKey ?? "null"}');

      VideoSource? selectedSource;
      if (savedSourceKey != null && savedSourceKey.isNotEmpty) {
        selectedSource = _findSourceByKey(_sources, savedSourceKey);
        _log('[initSources] selected by saved key => ${_briefSource(selectedSource)}');
      }

      // 2) 再尝试默认源
      selectedSource ??= _findDefaultSource(_sources);
      if (selectedSource != null) {
        _log('[initSources] selected default source => ${_briefSource(selectedSource)}');
      }

      // 3) 再尝试匹配当前源
      selectedSource ??= _findMatchingSource(_sources, _currentSource);
      if (selectedSource != null) {
        _log('[initSources] selected matched current source => ${_briefSource(selectedSource)}');
      }

      // 4) 最后兜底第一个
      selectedSource ??= _sources.first;
      _log('[initSources] final selected source => ${_briefSource(selectedSource)}');

      await _loadSourceData(
        source: selectedSource,
        token: token,
        reloadCategories: true,
        resetCategory: true,
        append: false,
        page: 1,
      );

      if (_isStale(token)) {
        _log('[initSources] stale after _loadSourceData token=$token');
        return;
      }

      // 只有成功加载后再保存，避免把坏源写进缓存
      if (_errorMessage == null && selectedSource != null) {
        await _saveLastSourceKey(_sourceKey(selectedSource));
        _log('[initSources] saved last source key=${_sourceKey(selectedSource)}');
      }

      _log('[initSources] done => $debugSummary');
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
      _log('[setCurrentSource] same source ignored => ${_briefSource(source)}');
      return;
    }

    final token = _beginRequest();

    _log('[setCurrentSource] source=${_briefSource(source)}');
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

    if (_isStale(token)) {
      _log('[setCurrentSource] stale after load token=$token');
      return;
    }

    if (_errorMessage == null) {
      await _saveLastSourceKey(_sourceKey(source));
      _log('[setCurrentSource] saved last source key=${_sourceKey(source)}');
    }

    _log('[setCurrentSource] done => $debugSummary');
  }

  /// 刷新当前片源
  ///
  /// 不会强制切换分类，默认保留当前分类。
  Future<void> refreshCurrentSource() async {
    if (_disposed) return;
    final source = _currentSource;
    if (source == null) {
      _log('[refreshCurrentSource] skipped, currentSource is null');
      return;
    }

    final token = _beginRequest();

    _log(
      '[refreshCurrentSource] source=${_briefSource(source)} '
      'currentTypeId=${_currentTypeId?.toString() ?? "all"}',
    );
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

    _log('[refreshCurrentSource] done => $debugSummary');
  }

  /// 切换分类
  ///
  /// typeId = null 表示全部
  Future<void> setCategory(int? typeId) async {
    if (_disposed) return;

    final source = _currentSource;
    if (source == null) {
      _log(
        '[setCategory] skipped, currentSource is null, '
        'typeId=${typeId?.toString() ?? "all"}',
      );
      return;
    }

    final token = _beginRequest();

    _log('[setCategory] source=${_briefSource(source)} typeId=${typeId?.toString() ?? "all"}');
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

    _log('[setCategory] done => $debugSummary');
  }

  /// 加载更多
  Future<void> loadMore() async {
    if (_disposed) return;

    if (_isLoading || !_hasMore) {
      _log(
        '[loadMore] skipped isLoading=$_isLoading hasMore=$_hasMore '
        'page=$_currentPage source=${_briefSource(_currentSource)}',
      );
      return;
    }

    final source = _currentSource;
    if (source == null) {
      _log('[loadMore] skipped, currentSource is null');
      return;
    }

    final nextPage = _currentPage + 1;
    final token = _beginRequest();

    _log(
      '[loadMore] start source=${_briefSource(source)} '
      'nextPage=$nextPage typeId=${_currentTypeId?.toString() ?? "all"}',
    );
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

    _log('[loadMore] done => $debugSummary');
  }

  /// 清掉错误状态
  void clearError() {
    _errorMessage = null;
    _log('[clearError] cleared');
    notifyListeners();
  }

  /// 替换当前列表中的某一条视频
  ///
  /// 注意：这里只更新当前列表，不会改变片源。
  void replaceVideoItem(VodItem updated) {
    final changed = _replaceVideoItemByVodId(updated);
    if (!changed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _log('[dispose] controller disposed');
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
      _log(
        '[loadSourceData] start '
        'source=${_briefSource(source)} '
        'reloadCategories=$reloadCategories '
        'resetCategory=$resetCategory '
        'append=$append '
        'page=$page '
        'currentTypeId=${_currentTypeId?.toString() ?? "all"}',
      );

      List<VideoCategory> newCategories = _categories;

      // 1) 先加载分类（如果需要）
      if (reloadCategories) {
        try {
          newCategories = await _repository.loadCategories(source);
          if (_isStale(token)) {
            _log('[loadSourceData] stale after loadCategories token=$token');
            return;
          }

          _log(
            '[loadSourceData] categories loaded count=${newCategories.length} '
            'sample=${_briefCategories(newCategories)}',
          );
        } catch (e, st) {
          // 分类失败不应该阻断视频加载
          AppLogger.instance.logError(e, st, 'VIDEO_CONTROLLER');
          newCategories = <VideoCategory>[];
          _log('[loadSourceData] categories load failed, fallback to empty list');
        }
      }

      // 2) 决定最终使用的分类 ID
      int? effectiveTypeId;
      if (resetCategory) {
        effectiveTypeId = null;
      } else {
        effectiveTypeId = _normalizeTypeId(_currentTypeId, newCategories);
      }

      _log(
        '[loadSourceData] effectiveTypeId=${effectiveTypeId?.toString() ?? "all"} '
        'newCategories=${newCategories.length}',
      );

      // 3) 拉视频
      final videos = await _loadVideosWithFallback(
        source: source,
        typeId: effectiveTypeId,
        page: page,
      );

      if (_isStale(token)) {
        _log('[loadSourceData] stale after loadVideos token=$token');
        return;
      }

      _log(
        '[loadSourceData] videos fetched count=${videos.length} '
        'sample=${_briefVideos(videos)}',
      );

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

      _log(
        '[loadSourceData] applied '
        'source=${source.name} '
        'categories=${_categories.length} '
        'videos=${_videoList.length} '
        'currentTypeId=${_currentTypeId?.toString() ?? "all"} '
        'page=$_currentPage '
        'hasMore=$_hasMore',
      );

      // 列表数据成功后，异步补齐当前批次缺封面的视频
      // 首屏优先补 20 条，后续分页优先补 10 条
      _scheduleCoverPrefetch(
        source,
        items: videos,
        limit: page == 1 ? 20 : 10,
      );
    } catch (e, st) {
      if (_isStale(token)) return;

      AppLogger.instance.logError(e, st, 'VIDEO_CONTROLLER');
      _errorMessage = '加载失败：$e';
      _log('[loadSourceData] error=$e');
    } finally {
      if (_isStale(token)) {
        _log('[loadSourceData] stale in finally token=$token');
        return;
      }

      _setLoading(false);
      notifyListeners();

      _log('[loadSourceData] finished => $debugSummary');
    }
  }

  /// 先按分类加载；如果第一页按分类没数据，自动回退到“全部”
  Future<List<VodItem>> _loadVideosWithFallback({
    required VideoSource source,
    required int? typeId,
    required int page,
  }) async {
    _log(
      '[loadVideos] request '
      'source=${_briefSource(source)} '
      'typeId=${typeId?.toString() ?? "all"} '
      'page=$page',
    );

    final videos = await _repository.loadVideos(
      source,
      typeId: typeId,
      page: page,
    );

    _log(
      '[loadVideos] result '
      'source=${source.name} '
      'typeId=${typeId?.toString() ?? "all"} '
      'page=$page '
      'count=${videos.length} '
      'sample=${_briefVideos(videos)}',
    );

    // 只有第一页才允许回退到“全部”，避免 loadMore 混入别的分类
    if (videos.isNotEmpty || typeId == null || page != 1) {
      return videos;
    }

    _log(
      '[loadVideos] fallback to all category '
      'source=${source.name} '
      'page=$page '
      'because category load returned empty',
    );

    final fallbackVideos = await _repository.loadVideos(
      source,
      typeId: null,
      page: page,
    );

    _log(
      '[loadVideos] fallback result '
      'source=${source.name} '
      'typeId=all '
      'page=$page '
      'count=${fallbackVideos.length} '
      'sample=${_briefVideos(fallbackVideos)}',
    );

    return fallbackVideos;
  }

  void _scheduleCoverPrefetch(
    VideoSource source, {
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
        items: items,
        limit: limit,
      ),
    );
  }

  Future<void> _prefetchMissingCovers({
    required VideoSource source,
    List<VodItem>? items,
    int limit = 20,
  }) async {
    if (_disposed) return;

    if (_coverPrefetchRunning) {
      _coverPrefetchQueued = true;
      return;
    }

    _coverPrefetchRunning = true;
    bool anyChanged = false;

    try {
      final activeSource = _currentSource;
      if (activeSource == null || !_sameSource(activeSource, source)) {
        _log('[prefetchMissingCovers] skipped because source changed');
        return;
      }

      final targetItems = (items ?? _videoList)
          .where((v) => !_hasText(v.vodPic))
          .take(limit)
          .toList(growable: false);

      if (targetItems.isEmpty) {
        _log('[prefetchMissingCovers] no missing cover targets');
        return;
      }

      _log(
        '[prefetchMissingCovers] start '
        'source=${source.name} '
        'limit=$limit '
        'targets=${targetItems.length}',
      );

      const int batchSize = 4;

      for (int i = 0; i < targetItems.length; i += batchSize) {
        if (_disposed) break;

        final batch = targetItems.skip(i).take(batchSize).toList(growable: false);
        bool batchChanged = false;

        final results = await Future.wait<VodItem?>(
          batch.map((item) async {
            if (_disposed) return null;

            final currentSource = _currentSource;
            if (currentSource == null || !_sameSource(currentSource, source)) {
              return null;
            }

            return VodDetailFillService.instance.fill(
              source: source,
              vodId: item.vodId,
              baseItem: item,
            );
          }),
        );

        for (final filled in results) {
          if (_disposed || filled == null) continue;

          if (_hasText(filled.vodPic)) {
            final updated = _replaceVideoItemByVodId(filled);
            if (updated) {
              batchChanged = true;
              anyChanged = true;
              _log(
                '[prefetchMissingCovers] cover filled '
                'vodId=${filled.vodId} '
                'vodName=${filled.vodName} '
                'vodPic=${filled.vodPic}',
              );
            }
          }
        }

        if (batchChanged && !_disposed) {
          notifyListeners();
        }
      }
    } catch (e, st) {
      AppLogger.instance.logError(e, st, 'VIDEO_CONTROLLER');
      _log('[prefetchMissingCovers] error=$e');
    } finally {
      _coverPrefetchRunning = false;

      if (_coverPrefetchQueued && !_disposed) {
        _coverPrefetchQueued = false;
        final currentSource = _currentSource;
        if (currentSource != null) {
          unawaited(
            _prefetchMissingCovers(
              source: currentSource,
              items: List<VodItem>.from(_videoList),
              limit: limit,
            ),
          );
        }
      } else {
        _coverPrefetchQueued = false;
      }

      _log('[prefetchMissingCovers] done changed=$anyChanged');
    }
  }

  bool _replaceVideoItemByVodId(VodItem updated) {
    final index = _videoList.indexWhere((e) => e.vodId == updated.vodId);
    if (index < 0) return false;

    _videoList[index] = updated;
    return true;
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