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

/// Locks fullscreen requests until Chewie reports the requested state.
class FullscreenToggleGate {
  FullscreenToggleGate(this._toggle, {bool initialValue = false})
    : _actualValue = initialValue;

  final VoidCallback _toggle;
  bool _actualValue;
  bool _isLocked = false;
  bool? _expectedValue;

  bool get isLocked => _isLocked;

  void request() {
    if (_isLocked) return;
    _isLocked = true;
    _expectedValue = !_actualValue;
    _toggle();
  }

  void onFullScreenChanged(bool value) {
    _actualValue = value;
    if (_isLocked && value == _expectedValue) {
      _isLocked = false;
      _expectedValue = null;
    }
  }
}

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
  bool _wasPlayingBeforeBackground = false;
  bool _hasSavedCompletion = false;
  int _initToken = 0;
  FullscreenToggleGate? _fullscreenToggleGate;

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
    if (oldWidget.url != widget.url ||
        oldWidget.initialPosition != widget.initialPosition) {
      unawaited(_saveThenInitialize());
    }
  }

  Future<void> _saveThenInitialize() async {
    await _historyTracker?.saveNow(force: true);
    if (mounted) await _initPlayer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _videoPlayerController;
    if (controller == null) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _wasPlayingBeforeBackground = controller.value.isPlaying;
      if (_wasPlayingBeforeBackground) unawaited(controller.pause());
      unawaited(_historyTracker?.saveNow(force: true));
      return;
    }

    if (state == AppLifecycleState.resumed && _wasPlayingBeforeBackground) {
      _wasPlayingBeforeBackground = false;
      unawaited(controller.play());
    }
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

    if (value.isCompleted && !_hasSavedCompletion) {
      _hasSavedCompletion = true;
      unawaited(_historyTracker?.saveNow(force: true));
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
    _fullscreenToggleGate?.onFullScreenChanged(now);
    if (now != _isFullScreen) {
      setState(() => _isFullScreen = now);
    }
  }

  void _toggleFullScreenSafely() {
    _fullscreenToggleGate?.request();
  }

  Future<void> _initPlayer() async {
    final int token = ++_initToken;
    _disposePlayer();

    if (!mounted) return;

    setState(() {
      _isBuffering = true;
      _errorMessage = null;
      _playbackFailed = false;
      _hasSavedCompletion = false;
      _isFullScreen = false;
    });

    final rawUrl = normalizePlayableUrl(widget.url);
    if (rawUrl.isEmpty) {
      _failFast('播放地址为空');
      return;
    }

    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        !isAllowedRemoteMediaUri(uri) ||
        isInvalidWebPageUrl(uri)) {
      _failFast('播放地址无效或不安全');
      return;
    }

    final historyController = context.read<HistoryController>();

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

      controller.addListener(_onPlayerStateChanged);
      await controller.initialize().timeout(_initTimeout);

      if (!mounted || token != _initToken) {
        controller.removeListener(_onPlayerStateChanged);
        await controller.dispose();
        return;
      }

      _videoPlayerController = controller;

      // Seek to history position
      if (widget.initialPosition > 0 &&
          controller.value.duration > Duration.zero) {
        final initial = Duration(milliseconds: widget.initialPosition);
        await controller.seekTo(
          controller.value.duration > initial
              ? initial
              : controller.value.duration,
        );
      }

      if (!mounted || token != _initToken) {
        controller.removeListener(_onPlayerStateChanged);
        await controller.dispose();
        return;
      }

      final chewie = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        looping: false,
        allowMuting: true,
        allowFullScreen: true,
        showControlsOnInitialize: false,
        aspectRatio: null,
        customControls: CustomVideoControls(
          title: widget.title,
          episodeName: widget.episodeName,
          onPrevious: widget.onPreviousEpisode,
          onNext: widget.onNextEpisode,
          onToggleFullScreen: _toggleFullScreenSafely,
        ),
      );
      chewie.addListener(_onChewieStateChanged);

      if (!mounted || token != _initToken) {
        chewie.removeListener(_onChewieStateChanged);
        chewie.dispose();
        controller.removeListener(_onPlayerStateChanged);
        await controller.dispose();
        return;
      }

      _chewieController = chewie;
      _isFullScreen = chewie.isFullScreen;
      _fullscreenToggleGate = FullscreenToggleGate(
        chewie.toggleFullScreen,
        initialValue: _isFullScreen,
      );
      _historyTracker = PlayerHistoryTracker(
        historyController: historyController,
        args: _playArgs,
      )..attach(controller);

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

  void _failFast(String msg) {
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
      content = PlayerErrorOverlay(
        errorMessage: _errorMessage!,
        onRetry: _retry,
      );
    } else if (_videoPlayerController == null ||
        _chewieController == null ||
        !_videoPlayerController!.value.isInitialized) {
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
        child: ColoredBox(color: Colors.black, child: content),
      ),
    );
  }
}
