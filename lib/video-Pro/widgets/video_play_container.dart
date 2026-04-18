import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../utils/app_logger.dart';
import '../controller/history_controller.dart';
import 'player/custom_video_controls.dart';
import 'player/player_history_tracker.dart';
import 'player/player_overlays.dart';
import 'player/player_request_headers.dart';
import 'player/player_stream_resolver.dart';
import 'player/video_play_args.dart';

class VideoPlayContainer extends StatefulWidget {
  final String url;
  final String title;
  final String vodId;
  final String vodPic;
  final String sourceId;
  final String sourceName;
  final String episodeName;
  final int initialPosition;
  final VoidCallback? onPreviousEpisode;
  final VoidCallback? onNextEpisode;
  final String? referer;
  final Map<String, String>? httpHeaders;
  final String userAgent;
  final bool showDebugInfo;

  const VideoPlayContainer({
    super.key,
    required this.url,
    required this.title,
    this.vodId = '',
    this.vodPic = '',
    this.sourceId = '',
    this.sourceName = '',
    this.episodeName = '正片',
    this.initialPosition = 0,
    this.onPreviousEpisode,
    this.onNextEpisode,
    this.referer,
    this.httpHeaders,
    this.userAgent =
        'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0 Mobile Safari/537.36',
    this.showDebugInfo = false,
  });

  @override
  State<VideoPlayContainer> createState() => _VideoPlayContainerState();
}

class _VideoPlayContainerState extends State<VideoPlayContainer>
    with WidgetsBindingObserver {
  static const Duration _resolveTimeout = Duration(seconds: 8);
  static const Duration _initTimeout = Duration(seconds: 12);

  final PlayerStreamResolver _streamResolver = const PlayerStreamResolver();

  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  PlayerHistoryTracker? _historyTracker;

  bool _isBuffering = true;
  bool _playbackFailed = false;
  bool _isFullScreen = false;

  String? _errorMessage;
  int _initToken = 0;
  Uri? _resolvedUri;

  /// 全屏切换遮罩
  bool _suspendLifecyclePause = false;
  int _fullscreenToggleToken = 0;

  VideoPlayArgs get _playArgs => VideoPlayArgs(
        url: widget.url,
        title: widget.title,
        vodId: widget.vodId,
        vodPic: widget.vodPic,
        sourceId: widget.sourceId,
        sourceName: widget.sourceName,
        episodeName: widget.episodeName,
        initialPosition: widget.initialPosition,
        onPreviousEpisode: widget.onPreviousEpisode,
        onNextEpisode: widget.onNextEpisode,
        referer: widget.referer,
        httpHeaders: widget.httpHeaders,
        userAgent: widget.userAgent,
        showDebugInfo: widget.showDebugInfo,
      );

  // 🏆 优化：移除 MediaQuery 依赖。非全屏下固定 16/9，全屏下由系统 Route 撑满。
  double get _layoutAspectRatio => 16 / 9;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPlayer();
  }

  @override
  void didUpdateWidget(covariant VideoPlayContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.initialPosition != widget.initialPosition) {
      unawaited(_historyTracker?.saveNow(force: true));
      _initPlayer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 🚀 终极修复：彻底不响应 AppLifecycleState！
    // 理由：Android 全屏下点击屏幕弹出虚拟导航栏会错误触发 AppLifecycleState.inactive。
    // 为了极致的稳定点播体验，移除这里的 pause 逻辑。
    return;
  }

  void _onPlayerStateChanged() {
    if (!mounted) return;
    final controller = _videoPlayerController;
    if (controller == null) return;

    final value = controller.value;
    if (value.hasError) {
      _failFast(value.errorDescription ?? '视频流已断开或无效');
      return;
    }

    _historyTracker?.setPlaying(value.isPlaying);

    if (value.isBuffering != _isBuffering) {
      setState(() => _isBuffering = value.isBuffering);
    }
  }

  void _onChewieStateChanged() {
    final chewie = _chewieController;
    if (chewie == null || !mounted) return;

    final now = chewie.isFullScreen;
    if (now != _isFullScreen) {
      setState(() => _isFullScreen = now);
    }
  }

  Future<void> _toggleFullScreenSafely() async {
    final chewie = _chewieController;
    if (chewie == null) return;

    final token = ++_fullscreenToggleToken;
    _suspendLifecyclePause = true;

    try {
      chewie.toggleFullScreen();
    } finally {
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (!mounted || token != _fullscreenToggleToken) return;
        _suspendLifecyclePause = false;
      });
    }
  }

  Future<void> _initPlayer() async {
    final int token = ++_initToken;
    _disposePlayer();

    if (!mounted) return;

    setState(() {
      _isBuffering = true;
      _errorMessage = null;
      _playbackFailed = false;
      _isFullScreen = false;
    });

    final rawUrl = normalizePlayableUrl(widget.url);
    if (rawUrl.isEmpty) {
      _failFast('播放地址为空');
      return;
    }

    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !uri.hasScheme || isInvalidWebPageUrl(uri)) {
      _failFast('无效的播放地址');
      return;
    }

    try {
      final headers = buildPlayerHeaders(
        userAgent: widget.userAgent,
        referer: widget.referer,
        extraHeaders: widget.httpHeaders,
      );

      final playableUri = await _streamResolver
          .resolveDirectM3u8(uri, headers: headers)
          .timeout(_resolveTimeout);

      if (!mounted || token != _initToken) return;
      _resolvedUri = playableUri;

      if (!kIsWeb && playableUri.path.toLowerCase().contains('.m3u8')) {
        final probeOk = await _streamResolver
            .probeHls(playableUri, headers: headers)
            .timeout(const Duration(seconds: 6));
        if (!mounted || token != _initToken) return;
        if (!probeOk) {
          _failFast('该线路服务器拒绝连接');
          return;
        }
      }

      final formatHint = playableUri.path.toLowerCase().contains('.m3u8')
          ? VideoFormat.hls
          : null;

      final controller = VideoPlayerController.networkUrl(
        playableUri,
        formatHint: formatHint,
        httpHeaders: kIsWeb ? const {} : headers,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );

      _videoPlayerController = controller;
      controller.addListener(_onPlayerStateChanged);
      await controller.initialize().timeout(_initTimeout);

      if (!mounted || token != _initToken) {
        _disposePlayer();
        return;
      }

      // Seek to history position
      if (widget.initialPosition > 0 && controller.value.duration > Duration.zero) {
        final initial = Duration(milliseconds: widget.initialPosition);
        await controller.seekTo(controller.value.duration > initial ? initial : controller.value.duration);
      }

      _chewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        looping: false,
        allowMuting: true,
        allowFullScreen: true,
        showControlsOnInitialize: false,
        // 🚀 核心修复：在此设为 null。
        // 这样在全屏模式下，视频会自动填充可用空间而不会被比例锁死导致左右黑边过大或画面塌陷。
        aspectRatio: null, 
        customControls: CustomVideoControls(
          title: widget.title,
          episodeName: widget.episodeName,
          onPrevious: widget.onPreviousEpisode,
          onNext: widget.onNextEpisode,
          onToggleFullScreen: _toggleFullScreenSafely,
        ),
      );

      _chewieController!.addListener(_onChewieStateChanged);
      _isFullScreen = _chewieController!.isFullScreen;

      _historyTracker = PlayerHistoryTracker(
        historyController: context.read<HistoryController>(),
        args: _playArgs,
      )..attach(controller);

      if (!mounted || token != _initToken) {
        _disposePlayer();
        return;
      }

      setState(() {
        _errorMessage = null;
        _isBuffering = false;
      });

      _historyTracker?.setPlaying(controller.value.isPlaying);
      
    } catch (e, st) {
      if (token != _initToken) return;
      AppLogger.instance.logError(e, st, 'PLAYER');
      _failFast(e is TimeoutException ? '连接超时' : '播放失败');
    }
  }

  void _failFast(String msg, [Object? debugObject]) {
    if (_playbackFailed) return;
    _playbackFailed = true;
    _disposePlayer();
    if (!mounted) return;
    setState(() {
      _errorMessage = msg;
      _isBuffering = false;
    });
  }

  Future<void> _retry() async => _initPlayer();

  void _disposePlayer() {
    _historyTracker?.stop();
    _historyTracker = null;
    _videoPlayerController?.removeListener(_onPlayerStateChanged);
    _chewieController?.removeListener(_onChewieStateChanged);
    _chewieController?.dispose();
    _chewieController = null;
    _videoPlayerController?.dispose();
    _videoPlayerController = null;
  }

  String _buildDebugInfo() {
    final controller = _videoPlayerController;
    if (controller == null) return 'no data';
    final value = controller.value;
    return 'pos=${value.position.inSeconds}s | dur=${value.duration.inSeconds}s | buf=${value.isBuffering}';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ++_initToken;
    unawaited(_historyTracker?.saveNow(force: true));
    _disposePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 渲染比例容器
    Widget content;
    if (_errorMessage != null) {
      content = PlayerErrorOverlay(errorMessage: _errorMessage!, onRetry: _retry);
    } else if (_videoPlayerController == null || _chewieController == null || !_videoPlayerController!.value.isInitialized) {
      content = const PlayerBufferingOverlay();
    } else {
      content = Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: Chewie(controller: _chewieController!)),
          if (_isBuffering) const PlayerBufferingOverlay(),
          if (widget.showDebugInfo) PlayerDebugOverlay(info: _buildDebugInfo()),
        ],
      );
    }

    return AspectRatio(
      aspectRatio: _layoutAspectRatio,
      child: ClipRect(
        child: ColoredBox(
          color: Colors.black,
          child: content,
        ),
      ),
    );
  }
}