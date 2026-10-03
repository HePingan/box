import 'dart:async';

import 'package:flutter/material.dart';

import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../pages/detail/detail_models.dart';
import '../pages/detail/detail_play_parser.dart';
import '../services/video_api_service.dart';
import '../services/play_line_memory_repository.dart';
import '../services/favorites_repository.dart';
import '../services/line_reachability_store.dart';
import '../services/player_startup_resolver.dart';
import '../widgets/player/player_request_headers.dart';
import '../widgets/player/player_stream_resolver.dart';
import '../widgets/video_play_container.dart';
import '../../utils/app_logger.dart';

typedef DetailFetcher = Future<VodItem?> Function();

class VideoDetailController extends ChangeNotifier {
  final VideoSource source;
  final int vodId;
  final String? initialEpisodeUrl;
  final int initialPosition;
  final String? localPath;
  final bool isOfflinePlayback;
  final String? episodeName; // 离线播放时传入剧集名称
  final int localFileExpectedBytes;

  VodItem? fullDetail;
  List<DetailPlayLine> playLines = [];
  bool isLoading = true;
  String? errorMessage;

  int selectedLineIndex = 0;
  int selectedEpisodeIndex = 0;

  String? currentEpisodeUrl;
  String? currentEpisodeName;
  String? currentLocalPath; // 离线播放时存储本地文件路径
  int get expectedLocalFileBytes =>
      isOfflinePlayback ? localFileExpectedBytes : 0;

  bool _resumeApplied = false;
  String? resumeMessage; // 用于通知 UI 弹出 Snackbar

  final DetailFetcher? _detailFetcher;
  final PlayLineMemoryRepository _lineMemoryRepo;
  final FavoritesRepository _favoritesRepo;
  int _loadGeneration = 0;
  bool _disposed = false;

  bool isFavorite = false;

  VideoDetailController({
    required this.source,
    required this.vodId,
    this.initialEpisodeUrl,
    this.initialPosition = 0,
    this.localPath,
    this.isOfflinePlayback = false,
    this.episodeName,
    this.localFileExpectedBytes = 0,
    DetailFetcher? detailFetcher,
    PlayLineMemoryRepository? lineMemoryRepo,
    FavoritesRepository? favoritesRepo,
  }) : _detailFetcher = detailFetcher,
       _lineMemoryRepo = lineMemoryRepo ?? PlayLineMemoryRepository(),
       _favoritesRepo = favoritesRepo ?? FavoritesRepository() {
    _lineMemoryRepo.init();
    _initFavorite();
    loadDetail();
  }

  Future<void> _initFavorite() async {
    await _favoritesRepo.init();
    if (_disposed) return;
    isFavorite = _favoritesRepo.isFavorite(source, vodId);
    notifyListeners();
  }

  /// 切换收藏状态。收藏时写入当前影片基本信息，供收藏列表直接渲染。
  Future<void> toggleFavorite() async {
    if (isFavorite) {
      await _favoritesRepo.remove(source, vodId);
      isFavorite = false;
    } else {
      final detail = fullDetail;
      await _favoritesRepo.add(
        source,
        vodId,
        vodName: detail?.vodName.trim().isNotEmpty == true
            ? detail!.vodName.trim()
            : source.name,
        vodPic: detail?.vodPic,
        vodRemarks: detail?.vodRemarks,
        typeName: detail?.typeName,
      );
      isFavorite = true;
    }
    if (_disposed) return;
    notifyListeners();
  }

  void _log(String message) {
    AppLogger.instance.log(message, tag: 'DETAIL_CTRL');
  }

  Future<void> loadDetail() async {
    final generation = ++_loadGeneration;
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      // 离线任务只有本地文件路径；不能再请求原站详情，因为下载管理页构造的 source
      // 并不带可用 API 地址。先构造最小详情状态，让详情页直接承载本地播放器。
      if (isOfflinePlayback &&
          localPath != null &&
          localPath!.trim().isNotEmpty) {
        final title = episodeName?.trim().isNotEmpty == true
            ? episodeName!.trim()
            : '已下载视频';
        fullDetail = VodItem(vodId: vodId, vodName: title);
        playLines = const [];
        currentLocalPath = localPath;
        currentEpisodeName = title;
        isLoading = false;
        notifyListeners();
        return;
      }

      // url 是真实采集 API，detailUrl 是官网/Referer 备用；优先走 API，
      // 避免列表可用但官网没有标准详情接口时误报详情失败。
      final candidates = <String>[
        source.url.trim(),
        source.detailUrl.trim(),
      ].where((url) => url.isNotEmpty).toSet();
      _log('开始加载详情，vodId=$vodId，候选=${candidates.join(" | ")}');

      VodItem? detail;
      if (_detailFetcher != null) {
        detail = await _detailFetcher();
      } else {
        for (final baseUrl in candidates) {
          detail = await VideoApiService.fetchDetail(baseUrl, vodId);
          if (detail != null) break;
        }
      }
      if (_disposed || generation != _loadGeneration) return;

      if (detail == null) {
        isLoading = false;
        errorMessage = '视频详情加载失败或不存在';
        notifyListeners();
        return;
      }

      fullDetail = detail;
      playLines = DetailPlayParser.buildPlayLines(detail, source);

      // 离线播放：直接使用本地文件，跳过网络线路选择
      if (isOfflinePlayback && localPath != null && localPath!.isNotEmpty) {
        currentLocalPath = localPath;
        currentEpisodeName = episodeName ?? '已下载';
        isLoading = false;
        notifyListeners();
        return;
      }

      // ② 线路记忆只影响「默认选哪条线」，**绝不阻塞详情加载**：
      // 存储读不出来（首次冷启动/平台通道异常）就当没有标记，走原判据。
      // 预热放在启动时（main.dart）——若在 loadDetail 里 await，
      // 存储慢一步就会把详情页永远停在 loading（实测报警：pumpAndSettle 超时）。
      unawaited(LineReachabilityStore.ensureLoaded());

      final defaultSelection = _pickDefaultSelection(
        playLines,
        initialEpisodeUrl: initialEpisodeUrl,
      );
      selectedLineIndex = defaultSelection.lineIndex;
      selectedEpisodeIndex = defaultSelection.episodeIndex;
      currentEpisodeUrl = defaultSelection.url;
      currentEpisodeName = defaultSelection.name;
      _resumeApplied = false;

      final initialUrl = initialEpisodeUrl?.trim();
      if (initialPosition > 0 &&
          initialUrl != null &&
          initialUrl.isNotEmpty &&
          currentEpisodeUrl != null &&
          DetailPlayParser.sameUrl(currentEpisodeUrl!, initialUrl)) {
        resumeMessage =
            '已为你恢复到上次播放位置：${DetailPlayParser.formatPosition(initialPosition)}';
      }

      isLoading = false;
      notifyListeners();
    } catch (e, st) {
      _log('加载详情失败: $e\n$st');
      if (_disposed || generation != _loadGeneration) return;
      isLoading = false;
      errorMessage = '视频详情加载失败，请稍后重试';
      notifyListeners();
    }
  }

  /// 默认选线策略：
  /// 1. 如果历史地址命中，并且命中的就是 m3u8 线路，则优先保留历史
  /// 2. 如果历史命中的是非 m3u8 线路，但页面里存在 m3u8 线路，则优先切到 m3u8
  /// 3. 如果没有历史命中，则直接优先选择 m3u8 线路
  /// 4. 如果没有 m3u8 线路，则回退到第一条可播放线路
  DetailPlaybackSelection _pickDefaultSelection(
    List<DetailPlayLine> lines, {
    String? initialEpisodeUrl,
  }) {
    if (lines.isEmpty) {
      return const DetailPlaybackSelection.none();
    }

    final initial = initialEpisodeUrl?.trim();

    int? matchedLineIndex;
    int? matchedEpisodeIndex;

    // 先尝试命中历史地址
    if (initial != null && initial.isNotEmpty) {
      for (var li = 0; li < lines.length; li++) {
        final line = lines[li];
        for (var ei = 0; ei < line.episodes.length; ei++) {
          final ep = line.episodes[ei];
          if (DetailPlayParser.sameUrl(ep.url, initial)) {
            matchedLineIndex = li;
            matchedEpisodeIndex = ei;
            break;
          }
        }
        if (matchedLineIndex != null) break;
      }
    }

    // 再找 m3u8 线路
    final preferredLineIndex = _findPreferredLineIndex(lines);
    final preferredLine = lines[preferredLineIndex];

    // 如果历史命中的是 m3u8 线路，直接尊重历史
    if (matchedLineIndex != null && matchedEpisodeIndex != null) {
      final matchedLine = lines[matchedLineIndex];

      if (_isM3u8Line(matchedLine) || preferredLineIndex == matchedLineIndex) {
        final ep = matchedLine.episodes[matchedEpisodeIndex];
        return DetailPlaybackSelection(
          lineIndex: matchedLineIndex,
          episodeIndex: matchedEpisodeIndex,
          url: ep.url,
          name: ep.name,
        );
      }

      // 历史命中的是非 m3u8 线路，但存在 m3u8 线路，则优先 m3u8
      if (preferredLine.episodes.isNotEmpty) {
        final ep = preferredLine.episodes.first;
        return DetailPlaybackSelection(
          lineIndex: preferredLineIndex,
          episodeIndex: 0,
          url: ep.url,
          name: ep.name,
        );
      }

      // 理论兜底：m3u8 线路没有可用集数，则回退历史命中的那一集
      final ep = matchedLine.episodes[matchedEpisodeIndex];
      return DetailPlaybackSelection(
        lineIndex: matchedLineIndex,
        episodeIndex: matchedEpisodeIndex,
        url: ep.url,
        name: ep.name,
      );
    }

    // 没命中历史地址时，优先复原用户在本片记住的线路
    final rememberedLineIndex = _resolveRememberedLineIndex(lines);
    if (rememberedLineIndex != null) {
      final line = lines[rememberedLineIndex];
      final ep = line.episodes.first;
      return DetailPlaybackSelection(
        lineIndex: rememberedLineIndex,
        episodeIndex: 0,
        url: ep.url,
        name: ep.name,
      );
    }

    // 再优先选择 m3u8 线路
    if (preferredLine.episodes.isNotEmpty) {
      final ep = preferredLine.episodes.first;
      return DetailPlaybackSelection(
        lineIndex: preferredLineIndex,
        episodeIndex: 0,
        url: ep.url,
        name: ep.name,
      );
    }

    // 再兜底：第一条可播放线路
    final firstPlayableIndex = lines.indexWhere(
      (line) => line.episodes.isNotEmpty,
    );
    if (firstPlayableIndex >= 0) {
      final line = lines[firstPlayableIndex];
      final ep = line.episodes.first;
      return DetailPlaybackSelection(
        lineIndex: firstPlayableIndex,
        episodeIndex: 0,
        url: ep.url,
        name: ep.name,
      );
    }

    return const DetailPlaybackSelection.none();
  }

  /// 找到最优先的线路：
  /// - 线路名包含 m3u8
  /// - 或任意集数地址包含 m3u8
  /// - 否则回退到第一条可播放线路
  int _findPreferredLineIndex(List<DetailPlayLine> lines) {
    if (lines.isEmpty) return 0;

    final playable = <int>[
      for (var i = 0; i < lines.length; i++)
        if (lines[i].episodes.isNotEmpty) i,
    ];

    // ② 默认选线**跳过**「最近取不到流」的线路（chip 上也会标注出来）。
    // 但如果所有可播线路都被标过，就忽略标记 —— 那更像网络环境/代理的问题，
    // 不是线路本身的问题，此时按原判据选即可。
    final fresh = playable
        .where((index) => !_isLineUnreachable(lines[index]))
        .toList(growable: false);
    final candidates = fresh.isEmpty ? playable : fresh;

    for (final index in candidates) {
      if (_isM3u8Line(lines[index])) return index;
    }
    if (candidates.isNotEmpty) return candidates.first;
    return 0;
  }

  /// ② 这条线是否「最近取不到流」（按源 + 线路名聚合的本地记忆）。
  bool _isLineUnreachable(DetailPlayLine line) {
    return LineReachabilityStore.isRecentlyUnreachable(
      sourceKey: _reachabilitySourceKey,
      lineName: line.name,
    );
  }

  /// 供界面用：第 index 条线路最近是否取不到流。
  bool isLineRecentlyUnreachable(int index) {
    if (index < 0 || index >= playLines.length) return false;
    return _isLineUnreachable(playLines[index]);
  }

  /// 供界面用：这条线路最近的失败原因（没有就返回 null）。
  String? lineUnreachableReason(int index) {
    if (index < 0 || index >= playLines.length) return null;
    return LineReachabilityStore.failureReasonOf(
      sourceKey: _reachabilitySourceKey,
      lineName: playLines[index].name,
    );
  }

  String get _reachabilitySourceKey =>
      source.id.trim().isNotEmpty ? source.id.trim() : source.url.trim();

  /// ② 起播成功：清掉当前线路的失败标记 —— 线路恢复不该等 TTL 到期。
  Future<void> markCurrentLineStarted() async {
    if (selectedLineIndex < 0 || selectedLineIndex >= playLines.length) return;
    await LineReachabilityStore.markSuccess(
      sourceKey: _reachabilitySourceKey,
      lineName: playLines[selectedLineIndex].name,
    );
  }

  /// 根据记忆复原线路：优先按线路名匹配，名字对不上再退回记忆的索引。
  /// 返回 null 表示没有可用记忆。
  int? _resolveRememberedLineIndex(List<DetailPlayLine> lines) {
    final memory = _lineMemoryRepo.getMemory(source, vodId);
    if (memory == null) return null;

    final name = memory.lineName.trim();
    if (name.isNotEmpty) {
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].name.trim() == name && lines[i].episodes.isNotEmpty) {
          return i;
        }
      }
    }

    final idx = memory.lineIndex;
    if (idx >= 0 && idx < lines.length && lines[idx].episodes.isNotEmpty) {
      return idx;
    }

    return null;
  }

  bool _isM3u8Line(DetailPlayLine line) {
    final lineName = line.name.toLowerCase();

    if (lineName.contains('m3u8')) {
      return true;
    }

    for (final ep in line.episodes) {
      final url = ep.url.toLowerCase();
      if (url.contains('.m3u8') || url.contains('m3u8')) {
        return true;
      }
    }

    return false;
  }

  /// 在不同线路中寻找与当前集同序号的候选；调用方仅在当前线路失败时使用。
  ///
  /// 优先严格复用当前索引；若线路集数较短，则返回其最后一个有效集，避免
  /// 自动恢复落在不可播放索引上。没有其它可播放线路时返回 null。
  int? findFallbackLineIndex({int? excludingLineIndex}) {
    final candidates = <int>[
      for (var index = 0; index < playLines.length; index++)
        if (index != excludingLineIndex && playLines[index].episodes.isNotEmpty)
          index,
    ];
    if (candidates.isEmpty) return null;

    // ② 换线时优先换到**没被标记过**的线路；全被标过就按原顺序换
    // （都被标过说明更像网络环境问题，换谁都一样，别再挑）。
    for (final index in candidates) {
      if (!_isLineUnreachable(playLines[index])) return index;
    }
    return candidates.first;
  }

  /// 切换到指定线路，并尽可能保留当前集序号，用于失败恢复。
  void selectFallbackLine(int index) {
    if (index < 0 || index >= playLines.length) return;
    final line = playLines[index];
    if (line.episodes.isEmpty) return;

    // ② 记下「刚才那条线取不到流」：下次进这部片时 chip 会标注、默认也不选它。
    // 放在换线动作里记，是因为调用点只有失败恢复这一种语义。
    if (selectedLineIndex >= 0 && selectedLineIndex < playLines.length) {
      final failedLine = playLines[selectedLineIndex];
      if (failedLine.name.trim() != line.name.trim()) {
        unawaited(
          LineReachabilityStore.markFailure(
            sourceKey: _reachabilitySourceKey,
            lineName: failedLine.name,
            reason: '上次这条线路取不到流',
          ),
        );
      }
    }

    final targetEpisodeIndex = selectedEpisodeIndex
        .clamp(0, line.episodes.length - 1)
        .toInt();
    final episode = line.episodes[targetEpisodeIndex];
    selectedLineIndex = index;
    selectedEpisodeIndex = targetEpisodeIndex;
    currentEpisodeUrl = episode.url;
    currentEpisodeName = episode.name;
    _resumeApplied = true;

    unawaited(
      _lineMemoryRepo.saveMemory(
        source,
        vodId,
        lineName: line.name,
        lineIndex: index,
      ),
    );
    notifyListeners();
  }

  void selectLine(int index) {
    if (index < 0 || index >= playLines.length) return;
    final line = playLines[index];
    if (line.episodes.isEmpty) return;

    selectedLineIndex = index;
    selectedEpisodeIndex = 0; // 切换线路默认选第一集
    currentEpisodeUrl = line.episodes.first.url;
    currentEpisodeName = line.episodes.first.name;
    _resumeApplied = true;

    // 记住用户在本片手动选择的线路，下次打开自动复原
    unawaited(
      _lineMemoryRepo.saveMemory(
        source,
        vodId,
        lineName: line.name,
        lineIndex: index,
      ),
    );

    _prewarmCurrentEpisode();
    notifyListeners();
  }

  void selectEpisode(int index) {
    if (playLines.isEmpty) return;
    final safeLineIndex = selectedLineIndex
        .clamp(0, playLines.length - 1)
        .toInt();
    final line = playLines[safeLineIndex];

    if (index < 0 || index >= line.episodes.length) return;
    final episode = line.episodes[index];
    if (currentEpisodeUrl == episode.url) return;

    selectedLineIndex = safeLineIndex;
    selectedEpisodeIndex = index;
    currentEpisodeUrl = episode.url;
    currentEpisodeName = episode.name;
    _resumeApplied = true;
    _prewarmCurrentEpisode();
    notifyListeners();
  }

  /// 下一集的原始地址（可能还是云播页）—— 交给播放器在播放时预热。
  String? get nextEpisodeRawUrl {
    if (!canPlayNext()) return null;
    final line = playLines[selectedLineIndex.clamp(0, playLines.length - 1)];
    return line.episodes[selectedEpisodeIndex + 1].url;
  }

  /// 预热当前集（②）：用户点完集数通常还要一下才落到播放器，
  /// 这段时间正好把「云播页归一化 + 直连解析」做掉。
  /// 与播放器自己的解析共用同一个缓存与「在途合并」，不会重复解析。
  void _prewarmCurrentEpisode() {
    final raw = currentEpisodeUrl?.trim();
    if (raw == null || raw.isEmpty) return;
    final uri = Uri.tryParse(normalizePlayableUrl(raw));
    if (uri == null || !isAllowedRemoteMediaUri(uri)) return;
    PlayerStartupResolver.instance.prewarm(
      uri,
      // Referer / UA 必须与播放器一致（缓存键含 Referer，见 PlayerStartupResolver.keyFor）
      headers: buildPlayerHeaders(
        userAgent: VideoPlayContainer.defaultUserAgent,
        referer: source.detailUrl.isNotEmpty ? source.detailUrl : source.url,
      ),
    );
  }

  void playPrevious() {
    if (canPlayPrevious()) selectEpisode(selectedEpisodeIndex - 1);
  }

  void playNext() {
    if (canPlayNext()) selectEpisode(selectedEpisodeIndex + 1);
  }

  bool canPlayPrevious() => playLines.isNotEmpty && selectedEpisodeIndex > 0;

  bool canPlayNext() {
    if (playLines.isEmpty) return false;
    final safeLineIndex = selectedLineIndex
        .clamp(0, playLines.length - 1)
        .toInt();
    return selectedEpisodeIndex < playLines[safeLineIndex].episodes.length - 1;
  }

  // 计算传给播放器的真实初始位置
  int getEffectiveInitialPosition() {
    if (_resumeApplied) return 0; // 只要用户手动切过集，就不再使用历史定位

    final initialUrl = initialEpisodeUrl?.trim();
    if (initialUrl == null || initialUrl.isEmpty || currentEpisodeUrl == null) {
      return 0;
    }

    return DetailPlayParser.sameUrl(currentEpisodeUrl!, initialUrl)
        ? initialPosition
        : 0;
  }

  // 消费提示信息
  void consumeResumeMessage() {
    resumeMessage = null;
  }

  @override
  void dispose() {
    _disposed = true; // 关键：标识被销毁，切断网络回调
    super.dispose();
  }
}
