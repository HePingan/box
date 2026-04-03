import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../core/models.dart';
import '../core/video_url_parser.dart';
import '../video_module.dart';
import 'player/video_player_details_view.dart';
import 'player/video_player_overlays.dart';

class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    super.key,
    required this.detail,
    this.initialSourceIndex = 0,
    this.initialEpisodeIndex = 0,
  });

  final VideoDetail detail;
  final int initialSourceIndex;
  final int initialEpisodeIndex;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> with WidgetsBindingObserver {
  VideoPlayerController? _controller;

  late VideoDetail _detail;

  int _currentSourceIndex = 0;
  int _currentEpisodeIndex = 0;
  VideoEpisode? _currentEpisode;

  bool _loading = true;
  String? _errorMessage;

  bool _isDragging = false;
  double _dragValue = 0;

  double _playbackSpeed = 1.0;
  bool _completionHandled = false;

  bool _controlsVisible = true;
  bool _isFullscreen = false;
  bool _disposed = false;
  bool _stallAutoRetried = false;

  // --- 新增：播放器核心新特性状态 ---
  bool _isLocked = false;
  bool _isLongPressAccelerating = false;

  int _loadToken = 0;

  Timer? _saveTimer;
  Timer? _bufferingWatchdogTimer;
  Timer? _controlsTimer;
  Timer? _uiRefreshTimer;

  VideoPlaybackProgress? _savedProgress;
  Duration _lastObservedPosition = Duration.zero;
  DateTime? _bufferingSince;
  DateTime _lastUiRefreshAt = DateTime.fromMillisecondsSinceEpoch(0);

  VideoPlaySource? get _currentSource {
    final sources = _detail.playSources;
    if (sources.isEmpty) return null;
    final index = _currentSourceIndex.clamp(0, sources.length - 1).toInt();
    return sources[index];
  }

  List<VideoEpisode> get _currentEpisodes {
    return _currentSource?.episodes ?? const [];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _detail = widget.detail;

    final sourceCount = _detail.playSources.length;
    _currentSourceIndex = sourceCount == 0 ? 0 : widget.initialSourceIndex.clamp(0, sourceCount - 1).toInt();

    final episodes = _currentEpisodes;
    _currentEpisodeIndex = episodes.isEmpty ? 0 : widget.initialEpisodeIndex.clamp(0, episodes.length - 1).toInt();
    _currentEpisode = episodes.isEmpty ? null : episodes[_currentEpisodeIndex];

    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      _savedProgress = await VideoModule.repository.getProgress(_detail.item.id);
    } catch (_) {}

    try {
      final freshDetail = await VideoModule.repository.fetchDetail(
        item: _detail.item,
        forceRefresh: true,
      );

      if (mounted) {
        _detail = freshDetail;

        final sourceCount = _detail.playSources.length;
        _currentSourceIndex = sourceCount == 0 ? 0 : _currentSourceIndex.clamp(0, sourceCount - 1).toInt();

        final episodes = _currentEpisodes;
        _currentEpisodeIndex = episodes.isEmpty ? 0 : _currentEpisodeIndex.clamp(0, episodes.length - 1).toInt();
        _currentEpisode = episodes.isEmpty ? null : episodes[_currentEpisodeIndex];
      }
    } catch (_) {}

    if (!mounted) return;

    if (_detail.playSources.isEmpty) {
      setState(() {
        _loading = false;
        _errorMessage = '当前没有可播放片源';
      });
      return;
    }

    if (_currentEpisodes.isEmpty) {
      var found = false;
      for (var i = 0; i < _detail.playSources.length; i++) {
        if (_detail.playSources[i].episodes.isNotEmpty) {
          _currentSourceIndex = i;
          _currentEpisodeIndex = 0;
          _currentEpisode = _detail.playSources[i].episodes.first;
          found = true;
          break;
        }
      }

      if (!found) {
        setState(() {
          _loading = false;
          _errorMessage = '当前没有可播放剧集';
        });
        return;
      }
    }

    await _prepareEpisode(
      _currentSourceIndex,
      _currentEpisodeIndex,
      restoreProgress: true,
      autoplay: true,
    );
  }

  VideoPlaybackProgress? _currentProgress() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;

    final value = controller.value;
    return VideoPlaybackProgress(
      videoId: _detail.item.id,
      sourceIndex: _currentSourceIndex,
      episodeIndex: _currentEpisodeIndex,
      positionSeconds: value.position.inMilliseconds / 1000.0,
      durationSeconds: value.duration.inMilliseconds / 1000.0,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _saveProgress() async {
    try {
      final progress = _currentProgress();
      if (progress == null) return;
      await VideoModule.repository.saveProgress(progress);
      _savedProgress = progress;
    } catch (_) {}
  }

  void _restartSaveTimer() {
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _saveProgress();
    });
  }

  void _restartBufferingWatchdog() {
    _bufferingWatchdogTimer?.cancel();
    _bufferingSince = null;
    _lastObservedPosition = Duration.zero;

    _bufferingWatchdogTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkBufferingWatchdog();
    });
  }

  void _checkBufferingWatchdog() {
    final controller = _controller;
    if (controller == null) return;

    final value = controller.value;

    if (!value.isInitialized || _loading || _errorMessage != null) {
      _bufferingSince = null;
      _lastObservedPosition = value.position;
      return;
    }

    if (!value.isPlaying) {
      _bufferingSince = null;
      _lastObservedPosition = value.position;
      return;
    }

    final moved = (value.position.inMilliseconds - _lastObservedPosition.inMilliseconds).abs() >= 600;

    if (value.isBuffering && !moved) {
      _bufferingSince ??= DateTime.now();

      if (DateTime.now().difference(_bufferingSince!) >= const Duration(seconds: 18)) {
        _bufferingSince = null;
        _handlePlaybackStall();
      }
    } else {
      _bufferingSince = null;
    }

    _lastObservedPosition = value.position;
  }

  Future<void> _handlePlaybackStall() async {
    if (_loading || _disposed || !mounted) return;

    if (!_stallAutoRetried) {
      _stallAutoRetried = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前线路缓冲异常，正在尝试重新连接...')),
      );
      await _prepareEpisode(
        _currentSourceIndex,
        _currentEpisodeIndex,
        restoreProgress: true,
        autoplay: true,
      );
      return;
    }

    await _showPlaybackError('缓冲超时，当前线路可能已失效，请切换其他线路或剧集');
  }

  Future<void> _disposeController() async {
    final old = _controller;
    _controller = null;

    _bufferingWatchdogTimer?.cancel();
    _bufferingWatchdogTimer = null;

    if (old == null) return;

    try {
      old.removeListener(_controllerListener);
    } catch (_) {}

    try {
      await old.pause();
    } catch (_) {}

    try {
      await old.dispose();
    } catch (_) {}
  }

  Future<void> _prepareEpisode(
    int sourceIndex,
    int episodeIndex, {
    required bool restoreProgress,
    bool autoplay = true,
  }) async {
    if (_detail.playSources.isEmpty) return;

    final token = ++_loadToken;

    final safeSourceIndex = sourceIndex.clamp(0, _detail.playSources.length - 1).toInt();
    final source = _detail.playSources[safeSourceIndex];
    if (source.episodes.isEmpty) {
      setState(() {
        _loading = false;
        _errorMessage = '当前线路没有可播放剧集';
      });
      return;
    }

    final safeEpisodeIndex = episodeIndex.clamp(0, source.episodes.length - 1).toInt();
    final episode = source.episodes[safeEpisodeIndex];

    await _disposeController();
    if (_disposed || !mounted || token != _loadToken) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
      _currentSourceIndex = safeSourceIndex;
      _currentEpisodeIndex = safeEpisodeIndex;
      _currentEpisode = episode;
      _completionHandled = false;
      _isDragging = false;
      _dragValue = 0;
      _stallAutoRetried = false;
      _controlsVisible = true;
      _isLongPressAccelerating = false; // 重置长按状态
    });

    final parsed = VideoUrlParser.parseEpisodeUrl(episode.url);
    final normalizedUrl = VideoUrlParser.normalizePlayUrl(
      parsed.url,
      _detail.sourceUrl,
      _detail.item.detailUrl,
    );

    if (normalizedUrl.isEmpty) {
      setState(() {
        _loading = false;
        _errorMessage = '播放地址为空或格式无效';
      });
      return;
    }

    final attempts = VideoUrlParser.buildRequestCandidates(
      url: normalizedUrl,
      embeddedHeaders: parsed.headers,
      sourceUrl: _detail.sourceUrl,
      detailUrl: _detail.item.detailUrl,
    );

    final failures = <String>[];
    bool isTimeout = false;

    for (final attempt in attempts) {
      if (_disposed || !mounted || token != _loadToken) return;

      final uri = Uri.tryParse(attempt.url);
      if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
        failures.add('${attempt.name}: 链接协议不受支持');
        continue;
      }

      final controller = VideoPlayerController.networkUrl(
        uri,
        httpHeaders: attempt.headers,
      );

      try {
        await controller.initialize().timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TimeoutException('连接对方服务器超时'),
        );

        if (_disposed || !mounted || token != _loadToken) {
          await controller.dispose();
          return;
        }

        await controller.setLooping(false);
        await controller.setPlaybackSpeed(_playbackSpeed);
        controller.addListener(_controllerListener);
        _controller = controller;

        if (restoreProgress) {
          await _restoreProgress(controller, safeSourceIndex, safeEpisodeIndex);
        }

        if (_disposed || !mounted || token != _loadToken) {
          controller.removeListener(_controllerListener);
          await controller.dispose();
          return;
        }

        _restartSaveTimer();
        _restartBufferingWatchdog();
        _restartControlsAutoHide();

        setState(() {
          _loading = false;
          _errorMessage = null;
        });

        if (autoplay) {
          await controller.play();
        }

        return;
      } catch (e) {
        try {
          controller.removeListener(_controllerListener);
        } catch (_) {}

        try {
          await controller.dispose();
        } catch (_) {}

        final errStr = _compactError(e);
        failures.add('${attempt.name}: $errStr');

        if (e is TimeoutException || errStr.toLowerCase().contains('timeout') || errStr.contains('超时')) {
          isTimeout = true;
          break;
        }
      }
    }

    if (_disposed || !mounted || token != _loadToken) return;

    setState(() {
      _loading = false;
      if (isTimeout) {
        _errorMessage = '片源未响应(连接超时)。\n请点击底部【片源/选集】切换线路后重试。';
      } else {
        _errorMessage = failures.isEmpty ? '当前线路暂时不可播放，请切换其他线路重试' : '当前线路不可播\n${failures.last}';
      }
    });
  }

  Future<void> _restoreProgress(
    VideoPlayerController controller,
    int sourceIndex,
    int episodeIndex,
  ) async {
    final progress = _savedProgress;
    if (progress == null) return;
    if (progress.sourceIndex != sourceIndex) return;
    if (progress.episodeIndex != episodeIndex) return;
    if (progress.positionSeconds <= 3) return;

    final duration = controller.value.duration;
    if (duration <= Duration.zero) return;

    final target = Duration(
      milliseconds: (progress.positionSeconds * 1000).round(),
    );

    final safeMax = duration - const Duration(seconds: 5);
    if (target > Duration.zero && target < safeMax) {
      try {
        await controller.seekTo(target);
      } catch (_) {}
    }
  }

  void _controllerListener() {
    final controller = _controller;
    if (controller == null || !mounted || _disposed) return;

    final value = controller.value;

    if (value.hasError) {
      final description = value.errorDescription?.trim();
      _showPlaybackError(
        description != null && description.isNotEmpty ? '播放失败：$description' : '播放中断，当前线路可能已极度卡顿或失效',
      );
      return;
    }

    if (value.isInitialized && value.duration > Duration.zero) {
      final isCompleted = value.position >= value.duration - const Duration(milliseconds: 300);
      if (isCompleted && !_completionHandled) {
        _completionHandled = true;
        Future.microtask(_onEpisodeCompleted);
      }
    }

    _scheduleUiRefresh();
  }

  void _scheduleUiRefresh() {
    if (!mounted || _disposed) return;

    final now = DateTime.now();
    if (now.difference(_lastUiRefreshAt) >= const Duration(milliseconds: 250)) {
      _lastUiRefreshAt = now;
      setState(() {});
      return;
    }

    if (_uiRefreshTimer?.isActive ?? false) return;

    _uiRefreshTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted || _disposed) return;
      _lastUiRefreshAt = DateTime.now();
      setState(() {});
    });
  }

  Future<void> _showPlaybackError(String message) async {
    if (_disposed || !mounted) return;

    try {
      await _controller?.pause();
    } catch (_) {}

    if (!mounted || _disposed) return;

    setState(() {
      _loading = false;
      _errorMessage = message;
      _controlsVisible = true;
    });
  }

  Future<void> _onEpisodeCompleted() async {
    await _saveProgress();
    if (!mounted || _disposed) return;

    final episodes = _currentEpisodes;
    if (_currentEpisodeIndex + 1 < episodes.length) {
      await _prepareEpisode(
        _currentSourceIndex,
        _currentEpisodeIndex + 1,
        restoreProgress: true,
        autoplay: true,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前线路已经播放到最后一集')),
      );
    }
  }

  Future<void> _togglePlayPause() async {
    final controller = _controller;
    if (controller == null) {
      await _retryCurrent();
      return;
    }

    if (!controller.value.isInitialized) return;

    _errorMessage = null;
    _restartControlsAutoHide();

    if (controller.value.isPlaying) {
      await controller.pause();
      await _saveProgress();
    } else {
      await controller.play();
    }

    if (mounted) setState(() {});
  }

  Future<void> _retryCurrent() async {
    await _prepareEpisode(
      _currentSourceIndex,
      _currentEpisodeIndex,
      restoreProgress: true,
      autoplay: true,
    );
  }

  Future<void> _setSpeed(double speed) async {
    _playbackSpeed = speed;
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      try {
        await controller.setPlaybackSpeed(speed);
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  Future<void> _switchEpisode(int index) async {
    if (index == _currentEpisodeIndex && _errorMessage == null) return;
    await _saveProgress();
    await _prepareEpisode(
      _currentSourceIndex,
      index,
      restoreProgress: true,
      autoplay: true,
    );
  }

  Future<void> _switchSource(int sourceIndex, {int episodeIndex = 0}) async {
    if (sourceIndex == _currentSourceIndex && episodeIndex == _currentEpisodeIndex && _errorMessage == null) {
      return;
    }

    await _saveProgress();
    await _prepareEpisode(
      sourceIndex,
      episodeIndex,
      restoreProgress: true,
      autoplay: true,
    );
  }

  void _toggleControls() {
    if (_loading || _errorMessage != null) {
      setState(() {
        _controlsVisible = true;
      });
      return;
    }

    setState(() {
      _controlsVisible = !_controlsVisible;
    });

    if (_controlsVisible) {
      _restartControlsAutoHide();
    } else {
      _controlsTimer?.cancel();
    }
  }

  // --- 新增：处理锁定逻辑 ---
  void _toggleLock() {
    setState(() {
      _isLocked = !_isLocked;
      _controlsVisible = true; // 锁定/解锁的一瞬间让控件强制呈现一下，告诉用户锁的位置
    });

    if (!_isLocked) {
      _restartControlsAutoHide();
    } else {
      _controlsTimer?.cancel();
      // 在锁定状态下，侧边的开锁按钮 3 秒后也会自动消失变成极度沉浸
      _controlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _controlsVisible = false);
      });
    }
  }

  void _restartControlsAutoHide() {
    _controlsTimer?.cancel();

    final controller = _controller;
    final isPlaying = controller?.value.isPlaying ?? false;
    if (!_controlsVisible || !isPlaying) return;

    _controlsTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || _disposed) return;
      final playing = _controller?.value.isPlaying ?? false;
      if (playing && !_loading && _errorMessage == null) {
        setState(() {
          _controlsVisible = false;
        });
      }
    });
  }

  Future<void> _toggleFullscreen() async {
    if (_isFullscreen) {
      await _exitFullscreen();
    } else {
      await _enterFullscreen();
    }
  }

  Future<void> _enterFullscreen() async {
    _isFullscreen = true;
    if (mounted) setState(() {});

    final isVerticalVideo = (_controller?.value.aspectRatio ?? 16 / 9) <= 1.0;

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    if (isVerticalVideo) {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }

    _restartControlsAutoHide();
  }

  Future<void> _exitFullscreen() async {
    _isFullscreen = false;
    _isLocked = false; // 退出全屏强制解开锁
    if (mounted) setState(() {});

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);

    _controlsVisible = true;
    if (mounted) setState(() {});
  }

  // ignore: deprecated_member_use
  Future<bool> _handleWillPop() async {
    if (_isFullscreen) {
      await _exitFullscreen();
      return false;
    }

    final progress = _currentProgress();
    if (progress != null) {
      await VideoModule.repository.saveProgress(progress);
    }
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _saveProgress();
      _controller?.pause();
    } else if (state == AppLifecycleState.resumed) {
      _restartBufferingWatchdog();
      _restartControlsAutoHide();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);

    _saveTimer?.cancel();
    _bufferingWatchdogTimer?.cancel();
    _controlsTimer?.cancel();
    _uiRefreshTimer?.cancel();

    final progress = _currentProgress();
    if (progress != null) {
      VideoModule.repository.saveProgress(progress);
    }

    final controller = _controller;
    _controller = null;

    if (controller != null) {
      try {
        controller.removeListener(_controllerListener);
      } catch (_) {}

      try {
        controller.dispose();
      } catch (_) {}
    }

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);

    super.dispose();
  }

  String _compactError(Object error) {
    final text = error.toString().trim();
    if (text.isEmpty) return '未知错误';
    return text.length > 120 ? '${text.substring(0, 120)}...' : text;
  }

  Widget _buildPlayerSurface({required bool fullscreen}) {
    final controller = _controller;
    final ready = controller?.value.isInitialized ?? false;
    final videoRatio = ready && controller!.value.aspectRatio > 0 ? controller.value.aspectRatio : 16 / 9;

    final playerWidget = Container(
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Center(
              child: AspectRatio(
                aspectRatio: videoRatio,
                child: ready ? VideoPlayer(controller!) : Container(color: Colors.black),
              ),
            ),
          ),
          
          // --- 手势识别层 ---
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (_isLocked) {
                  // 被锁定状态时，仅唤醒一次 controls 告诉用户解锁按钮在哪，然后快速隐去
                  setState(() => _controlsVisible = !_controlsVisible);
                  if (_controlsVisible) {
                    _controlsTimer?.cancel();
                    _controlsTimer = Timer(const Duration(seconds: 3), () {
                      if (mounted) setState(() => _controlsVisible = false);
                    });
                  }
                } else {
                  _toggleControls();
                }
              },
              onDoubleTap: () {
                if (_isLocked || _loading || _errorMessage != null) return;
                _togglePlayPause();
              },
              onLongPressStart: (_) async {
                if (_isLocked || _loading || _errorMessage != null) return;
                final c = _controller;
                if (c != null && c.value.isInitialized && c.value.isPlaying) {
                  setState(() {
                    _isLongPressAccelerating = true;
                    _controlsVisible = false; // 长按加速时体验更好应隐藏控制栏
                  });
                  try {
                    await c.setPlaybackSpeed(3.0); // 提供酣畅淋漓的 3 倍速
                  } catch (_) {}
                }
              },
              onLongPressEnd: (_) async {
                if (_isLongPressAccelerating) {
                  final c = _controller;
                  if (c != null && c.value.isInitialized) {
                    try {
                      await c.setPlaybackSpeed(_playbackSpeed); // 恢复初始设定的倍速
                    } catch (_) {}
                  }
                  setState(() => _isLongPressAccelerating = false);
                }
              },
              onLongPressCancel: () async {
                if (_isLongPressAccelerating) {
                  final c = _controller;
                  if (c != null && c.value.isInitialized) {
                    try {
                      await c.setPlaybackSpeed(_playbackSpeed);
                    } catch (_) {}
                  }
                  setState(() => _isLongPressAccelerating = false);
                }
              },
              child: Container(color: Colors.transparent),
            ),
          ),
          
          VideoPlayerOverlays(
            controller: controller,
            isFullscreen: fullscreen,
            controlsVisible: _controlsVisible,
            loading: _loading,
            errorMessage: _errorMessage,
            isDragging: _isDragging,
            dragValue: _dragValue,
            paddingTop: MediaQuery.of(context).padding.top,
            playbackSpeed: _playbackSpeed,
            headerTitle: _detail.item.title,
            sourceName: _currentSource?.name ?? '未知线路',
            episodeTitle: _currentEpisode?.title ?? '',
            hasPrev: _currentEpisodeIndex > 0,
            hasNext: _currentEpisodeIndex + 1 < _currentEpisodes.length,
            hasSources: _detail.playSources.isNotEmpty,
            isLocked: _isLocked,
            isLongPressAccelerating: _isLongPressAccelerating,
            onToggleLock: _toggleLock,
            onTogglePlayPause: _togglePlayPause,
            onToggleFullscreen: _toggleFullscreen,
            onExit: () async {
              if (fullscreen) {
                await _exitFullscreen();
              } else if (mounted) {
                Navigator.of(context).maybePop();
              }
            },
            onRetry: _retryCurrent,
            onPrev: () => _switchEpisode(_currentEpisodeIndex - 1),
            onNext: () => _switchEpisode(_currentEpisodeIndex + 1),
            onOpenEpisodeSheet: _openEpisodeSheet,
            onOpenQualitySheet: _openQualitySheet,
            onSeekStart: (_) {
              setState(() {
                _isDragging = true;
                _completionHandled = false;
                _controlsVisible = true;
              });
            },
            onSeekUpdate: (value) {
              setState(() {
                _dragValue = value;
              });
            },
            onSeekEnd: (value) async {
              final c = _controller;
              if (c == null || !c.value.isInitialized) return;

              final wasPlaying = c.value.isPlaying;
              final target = Duration(milliseconds: value.round());

              try {
                await c.seekTo(target);
                if (wasPlaying) {
                  await c.play();
                }
              } catch (_) {}

              if (!mounted) return;
              setState(() {
                _isDragging = false;
              });

              _restartControlsAutoHide();
              await _saveProgress();
            },
            onSpeedChange: _setSpeed,
          ),
        ],
      ),
    );

    if (fullscreen) return playerWidget;

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: playerWidget,
    );
  }

  Widget _buildNormalPage() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: Colors.black,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.55,
              ),
              child: Center(
                child: _buildPlayerSurface(fullscreen: false),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                physics: const BouncingScrollPhysics(),
                children: [
                  VideoPlayerDetailsView(
                    detail: _detail,
                    currentSourceIndex: _currentSourceIndex,
                    currentEpisodeIndex: _currentEpisodeIndex,
                    savedProgress: _savedProgress,
                    onSwitchSource: _switchSource,
                    onSwitchEpisode: _switchEpisode,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullscreenPage() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildPlayerSurface(fullscreen: true),
    );
  }

  @override
  // ignore: deprecated_member_use
  Widget build(BuildContext context) {
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: _handleWillPop,
      child: _isFullscreen ? _buildFullscreenPage() : _buildNormalPage(),
    );
  }

  // --- 高颜值独立清晰度/线路选择弹窗 ---
  void _openQualitySheet() {
    final sources = _detail.playSources;
    if (sources.isEmpty) return;
    
    final isDark = _isFullscreen;
    final textColor = isDark ? Colors.white : Colors.black87;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.6,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text('清晰度 / 线路选择', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    itemCount: sources.length,
                    itemBuilder: (context, index) {
                      final isCurrent = index == _currentSourceIndex;
                      return ListTile(
                        title: Center(
                          child: Text(
                            sources[index].name,
                            style: TextStyle(
                              color: isCurrent ? Colors.blueAccent : (isDark ? Colors.white70 : Colors.black87),
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _switchSource(index, episodeIndex: _currentEpisodeIndex);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- 高颜值独立选集弹窗排版优化 (Grid 宫格适配全屏视觉) ---
  void _openEpisodeSheet() {
    final isDark = _isFullscreen;
    final textColor = isDark ? Colors.white : Colors.black87;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bgColor,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final episodes = _currentEpisodes;
        return FractionallySizedBox(
          heightFactor: 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('选集', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                    IconButton(icon: Icon(Icons.close, color: textColor), onPressed: () => Navigator.pop(context)),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 120, // 调整宫格宽度容纳长文字集数
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.2,
                  ),
                  itemCount: episodes.length,
                  itemBuilder: (context, index) {
                    final isCurrent = index == _currentEpisodeIndex;
                    return InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        _switchEpisode(index);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: isCurrent 
                            ? Colors.blueAccent.withOpacity(0.2) 
                            : (isDark ? Colors.white.withOpacity(0.12) : const Color(0xFFF2F4F7)),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isCurrent ? Colors.blueAccent : Colors.transparent),
                        ),
                        child: Text(
                          episodes[index].title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: isCurrent ? Colors.blueAccent : textColor,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
