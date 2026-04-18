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

  Timer? _attemptTimer;

  bool _isBuffering = true;
  bool _wasPlayingBeforePause = false;
  bool _playbackFailed = false;

  String? _errorMessage;
  int _initToken = 0;
  Uri? _resolvedUri;

  bool _isFullScreen = false;

  /// 全屏切换期间，临时屏蔽生命周期误判
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

  double _layoutAspectRatio(BuildContext context) {
    if (_isFullScreen) {
      final size = MediaQuery.sizeOf(context);
      if (size.height > 0) {
        return size.width / size.height;
      }
    }
    return 16 / 9;
  }

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
      unawaited(_historyTracker?.saveNow(force: true));
      _initPlayer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _videoPlayerController;
    if (controller == null) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      /// 关键：全屏切换期间不要误暂停
      if (_suspendLifecyclePause) {
        return;
      }

      _wasPlayingBeforePause = controller.value.isPlaying;
      if (controller.value.isPlaying) {
        controller.pause();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_wasPlayingBeforePause && !_suspendLifecyclePause) {
        controller.play();
      }
      _wasPlayingBeforePause = false;
    }
  }

  void _onPlayerStateChanged() {
    if (!mounted) return;

    final controller = _videoPlayerController;
    if (controller == null) return;

    final value = controller.value;

    if (value.hasError) {
      final msg = value.errorDescription ?? '视频流已断开或无效';
      AppLogger.instance.log(
        '视频播放器底层抛出异常: $msg | url=${widget.url}',
        tag: 'PLAYER_ERROR',
      );

      _failFast(msg);
      return;
    }

    _historyTracker?.setPlaying(value.isPlaying);

    if (value.isBuffering != _isBuffering) {
      setState(() => _isBuffering = value.isBuffering);
    }
  }

  void _onChewieStateChanged() {
    final chewie = _chewieController;
    if (chewie == null) return;

    final now = chewie.isFullScreen;
    if (now == _isFullScreen) return;

    _isFullScreen = now;

    if (!mounted) return;
    setState(() {});
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
        if (!mounted) return;
        if (token != _fullscreenToggleToken) return;
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
      _failFast('无效的播放地址，请尝试切换线路');
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
          _failFast('该线路服务器拒绝连接或分片已失效');
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

      if (widget.initialPosition > 0 &&
          controller.value.duration > Duration.zero) {
        final initial = Duration(milliseconds: widget.initialPosition);
        final safeInitial = controller.value.duration > initial
            ? initial
            : controller.value.duration;
        await controller.seekTo(safeInitial);
      }

      _chewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        looping: false,
        allowMuting: true,
        allowFullScreen: true,
        showControlsOnInitialize: false,
        aspectRatio: 16 / 9,
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

      _attemptTimer?.cancel();
      _attemptTimer = null;

      _historyTracker?.setPlaying(controller.value.isPlaying);
    } on TimeoutException catch (e, st) {
      AppLogger.instance.logError(e, st, 'PLAYER');

      if (!mounted || token != _initToken) {
        _disposePlayer();
        return;
      }

      _disposePlayer();
      _failFast('视频连接超时，请稍后重试', e);
    } catch (e, st) {
      AppLogger.instance.logError(e, st, 'PLAYER');

      if (!mounted || token != _initToken) {
        _disposePlayer();
        return;
      }

      _disposePlayer();
      _failFast('视频连接失败，请稍后重试', e);
    }
  }

  void _failFast(String msg, [Object? debugObject]) {
    if (_playbackFailed) return;
    _playbackFailed = true;

    if (!mounted) return;

    setState(() {
      _errorMessage = msg;
      _isBuffering = false;
    });

    _disposePlayer();
  }

  Future<void> _retry() async {
    _initPlayer();
  }

  void _disposePlayer() {
    _attemptTimer?.cancel();
    _attemptTimer = null;

    _historyTracker?.stop();
    _historyTracker = null;

    _videoPlayerController?.removeListener(_onPlayerStateChanged);

    final chewie = _chewieController;
    if (chewie != null) {
      chewie.removeListener(_onChewieStateChanged);
    }
    _chewieController = null;
    chewie?.dispose();

    final video = _videoPlayerController;
    _videoPlayerController = null;
    video?.dispose();
  }

  String _buildDebugInfo() {
    final controller = _videoPlayerController;
    if (controller == null) return 'no controller';

    final value = controller.value;
    return 'pos=${value.position.inSeconds}s | '
        'dur=${value.duration.inSeconds}s | '
        'buf=${value.isBuffering} | '
        'host=${_resolvedUri?.host ?? "-"}';
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
    final aspectRatio = _layoutAspectRatio(context);

    if (_errorMessage != null) {
      return AspectRatio(
        aspectRatio: aspectRatio,
        child: ClipRect(
          child: ColoredBox(
            color: Colors.black,
            child: PlayerErrorOverlay(
              errorMessage: _errorMessage!,
              onRetry: _retry,
            ),
          ),
        ),
      );
    }

    if (_videoPlayerController == null ||
        _chewieController == null ||
        !_videoPlayerController!.value.isInitialized) {
      return AspectRatio(
        aspectRatio: aspectRatio,
        child: ClipRect(
          child: ColoredBox(
            color: Colors.black,
            child: const PlayerBufferingOverlay(),
          ),
        ),
      );
    }

    return PopScope(
      onPopInvoked: (didPop) {
        if (didPop) {
          _disposePlayer();
        }
      },
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: ClipRect(
          child: ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: Chewie(controller: _chewieController!),
                ),
                if (_isBuffering) const PlayerBufferingOverlay(),
                if (widget.showDebugInfo)
                  PlayerDebugOverlay(info: _buildDebugInfo()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}