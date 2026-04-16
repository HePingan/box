import 'package:flutter/material.dart';

import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../pages/detail/detail_models.dart';
import '../pages/detail/detail_play_parser.dart';
import '../services/video_api_service.dart';
import '../../utils/app_logger.dart';

class VideoDetailController extends ChangeNotifier {
  final VideoSource source;
  final int vodId;
  final String? initialEpisodeUrl;
  final int initialPosition;

  VodItem? fullDetail;
  List<DetailPlayLine> playLines = [];
  bool isLoading = true;
  String? errorMessage;

  int selectedLineIndex = 0;
  int selectedEpisodeIndex = 0;

  String? currentEpisodeUrl;
  String? currentEpisodeName;

  bool _resumeApplied = false;
  String? resumeMessage; // 用于通知 UI 弹出 Snackbar

  bool _disposed = false;

  VideoDetailController({
    required this.source,
    required this.vodId,
    this.initialEpisodeUrl,
    this.initialPosition = 0,
  }) {
    loadDetail();
  }

  void _log(String message) {
    AppLogger.instance.log(message, tag: 'DETAIL_CTRL');
  }

  Future<void> loadDetail() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final detailUrl =
          source.detailUrl.trim().isNotEmpty ? source.detailUrl : source.url;
      _log('开始加载详情，vodId=$vodId, detailUrl=$detailUrl');

      // 获取详情数据
      final detail = await VideoApiService.fetchDetail(detailUrl, vodId);

      if (_disposed) return;

      if (detail == null) {
        isLoading = false;
        errorMessage = '视频详情加载失败或不存在';
        notifyListeners();
        return;
      }

      fullDetail = detail;
      playLines = DetailPlayParser.buildPlayLines(detail, source);

      // 这里改成：优先选择 m3u8 线路
      final defaultSelection = _pickDefaultSelection(
        playLines,
        initialEpisodeUrl: initialEpisodeUrl,
      );

      selectedLineIndex = defaultSelection.lineIndex;
      selectedEpisodeIndex = defaultSelection.episodeIndex;
      currentEpisodeUrl = defaultSelection.url;
      currentEpisodeName = defaultSelection.name;

      _resumeApplied = false;

      // 检查是否命中了历史续播
      final initialUrl = initialEpisodeUrl?.trim();
      if (initialPosition > 0 &&
          initialUrl != null &&
          initialUrl.isNotEmpty &&
          currentEpisodeUrl != null) {
        if (DetailPlayParser.sameUrl(currentEpisodeUrl!, initialUrl)) {
          resumeMessage =
              '已为你恢复到上次播放位置：${DetailPlayParser.formatPosition(initialPosition)}';
        }
      }

      isLoading = false;
      notifyListeners();
    } catch (e) {
      if (_disposed) return;
      isLoading = false;
      errorMessage = '加载失败：$e';
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

    // 没命中历史地址时，直接优先选择 m3u8 线路
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
    final firstPlayableIndex = lines.indexWhere((line) => line.episodes.isNotEmpty);
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

    for (var i = 0; i < lines.length; i++) {
      if (_isM3u8Line(lines[i])) {
        return i;
      }
    }

    final firstPlayableIndex = lines.indexWhere((line) => line.episodes.isNotEmpty);
    return firstPlayableIndex >= 0 ? firstPlayableIndex : 0;
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

  void selectLine(int index) {
    if (index < 0 || index >= playLines.length) return;
    final line = playLines[index];
    if (line.episodes.isEmpty) return;

    selectedLineIndex = index;
    selectedEpisodeIndex = 0; // 切换线路默认选第一集
    currentEpisodeUrl = line.episodes.first.url;
    currentEpisodeName = line.episodes.first.name;
    _resumeApplied = true;
    notifyListeners();
  }

  void selectEpisode(int index) {
    if (playLines.isEmpty) return;
    final safeLineIndex = selectedLineIndex.clamp(0, playLines.length - 1).toInt();
    final line = playLines[safeLineIndex];

    if (index < 0 || index >= line.episodes.length) return;
    final episode = line.episodes[index];
    if (currentEpisodeUrl == episode.url) return;

    selectedLineIndex = safeLineIndex;
    selectedEpisodeIndex = index;
    currentEpisodeUrl = episode.url;
    currentEpisodeName = episode.name;
    _resumeApplied = true;
    notifyListeners();
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
    final safeLineIndex = selectedLineIndex.clamp(0, playLines.length - 1).toInt();
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