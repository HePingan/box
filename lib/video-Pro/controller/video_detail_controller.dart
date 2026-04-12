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
      final detailUrl = source.detailUrl.trim().isNotEmpty ? source.detailUrl : source.url;
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
      
      // 选取默认播放集数或历史续播集数
      final defaultSelection = DetailPlayParser.pickDefaultSelection(
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
      if (initialPosition > 0 && initialUrl != null && initialUrl.isNotEmpty && currentEpisodeUrl != null) {
        if (DetailPlayParser.sameUrl(currentEpisodeUrl!, initialUrl)) {
          resumeMessage = '已为你恢复到上次播放位置：${DetailPlayParser.formatPosition(initialPosition)}';
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
    if (initialUrl == null || initialUrl.isEmpty || currentEpisodeUrl == null) return 0;
    return DetailPlayParser.sameUrl(currentEpisodeUrl!, initialUrl) ? initialPosition : 0;
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