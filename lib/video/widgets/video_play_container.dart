import 'dart:async';
import 'dart:io' show File;
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
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

/// Locks fullscreen requests until Chewie reports the requested state or a
/// bounded recovery timer expires. Platform callbacks can be lost during
/// rotation, route teardown and lifecycle transitions; a gate must never stay
/// locked indefinitely.
class FullscreenToggleGate {
  FullscreenToggleGate(
    this._toggle, {
    bool initialValue = false,
    this.unlockTimeout = const Duration(seconds: 2),
  }) : _actualValue = initialValue;

  final VoidCallback _toggle;
  final Duration unlockTimeout;
  bool _actualValue;
  bool _isLocked = false;
  bool? _expectedValue;
  Timer? _unlockTimer;

  bool get isLocked => _isLocked;

  void request() {
    if (_isLocked) return;
    _isLocked = true;
    _expectedValue = !_actualValue;
    _unlockTimer?.cancel();
    _unlockTimer = Timer(unlockTimeout, reset);
    _toggle();
  }

  void onFullScreenChanged(bool value) {
    _actualValue = value;
    if (_isLocked && value == _expectedValue) reset();
  }

  /// Call on lifecycle recovery, controller replacement and disposal.
  void reset() {
    _unlockTimer?.cancel();
    _unlockTimer = null;
    _isLocked = false;
    _expectedValue = null;
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
  final VoidCallback? onFallbackLine;
  final String? referer;
  final Map<String, String>? httpHeaders;
  final String userAgent;
  final bool showDebugInfo;

  /// 本地文件路径（离线播放时使用）。当此值非空时，优先使用本地文件播放。
  final String? localPath;

  /// 下载完成时原生端报告的总字节数；用于播放前拒绝不完整文件。
  final int localFileExpectedBytes;

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
    this.onFallbackLine,
    this.referer,
    this.httpHeaders,
    this.userAgent =
        'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0 Mobile Safari/537.36',
    this.showDebugInfo = false,
    this.localPath,
    this.localFileExpectedBytes = 0,
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
    onFallbackLine: widget.onFallbackLine,
    referer: widget.referer,
    httpHeaders: widget.httpHeaders,
    userAgent: widget.userAgent,
    showDebugInfo: widget.showDebugInfo,
    localPath: widget.localPath,
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
    // 切集：同步抓当前进度快照后让写入在后台跑，新流解析立即开始，
    // 不再被本地历史 IO 串行阻塞。saveSnapshot 已在调用时刻读出
    // pos/dur，随后 _initPlayer 里 dispose 旧 controller 也不会污染这次保存。
    unawaited(_historyTracker?.saveSnapshot());
    await _initPlayer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _fullscreenToggleGate?.reset();
    }

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

  /// 播放失败计数——用于连续失败回退。
  int _consecutiveFailures = 0;

  void _onPlayerStateChanged() {
    if (!mounted) return;
    final controller = _videoPlayerController;
    if (controller == null) return;

    final value = controller.value;
    if (value.hasError) {
      // B2：连续失败回退——换线重试仍然失败时，回退到上一线路的同一集。
      _consecutiveFailures++;
      if (_consecutiveFailures >= 2 && widget.onFallbackLine != null) {
        widget.onFallbackLine!();
        _consecutiveFailures = 0;
        return;
      }
      _failFast(value.errorDescription ?? '视频流已断开或无效');
      return;
    }

    // 成功起播或恢复播放时重置计数器。
    if (!_playbackFailed) {
      _consecutiveFailures = 0;
    }

    if (value.isCompleted && !_hasSavedCompletion) {
      _hasSavedCompletion = true;
      unawaited(_historyTracker?.saveNow(force: true));
      // A1：播放完成自动续播——仅在存在下一集且尚未触发过续播时执行。
      if (widget.onNextEpisode != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.onNextEpisode != null) {
            widget.onNextEpisode!();
          }
        });
      }
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

  /// 初始化本地文件播放器（离线播放）。
  bool _isValidCompletedFile(File file, int expectedBytes) {
    if (!file.existsSync() || file.lengthSync() <= 0) return false;
    // 有明确总长度时，拒绝明显不完整的文件；未知长度只校验非空。
    return expectedBytes <= 0 || file.lengthSync() >= expectedBytes;
  }

  Future<void> _initLocalPlayer(
    int token,
    String localPath, {
    int expectedBytes = 0,
  }) async {
    if (!mounted || token != _initToken) return;

    final file = File(localPath);
    if (!_isValidCompletedFile(file, expectedBytes)) {
      if (!mounted || token != _initToken) return;
      final actualBytes = file.existsSync() ? file.lengthSync() : 0;
      _failFast(
        expectedBytes > 0 && actualBytes > 0
            ? '本地文件下载不完整（$actualBytes / $expectedBytes 字节）'
            : '本地文件不存在或为空',
      );
      return;
    }

    if (!mounted || token != _initToken) return;

    final historyController = context.read<HistoryController>();

    try {
      final controller = VideoPlayerController.file(file)
        ..setVolume(1.0)
        ..setLooping(false);

      controller.addListener(_onPlayerStateChanged);
      _videoPlayerController = controller;

      // 绑定历史记录追踪器
      _historyTracker = PlayerHistoryTracker(
        historyController: historyController,
        args: VideoPlayArgs(
          url: localPath,
          title: widget.title,
          vodId: widget.vodId,
          vodPic: widget.vodPic,
          sourceId: widget.sourceId,
          sourceName: widget.sourceName,
          episodeName: widget.episodeName,
          initialPosition: widget.initialPosition,
        ),
      )..attach(controller);

      // HLS 预探测跳过（本地文件不需要）
      await controller.initialize().timeout(_initTimeout);

      if (!mounted || token != _initToken) {
        _disposePlayer();
        return;
      }

      _chewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        looping: false,
        aspectRatio: _layoutAspectRatio,
        allowFullScreen: true,
        allowMuting: true,
        allowPlaybackSpeedChanging: false,
        customControls: CustomVideoControls(
          title: widget.title,
          episodeName: widget.episodeName,
        ),
      );

      if (!mounted) return;
      setState(() {
        _isBuffering = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted || token != _initToken) return;
      _failFast('本地视频加载失败: ${e.toString().replaceAll('Exception: ', '')}');
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
      _hasSavedCompletion = false;
      _isFullScreen = false;
      _consecutiveFailures = 0;
    });

    // ── 离线播放：优先使用本地文件 ──
    if (widget.localPath != null && widget.localPath!.isNotEmpty) {
      await _initLocalPlayer(
        token,
        widget.localPath!,
        expectedBytes: widget.localFileExpectedBytes,
      );
      return;
    }

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

      final formatHint = playableUri.path.toLowerCase().contains('.m3u8')
          ? VideoFormat.hls
          : null;

      final controller = VideoPlayerController.networkUrl(
        playableUri,
        formatHint: formatHint,
        httpHeaders: kIsWeb ? const {} : headers,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
      );

      controller.addListener(_onPlayerStateChanged);

      // HLS 初始化与预探测并发，但无论哪一路先失败，都必须等待
      // controller.initialize() 安全收敛后才能释放 controller。否则原生层
      // 仍在创建播放器时 dispose，会触发竞态/未处理异步错误。
      final initFuture = controller.initialize().timeout(_initTimeout);
      final initSettled = initFuture.then<void>((_) {}, onError: (_, _) {});

      try {
        if (!kIsWeb && playableUri.path.toLowerCase().contains('.m3u8')) {
          final probeFuture = _streamResolver
              .probeHls(playableUri, headers: headers)
              .timeout(const Duration(seconds: 6), onTimeout: () => false);
          final guard = Completer<void>();

          unawaited(
            initFuture.then(
              (_) {
                if (!guard.isCompleted) guard.complete();
              },
              onError: (Object e, StackTrace st) {
                if (!guard.isCompleted) guard.completeError(e, st);
              },
            ),
          );
          unawaited(
            probeFuture.then(
              (ok) {
                if (!ok && !guard.isCompleted) {
                  guard.completeError(const _StreamRejectedException());
                }
              },
              onError: (Object e, StackTrace st) {
                if (!guard.isCompleted) guard.completeError(e, st);
              },
            ),
          );

          // init 先成功 -> 直接起播；探测先判死/超时 -> 提前失败。
          await guard.future;
        }

        await initFuture;
      } catch (e) {
        await initSettled;
        controller.removeListener(_onPlayerStateChanged);
        await controller.dispose();
        rethrow;
      }

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
      final String msg;
      if (e is _StreamRejectedException) {
        msg = '该线路服务器拒绝连接';
      } else if (e is TimeoutException) {
        msg = '连接超时';
      } else {
        msg = '播放失败';
      }
      _failFast(msg);
    }
  }

  void _failFast(String msg) {
    if (_playbackFailed) return;
    _playbackFailed = true;
    _consecutiveFailures = 0;
    _disposePlayer();
    if (!mounted) return;
    setState(() {
      _errorMessage = msg;
      _isBuffering = false;
    });
  }

  Future<void> _retry() async => _initPlayer();

  void _disposePlayer() {
    _fullscreenToggleGate?.reset();
    _fullscreenToggleGate = null;
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
    // 同步抓快照后再 dispose：saveNow 是异步链，写入时 controller 可能已被
    // _disposePlayer 释放，读到脏数据。saveSnapshot 在此刻立即读出 pos/dur。
    unawaited(_historyTracker?.saveSnapshot());
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
        onFallbackLine: widget.onFallbackLine,
      );
    } else if (_videoPlayerController == null ||
        _chewieController == null ||
        !_videoPlayerController!.value.isInitialized) {
      // 起播时用列表已缓存的封面做模糊垫底，体感“秒有画面”，
      // 而不是纯黑底 spinner。封面命中内存缓存，零额外拉取。
      final pic = widget.vodPic.trim();
      if (pic.isEmpty) {
        content = const PlayerBufferingOverlay();
      } else {
        content = Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: pic,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(color: Colors.black.withValues(alpha: 0.35)),
              ),
            ),
            const PlayerBufferingOverlay(),
          ],
        );
      }
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

/// HLS 预探测在 init 完成前先判定线路不可用时抛出，用于提前失败。
class _StreamRejectedException implements Exception {
  const _StreamRejectedException();
  @override
  String toString() => '该线路服务器拒绝连接';
}
