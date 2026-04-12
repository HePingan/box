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
  /// 解析阶段超时，给得稍微宽一点，避免一些慢站点误判
  static const Duration _resolveTimeout = Duration(seconds: 8);

  /// 播放器初始化超时
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

  double get _aspectRatio =>
      (_videoPlayerController?.value.aspectRatio ?? 0) > 0
          ? _videoPlayerController!.value.aspectRatio
          : 16 / 9;

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

    if (state == AppLifecycleState.paused) {
      _wasPlayingBeforePause = controller.value.isPlaying;
      unawaited(_historyTracker?.saveNow(force: true));
      if (controller.value.isPlaying) {
        controller.pause();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_wasPlayingBeforePause) {
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

  Future<void> _initPlayer() async {
    final int token = ++_initToken;

    _disposePlayer();

    if (!mounted) return;

    setState(() {
      _isBuffering = true;
      _errorMessage = null;
      _playbackFailed = false;
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

      // 解析直接可播放地址（例如 share 页 -> m3u8）
      final playableUri = await _streamResolver
          .resolveDirectM3u8(uri, headers: headers)
          .timeout(_resolveTimeout);

      if (!mounted || token != _initToken) return;
      _resolvedUri = playableUri;

      // HLS 可用性探测
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

      // 底层播放器初始化
      await controller.initialize().timeout(_initTimeout);

      if (!mounted || token != _initToken) {
        _disposePlayer();
        return;
      }

      // 起始播放位置
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
        aspectRatio:
            controller.value.aspectRatio > 0 ? controller.value.aspectRatio : 16 / 9,
        customControls: CustomVideoControls(
          title: widget.title,
          episodeName: widget.episodeName,
          onPrevious: widget.onPreviousEpisode,
          onNext: widget.onNextEpisode,
        ),
      );

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
    if (_errorMessage != null) {
      return AspectRatio(
        aspectRatio: _aspectRatio,
        child: Container(
          color: Colors.black,
          child: PlayerErrorOverlay(
            errorMessage: _errorMessage!,
            onRetry: _retry,
          ),
        ),
      );
    }

    if (_videoPlayerController == null ||
        _chewieController == null ||
        !_videoPlayerController!.value.isInitialized) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: Colors.black,
          child: const PlayerBufferingOverlay(),
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
        aspectRatio: _aspectRatio,
        child: Container(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Chewie(controller: _chewieController!),
              if (_isBuffering) const PlayerBufferingOverlay(),
              if (widget.showDebugInfo)
                PlayerDebugOverlay(info: _buildDebugInfo()),
            ],
          ),
        ),
      ),
    );
  }
}