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
import '../services/player_startup_resolver.dart';
import 'player/custom_video_controls.dart';
import 'player/line_failover_policy.dart';
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
  /// 播放器默认 UA。详情页预热与播放器起播必须用同一个，否则同一地址
  /// 可能被源站按 UA 给出不同结果（缓存键含 Referer 不含 UA，见
  /// [PlayerStartupResolver.keyFor]）。
  static const String defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/123.0 Mobile Safari/537.36';

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

  /// 下一集的原始地址（可能还是云播页）。播放开始后在后台预热，
  /// 切下一集/自动续播时直接吃缓存 —— 不必再等一次解析
  /// （实测正常线路 146ms~1.9s，坏线路最坏十几秒）。null = 没有下一集。
  final String? nextEpisodeUrl;

  /// 需要在播放器上说一句话（例如「已自动换线路」）时用。
  final void Function(String message)? onNotice;

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
    this.userAgent = defaultUserAgent,
    this.showDebugInfo = false,
    this.nextEpisodeUrl,
    this.onNotice,
    this.localPath,
    this.localFileExpectedBytes = 0,
  });

  @override
  State<VideoPlayContainer> createState() => _VideoPlayContainerState();
}

class _VideoPlayContainerState extends State<VideoPlayContainer>
    with WidgetsBindingObserver {
  /// 整段解析（云播页归一化 + 直连解析）的兜底上限。
  ///
  /// 实测（2026-10-03，走 App 同一条解析链）：正常线路整段 146ms ~ 1.9s，
  /// 一条不可达线路会一直等到封顶。段内超时分别由 [PlayerStartupResolver]
  /// 管（cloud 6s / stream 5s），这里只是「两段都没按时返回」时的最后一道。
  /// 原来这里是 8s 与 12s 两段串行 —— 一条坏线路能让用户干等十几秒。
  static const Duration _resolveTimeout = Duration(seconds: 12);
  static const Duration _initTimeout = Duration(seconds: 12);

  /// 起播超过这个时长就主动告诉用户一句（⑤ 起播可见化）。
  static const int _slowStartupNoticeMs = 3000;

  final PlayerStreamResolver _streamResolver = const PlayerStreamResolver();

  /// 起播链（云播页归一化 → 真流地址）：带缓存与预热，与详情页共用。
  final PlayerStartupResolver _startupResolver = PlayerStartupResolver.instance;

  // ── 起播计时（日志与调试浮层都看得到）──
  final Stopwatch _startupWatch = Stopwatch();
  int _resolveMs = 0;
  int _totalMs = 0;
  bool _cameFromCache = false;
  bool _prewarmedNext = false;
  int _lineSwitches = 0;

  /// 线路失败计数（跨重试保留：见 LineFailoverPolicy 里的说明）。
  final LineFailoverPolicy _lineFailover = LineFailoverPolicy();

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

  void _onPlayerStateChanged() {
    if (!mounted) return;
    final controller = _videoPlayerController;
    if (controller == null) return;

    final value = controller.value;
    if (value.hasError) {
      // 播放中报错也算这条线路失败一次；换线重试仍然失败就自动回退。
      _handleLineFailure(value.errorDescription ?? '视频流已断开或无效');
      return;
    }

    // 只有真正起播成功才清零失败计数——「这次没报错」不算成功。
    if (value.isInitialized && !value.isCompleted) {
      _lineFailover.recordPlaybackStarted();
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
      // 注意：线路失败计数**不在这里清零**。手动重试后计数器必须保留，
      // 否则「重试仍失败 → 自动换线路」永远触发不了（见 LineFailoverPolicy）。
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

      // 起播链：云播页（`/play/<id>`、`/share/<id>`）先换成真流地址，再解析直连 m3u8。
      // 归一化后仍是网页 → 明确判死（不再把一个 HTML 页面丢给播放器）。
      // 结果进共享缓存：同一集再进来 / 切集切回来 / 刚被预热过 —— 直接命中，不再联网。
      _cameFromCache = _startupResolver.isWarm(uri, headers);
      _startupWatch
        ..reset()
        ..start();
      final playableUri = await _startupResolver
          .resolve(uri, headers: headers)
          .timeout(_resolveTimeout);
      _resolveMs = _startupWatch.elapsedMilliseconds;

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
              .timeout(const Duration(seconds: 4), onTimeout: () => false);
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

      // ⑤ 起播可见化：日志留一行（工期/是否吃缓存/换了几次线），
      // 慢起播再主动说一句；数字同时进调试浮层。
      _startupWatch.stop();
      _totalMs = _startupWatch.elapsedMilliseconds;
      AppLogger.instance.log(
        '起播完成：解析 ${_resolveMs}ms${_cameFromCache ? '（缓存命中）' : ''}'
        ' + 初始化 ${_totalMs - _resolveMs}ms，换线 $_lineSwitches 次',
        tag: 'PLAYER',
      );
      if (_totalMs >= _slowStartupNoticeMs) {
        widget.onNotice?.call(
          '起播用了 ${(_totalMs / 1000).toStringAsFixed(1)}s'
          '${_cameFromCache ? '（缓存命中）' : ''}',
        );
      }

      // ③ 预取下一集：现在顺手解析好，切集/自动续播就零等待。
      _prewarmNextEpisode(headers);
    } catch (e, st) {
      if (token != _initToken) return;
      AppLogger.instance.logError(e, st, 'PLAYER');
      // 网页线路重试也还是网页，属于「无需再试」的失败 —— 直接换线路。
      final isPageUrl = e is UnresolvedCloudPageException;
      final String msg;
      if (isPageUrl) {
        msg = '该线路是网页线路，已自动换线路';
      } else if (e is _StreamRejectedException) {
        msg = '该线路服务器拒绝连接';
      } else if (e is TimeoutException) {
        msg = '连接超时';
      } else {
        msg = '播放失败';
      }
      _handleLineFailure(msg, decisive: isPageUrl);
    }
  }

  /// 记一次线路失败：够阈值或本次失败已无重试价值 → 自动换线路；
  /// 否则维持原来的行为，把错误显示给用户（错误层里也有「换线路重试」按钮）。
  void _handleLineFailure(String msg, {bool decisive = false}) {
    final fallback = widget.onFallbackLine;
    if (fallback != null &&
        _lineFailover.recordFailure(
          hasFallbackLine: true,
          decisive: decisive,
        )) {
      _lineSwitches++;
      // 这条地址的解析结果作废：换回来时不该再从缓存里拿到同一个坏地址。
      _invalidateResolvedAddress();
      AppLogger.instance.log(
        '线路连续失败，自动换线路（$msg）',
        tag: 'PLAYER',
      );
      // ⑤ 把「为什么换」说出来。容器会随线路切换重建（父级 key 变了），
      // 所以这句提示交给父级页面显示，不留在自己的 State 里。
      widget.onNotice?.call('$msg，已自动换线路');
      fallback();
      return;
    }
    _failFast(msg);
  }

  /// 失败地址的解析结果作废（缓存里那条可能是源站已经换掉的旧地址）。
  void _invalidateResolvedAddress() {
    final uri = Uri.tryParse(normalizePlayableUrl(widget.url));
    if (uri == null) return;
    _startupResolver.invalidate(
      uri,
      buildPlayerHeaders(
        userAgent: widget.userAgent,
        referer: widget.referer,
        extraHeaders: widget.httpHeaders,
      ),
    );
  }

  /// ③ 预取下一集：播放已经开始，这时多解析一条地址几乎不影响播放，
  /// 但切下一集（含播完自动续播）时就能直接命中缓存 —— 不用再等一次解析。
  void _prewarmNextEpisode(Map<String, String> headers) {
    if (_prewarmedNext) return;
    _prewarmedNext = true;
    final raw = widget.nextEpisodeUrl?.trim();
    if (raw == null || raw.isEmpty) return;
    final uri = Uri.tryParse(normalizePlayableUrl(raw));
    if (uri == null || !isAllowedRemoteMediaUri(uri)) return;
    _startupResolver.prewarm(uri, headers: headers);
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
    return 'pos=${value.position.inSeconds}s | dur=${value.duration.inSeconds}s | buf=${value.isBuffering}\n'
        '起播：解析 ${_resolveMs}ms${_cameFromCache ? '(缓存命中)' : ''} / 总 ${_totalMs}ms'
        ' | 换线 $_lineSwitches 次';
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
