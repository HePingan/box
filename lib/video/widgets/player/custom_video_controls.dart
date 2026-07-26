import 'dart:async';
import 'dart:ui';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../design_system/app_tokens.dart';

/// Serializes seek commands while coalescing requests made in the same UI turn.
///
/// A scrub records whether playback was active before it started, so only a
/// scrub that began during playback resumes it after its final seek completes.
class LatestSeekCommandQueue {
  LatestSeekCommandQueue({
    required FutureOr<void> Function(Duration target) seekTo,
    required FutureOr<void> Function() resume,
  }) : _seekTo = seekTo,
       _resume = resume;

  final FutureOr<void> Function(Duration target) _seekTo;
  final FutureOr<void> Function() _resume;
  Duration? _pendingTarget;
  bool _pendingResume = false;
  bool _scheduled = false;
  bool _running = false;
  final List<Completer<void>> _waiters = [];

  Future<void> submit(Duration target, {required bool resumePlayback}) {
    _pendingTarget = target;
    _pendingResume = resumePlayback;
    final completer = Completer<void>();
    _waiters.add(completer);
    if (!_scheduled && !_running) {
      _scheduled = true;
      scheduleMicrotask(_drain);
    }
    return completer.future;
  }

  Future<void> _drain() async {
    _scheduled = false;
    _running = true;
    final target = _pendingTarget;
    final resumePlayback = _pendingResume;
    _pendingTarget = null;
    _pendingResume = false;
    final waiters = List<Completer<void>>.from(_waiters);
    _waiters.clear();

    try {
      if (target != null) {
        await _seekTo(target);
        if (resumePlayback && _pendingTarget == null) await _resume();
      }
      for (final waiter in waiters) {
        waiter.complete();
      }
    } catch (error, stackTrace) {
      for (final waiter in waiters) {
        waiter.completeError(error, stackTrace);
      }
    } finally {
      _running = false;
      if (_pendingTarget != null && !_scheduled) {
        _scheduled = true;
        scheduleMicrotask(_drain);
      }
    }
  }
}

/// Playback speed options offered by the speed menu (B6).
const List<double> kPlaybackSpeeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

class CustomVideoControls extends StatefulWidget {
  final String title;
  final String episodeName;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onToggleFullScreen;

  const CustomVideoControls({
    super.key,
    required this.title,
    required this.episodeName,
    this.onPrevious,
    this.onNext,
    this.onToggleFullScreen,
  });

  @override
  State<CustomVideoControls> createState() => _CustomVideoControlsState();
}

class _CustomVideoControlsState extends State<CustomVideoControls> {
  ChewieController? _chewieController;
  VideoPlayerController? _videoController;

  bool _bound = false;
  // 控件默认按需出现：自动播放开始时不遮挡首帧；暂停、拖动和显式点击才展示。
  bool _showControls = false;
  bool _isLocked = false;

  // 手势与防抖
  bool _isReallyScrubbing = false;
  bool _isScrubbing = false;
  bool _wasPlayingBeforeScrub = false;
  LatestSeekCommandQueue? _seekQueue;

  int _lastTapTime = 0;
  Timer? _singleTapTimer;
  bool _showControlsBeforeTap = true;

  // 双击快进/快退提示
  String? _doubleTapSeekHint;
  Timer? _doubleTapHintTimer;

  // 记录上一次播放状态，防止自动触发导致的 UI 闪烁
  bool? _lastKnownPlayingState;

  // A1: 记录上次渲染的秒数，仅在整秒变化时刷新时间/进度，避免逐帧 setState。
  int _lastRenderedSecond = -1;

  Timer? _hideTimer;

  bool _isLongPressSpeeding = false;
  final double _longPressSpeed = 2.0;

  Duration _scrubCurrentPosition = Duration.zero;

  // B6: 常驻倍速。长按结束后恢复到用户选择的倍速，而非写死 1.0。
  double _currentSpeed = 1.0;
  bool _speedMenuOpen = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bound) return;

    final chewie = ChewieController.of(context);

    _chewieController = chewie;
    _videoController = chewie.videoPlayerController;
    _seekQueue = LatestSeekCommandQueue(
      seekTo: _videoController!.seekTo,
      resume: _videoController!.play,
    );
    _bound = true;

    _videoController!.addListener(_onVideoTick);
    _lastKnownPlayingState = _videoController!.value.isPlaying;

    // `autoPlay` 的起播前一帧通常仍是 paused；不在这里展示控件，
    // 否则会短暂遮住首帧。真正暂停由 _onVideoTick 的状态迁移处理。
    if (_videoController!.value.isPlaying) {
      _startHideTimer();
    }
  }

  @override
  void dispose() {
    _videoController?.removeListener(_onVideoTick);
    _hideTimer?.cancel();
    _singleTapTimer?.cancel();
    _doubleTapHintTimer?.cancel();
    super.dispose();
  }

  bool get _isFullScreen => _chewieController?.isFullScreen ?? false;

  // 🚀 核心优化：监控播放器状态变化
  void _onVideoTick() {
    if (!mounted || _videoController == null) return;

    final value = _videoController!.value;
    final isPlaying = value.isPlaying;

    // 只有状态从【播放->暂停】或【暂停->播放】发生真实切换时才触发
    if (isPlaying != _lastKnownPlayingState) {
      _lastKnownPlayingState = isPlaying;

      setState(() {
        if (!isPlaying) {
          // 视频暂停了：立刻显示控制栏，并取消自动隐藏计时器
          _showControls = true;
          _hideTimer?.cancel();
        } else {
          // 视频开始播放了：如果当前控制栏开着，开启自动隐藏倒计时
          if (_showControls && !_isLocked) {
            _startHideTimer();
          }
        }
      });
    }

    // A1: 播放中时间/进度实时刷新。底栏时间文本读的是 controller.value.position，
    // 若不主动 setState 就会“冻住”。按整秒节流，控制栏可见时才重建。
    if (!_isScrubbing) {
      final second = value.position.inSeconds;
      if (second != _lastRenderedSecond) {
        _lastRenderedSecond = second;
        if (_showControls && !_isLocked) setState(() {});
      }
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 3000), () {
      // 只有在视频正在播放且没锁定时，才隐去控制栏
      if (mounted &&
          _videoController?.value.isPlaying == true &&
          !_isLocked &&
          !_isScrubbing &&
          !_speedMenuOpen) {
        setState(() => _showControls = false);
      }
    });
  }

  // 单击即时响应，双击到来时回滚。彻底拦截任何点击穿透。
  void _handleTap(TapUpDetails details) {
    if (_speedMenuOpen) {
      setState(() => _speedMenuOpen = false);
      return;
    }
    if (_isLocked) {
      // 锁屏态下点击只闪一下锁按钮，交给 _buildAnimatedLock 的透明度控制
      setState(() {});
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final delta = now - _lastTapTime;
    _lastTapTime = now;

    if (delta < 300) {
      // 【双击】：先取消挂起的单击、回滚它对控制栏做的切换，再按区域执行
      _singleTapTimer?.cancel();
      _singleTapTimer = null;
      _showControls = _showControlsBeforeTap;

      final width = MediaQuery.sizeOf(context).width;
      final dx = details.localPosition.dx;
      if (dx < width * 0.35) {
        _seekBy(const Duration(seconds: -10));
      } else if (dx > width * 0.65) {
        _seekBy(const Duration(seconds: 10));
      } else {
        _togglePlayPause();
      }
      return;
    }

    // 【单击】：立即切换控制栏（不等待 300ms），记录切换前状态以便双击回滚
    _showControlsBeforeTap = _showControls;
    setState(() {
      _showControls = !_showControls;
      if (_showControls) {
        if (_videoController?.value.isPlaying == true) {
          _startHideTimer();
        } else {
          _hideTimer?.cancel();
        }
      } else {
        _hideTimer?.cancel();
      }
    });
  }

  // 双击快进/快退：相对当前位置 seek，带边界保护和提示
  void _seekBy(Duration offset) {
    final controller = _videoController;
    if (controller == null) return;

    final duration = controller.value.duration;
    var target = controller.value.position + offset;
    if (target < Duration.zero) {
      target = Duration.zero;
    } else if (duration > Duration.zero && target > duration) {
      target = duration;
    }

    _seekQueue?.submit(target, resumePlayback: controller.value.isPlaying);

    final label = offset.isNegative ? '快退 10 秒' : '快进 10 秒';
    setState(() => _doubleTapSeekHint = label);
    _doubleTapHintTimer?.cancel();
    _doubleTapHintTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _doubleTapSeekHint = null);
    });
  }

  void _togglePlayPause() {
    if (_videoController == null || _isLocked) return;
    if (_videoController!.value.isPlaying) {
      _videoController!.pause();
    } else {
      _videoController!.play();
    }
  }

  void _toggleLock() {
    setState(() {
      _isLocked = !_isLocked;
      _showControls = true;
      _speedMenuOpen = false;
      if (!_isLocked && _videoController?.value.isPlaying == true) {
        _startHideTimer();
      } else {
        _hideTimer?.cancel();
      }
    });
  }

  // B6: 应用倍速并关闭菜单。
  void _applySpeed(double speed) {
    _currentSpeed = speed;
    _videoController?.setPlaybackSpeed(speed);
    setState(() => _speedMenuOpen = false);
    if (_videoController?.value.isPlaying == true) _startHideTimer();
  }

  // A4: 顶栏左键。全屏态下退出全屏，非全屏态下返回上一页。
  void _handleTopLeading() {
    if (_isFullScreen) {
      (widget.onToggleFullScreen ?? _chewieController!.toggleFullScreen)();
    } else {
      Navigator.maybePop(context);
    }
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return d.inHours > 0
        ? '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}'
        : '${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }

  // ============== 手势逻辑 ==============

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_videoController == null || _isLocked) return;

    if (!_isReallyScrubbing) {
      _beginScrub();
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final dragSeconds = (details.delta.dx / screenWidth * 180).toInt();

    var newPos = _scrubCurrentPosition + Duration(seconds: dragSeconds);

    final totalDuration = _videoController!.value.duration;
    if (newPos < Duration.zero) {
      newPos = Duration.zero;
    } else if (newPos > totalDuration) {
      newPos = totalDuration;
    }

    if (newPos != _scrubCurrentPosition) {
      setState(() => _scrubCurrentPosition = newPos);
    }
  }

  // A2: 进度条与横拖共用同一套 scrub 状态与 _seekQueue，行为统一、防抖一致。
  void _beginScrub() {
    final controller = _videoController;
    if (controller == null) return;
    if (!_isReallyScrubbing) {
      _isReallyScrubbing = true;
      _wasPlayingBeforeScrub = controller.value.isPlaying;
      if (_wasPlayingBeforeScrub) controller.pause();
    }
    setState(() {
      _isScrubbing = true;
      _showControls = true;
    });
    _hideTimer?.cancel();
  }

  Future<void> _endScrub() async {
    final seekQueue = _seekQueue;
    final shouldResume = _wasPlayingBeforeScrub;
    if (_isReallyScrubbing && seekQueue != null) {
      await seekQueue.submit(
        _scrubCurrentPosition,
        resumePlayback: shouldResume,
      );
    }
    if (!mounted) return;
    setState(() {
      _isScrubbing = false;
      _isReallyScrubbing = false;
    });
    if (_videoController?.value.isPlaying == true) {
      _startHideTimer();
    }
  }

  // ============== UI 构建 ==============

  @override
  Widget build(BuildContext context) {
    if (_videoController == null) return const SizedBox.shrink();

    // B3：按播放器实际高度自适应控件密度。小窗（非全屏内嵌，16:9 约 200px）
    // 走紧凑档：顶栏隐藏集名副标题、底栏按钮缩小，避免上下控件堆叠。
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = !_isFullScreen && constraints.maxHeight < 320;
        return _buildControlsStack(compact);
      },
    );
  }

  Widget _buildControlsStack(bool compact) {
    return SizedBox.expand(
      child: Stack(
        children: [
          // 🚀 核心透明拦截层：强制使用 HitTestBehavior.opaque 拦截所有底层穿透
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: _handleTap,
              onLongPressStart: _isLocked
                  ? null
                  : (d) {
                      _wasPlayingBeforeScrub =
                          _videoController!.value.isPlaying;
                      _videoController!.setPlaybackSpeed(_longPressSpeed);
                      setState(() => _isLongPressSpeeding = true);
                    },
              onLongPressEnd: _isLocked
                  ? null
                  : (d) {
                      // B6: 长按结束恢复到当前选定倍速，而非写死 1.0。
                      _videoController!.setPlaybackSpeed(_currentSpeed);
                      if (!_wasPlayingBeforeScrub) _videoController!.pause();
                      setState(() => _isLongPressSpeeding = false);
                    },
              onHorizontalDragStart: _isLocked
                  ? null
                  : (d) {
                      _scrubCurrentPosition = _videoController!.value.position;
                      _isReallyScrubbing = false;
                    },
              onHorizontalDragUpdate: _isLocked
                  ? null
                  : _onHorizontalDragUpdate,
              onHorizontalDragEnd: _isLocked ? null : (d) => _endScrub(),
            ),
          ),

          // 内嵌播放器已有页面头部导航与标题；只在全屏保留播放器顶栏，
          // 避免同一标题/返回在一屏内出现两次并挤占画面。
          if (_isFullScreen)
            _buildAnimatedBar(
              alignment: Alignment.topCenter,
              visible: _showControls && !_isLocked,
              child: _buildTopBar(compact),
            ),

          // 底部
          _buildAnimatedBar(
            alignment: Alignment.bottomCenter,
            visible: _showControls && !_isLocked,
            child: _buildBottomBar(compact),
          ),

          // B6: 倍速选择面板
          if (_speedMenuOpen && !_isLocked) _buildSpeedMenu(),

          // 锁按钮
          _buildAnimatedLock(),

          // A3: 中心大播放按钮仅在【暂停且控制栏隐藏】时出现，避免与底栏播放键重复
          if (!_isLocked &&
              !_videoController!.value.isPlaying &&
              !_showControls)
            Center(child: _buildLargePlayButton()),

          // Overlay 提示层
          if (_isScrubbing) _buildScrubOverlay(),
          if (_isLongPressSpeeding) _buildSpeedHint(),
          if (_doubleTapSeekHint != null) _buildDoubleTapSeekHint(),
        ],
      ),
    );
  }

  Widget _buildAnimatedBar({
    required Alignment alignment,
    required bool visible,
    required Widget child,
  }) {
    return Positioned(
      left: 0,
      right: 0,
      top: alignment == Alignment.topCenter ? 0 : null,
      bottom: alignment == Alignment.bottomCenter ? 0 : null,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
        child: visible ? child : const SizedBox.shrink(),
      ),
    );
  }

  // A5: 非全屏内嵌在滚动列表里，持续的 BackdropFilter 合成有开销；
  // 只有全屏才开真模糊，非全屏用高透明度实色底，观感接近、성能更稳。
  Widget _glassSurface({
    required BorderRadius radius,
    required EdgeInsetsGeometry margin,
    required EdgeInsetsGeometry padding,
    required double alpha,
    required Widget child,
  }) {
    final decorated = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(
          0xFF080A1F,
        ).withValues(alpha: _isFullScreen ? alpha : 0.9),
        borderRadius: radius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: child,
    );

    if (!_isFullScreen) return decorated;

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: decorated,
      ),
    );
  }

  Widget _buildTopBar(bool compact) {
    // B1/A1：全屏顶栏视觉降噪——移除副标题、缩小返回键，改用渐变遮罩替代实色面板，
    // 减少遮挡画面积的同时提升文字可读性。
    final gradient = _isFullScreen
        ? BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF080A1F).withValues(alpha: 0.75),
                Colors.transparent,
              ],
            ),
          )
        : BoxDecoration(color: const Color(0xFF080A1F).withValues(alpha: 0.66));
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      decoration: gradient,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            _glassButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: _handleTopLeading,
              compact: true,
              size: 30,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(bool compact) {
    final value = _videoController!.value;
    final position = _isScrubbing ? _scrubCurrentPosition : value.position;
    final embedded = !_isFullScreen;
    // A2：底栏进一步压缩——全屏态减少内边距、缩小按钮间距，让进度条更接近画面边缘。
    final isFull = _isFullScreen;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        embedded ? 6 : (isFull ? 8 : 10),
        isFull ? 6 : 0,
        embedded ? 6 : (isFull ? 8 : 10),
        embedded ? 4 : (isFull ? 6 : 10),
      ),
      child: _glassSurface(
        radius: BorderRadius.circular(embedded ? 14 : (isFull ? 20 : 26)),
        margin: EdgeInsets.zero,
        padding: EdgeInsets.fromLTRB(
          embedded ? 8 : (isFull ? 10 : 12),
          embedded ? 2 : (isFull ? 4 : 10),
          embedded ? 8 : (isFull ? 10 : 12),
          embedded ? 3 : (isFull ? 4 : 10),
        ),
        alpha: embedded ? 0.62 : 0.72,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _timeLabel(_formatDuration(position), embedded),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: embedded ? 7 : (isFull ? 8 : 10),
                      ),
                      child: _buildSeekBar(compact: embedded),
                    ),
                  ),
                  _timeLabel(_formatDuration(value.duration), embedded),
                ],
              ),
              SizedBox(height: embedded ? 1 : (isFull ? 2 : (compact ? 4 : 8))),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _glassButton(
                    icon: Icons.skip_previous_rounded,
                    onTap: widget.onPrevious,
                    compact: embedded || compact,
                  ),
                  _glassButton(
                    icon: value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    onTap: _togglePlayPause,
                    emphasized: true,
                    compact: embedded || compact,
                    isPlaying: value.isPlaying,
                  ),
                  _glassButton(
                    icon: Icons.skip_next_rounded,
                    onTap: widget.onNext,
                    compact: embedded || compact,
                  ),
                  if (!compact && !embedded) _buildSpeedButton(compact),
                  _glassButton(
                    icon: _isFullScreen
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    onTap:
                        widget.onToggleFullScreen ??
                        () => _chewieController!.toggleFullScreen(),
                    compact: embedded || compact,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 内嵌状态使用无背景时间文字，不让两枚胶囊遮挡视频画面。
  Widget _timeLabel(String text, bool embedded) {
    if (!embedded) return _timeChip(text);
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }

  // A1: 自绘进度条，拖动/点击都走 _seekQueue，与横拖共享防抖与续播语义。
  Widget _buildSeekBar({bool compact = false}) {
    final value = _videoController!.value;
    final duration = value.duration;
    final durMs = duration.inMilliseconds;
    final position = _isScrubbing ? _scrubCurrentPosition : value.position;
    final playedFraction = durMs > 0
        ? (position.inMilliseconds / durMs).clamp(0.0, 1.0)
        : 0.0;
    var bufferedFraction = 0.0;
    if (durMs > 0 && value.buffered.isNotEmpty) {
      bufferedFraction = (value.buffered.last.end.inMilliseconds / durMs).clamp(
        0.0,
        1.0,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void seekToDx(double dx) {
          if (durMs <= 0) return;
          final frac = (dx / width).clamp(0.0, 1.0);
          setState(() {
            _scrubCurrentPosition = Duration(
              milliseconds: (durMs * frac).round(),
            );
          });
        }

        const thumb = 10.0;
        final trackHeight = compact ? 3.0 : 4.0;
        final touchHeight = compact ? 16.0 : 24.0;
        final playedWidth = (width * playedFraction).clamp(0.0, width);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) {
            _beginScrub();
            seekToDx(d.localPosition.dx);
          },
          onHorizontalDragUpdate: (d) => seekToDx(d.localPosition.dx),
          onHorizontalDragEnd: (d) => _endScrub(),
          onTapDown: (d) {
            _beginScrub();
            seekToDx(d.localPosition.dx);
          },
          onTapUp: (d) => _endScrub(),
          child: SizedBox(
            height: touchHeight,
            width: width,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // 轨道底
                Container(
                  height: trackHeight,
                  decoration: BoxDecoration(
                    color: const Color(0x33FFFFFF),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // 已缓冲
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: bufferedFraction,
                  child: Container(
                    height: trackHeight,
                    decoration: BoxDecoration(
                      color: const Color(0x66FFFFFF),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // 已播放
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: playedFraction,
                  child: Container(
                    height: trackHeight,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE08A),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // 拖动圆点
                Positioned(
                  left: (playedWidth - thumb / 2).clamp(0.0, width - thumb),
                  child: Container(
                    width: thumb,
                    height: thumb,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE08A),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSpeedButton(bool compact) {
    final label = _currentSpeed == _currentSpeed.roundToDouble()
        ? '${_currentSpeed.toStringAsFixed(0)}x'
        : '${_currentSpeed}x';
    // B3/A2：小窗紧凑档同步缩小倍速键，与其它底栏按钮尺寸一致。
    final double r = compact ? 14 : 18;
    return Opacity(
      opacity: 1,
      child: Material(
        color: _speedMenuOpen
            ? const Color(0xFFFFE08A)
            : Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(r),
        child: InkWell(
          borderRadius: BorderRadius.circular(r),
          onTap: () {
            setState(() => _speedMenuOpen = !_speedMenuOpen);
            _hideTimer?.cancel();
          },
          child: SizedBox(
            width: 44,
            height: 38,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: _speedMenuOpen ? AppTokens.inkDark : Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpeedMenu() {
    return Positioned(
      right: 16,
      bottom: 92,
      child: SafeArea(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF080A1F).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final speed in kPlaybackSpeeds.reversed)
                  _buildSpeedItem(speed),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpeedItem(double speed) {
    final selected = speed == _currentSpeed;
    final label = speed == speed.roundToDouble()
        ? '${speed.toStringAsFixed(1)}x'
        : '${speed}x';
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _applySpeed(speed),
      child: Container(
        width: 96,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFFFE08A).withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: selected
                  ? const Icon(
                      Icons.check_rounded,
                      color: Color(0xFFFFE08A),
                      size: 16,
                    )
                  : null,
            ),
            const SizedBox(width: 6),
            Text(
              speed == 1.0 ? '正常' : label,
              style: TextStyle(
                color: selected ? const Color(0xFFFFE08A) : Colors.white,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLargePlayButton() {
    final playing = _videoController!.value.isPlaying;
    return GestureDetector(
      onTap: _togglePlayPause,
      child: Container(
        width: 66,
        height: 66,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFE08A).withValues(alpha: 0.28),
              blurRadius: 26,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(
          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: Colors.white,
          size: 40,
        ),
      ),
    );
  }

  Widget _glassButton({
    required IconData icon,
    required VoidCallback? onTap,
    bool emphasized = false,
    bool compact = false,
    double? size,
    bool isPlaying = false,
  }) {
    final enabled = onTap != null;
    // A2：播放/暂停按钮视觉增强——播放态白色半透明圆底+播放三角，
    // 暂停态保持黄色焦点。compact 模式统一缩小尺寸。
    Color? bgColor;
    if (emphasized) {
      bgColor = isPlaying
          ? Colors.white.withValues(alpha: 0.18)
          : const Color(0xFFFFE08A);
    } else {
      bgColor = Colors.white.withValues(alpha: 0.14);
    }
    final double w =
        size ?? (emphasized ? (compact ? 38 : 52) : (compact ? 32 : 40));
    final double h =
        size ?? (emphasized ? (compact ? 38 : 44) : (compact ? 32 : 38));
    final double iconSize = size != null
        ? size * 0.6
        : (emphasized ? (compact ? 22 : 30) : (compact ? 18 : 22));
    final double r = emphasized && compact ? 999 : (compact ? 12 : 18);
    return Opacity(
      opacity: enabled ? 1 : 0.38,
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(r),
        child: InkWell(
          borderRadius: BorderRadius.circular(r),
          onTap: onTap,
          child: SizedBox(
            width: w,
            height: h,
            child: Icon(
              icon,
              color: emphasized && !isPlaying
                  ? AppTokens.inkDark
                  : Colors.white,
              size: iconSize,
            ),
          ),
        ),
      ),
    );
  }

  Widget _timeChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  Widget _buildAnimatedLock() {
    // 控件显示时不再叠加独立锁图标；自动淡出后才提供轻量锁定入口。
    final visible = !_showControls || _isLocked;
    return Positioned(
      left: 12,
      top: 0,
      bottom: 0,
      child: Center(
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: Material(
              color: const Color(0xFF080A1F).withValues(alpha: 0.48),
              shape: const CircleBorder(),
              child: IconButton(
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  _isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                  color: Colors.white.withValues(alpha: 0.9),
                  size: 20,
                ),
                onPressed: _toggleLock,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScrubOverlay() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${_formatDuration(_scrubCurrentPosition)} / ${_formatDuration(_videoController!.value.duration)}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  Widget _buildSpeedHint() {
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF080A1F).withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFFFE08A).withValues(alpha: 0.5),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.fast_forward_rounded,
                color: Color(0xFFFFE08A),
                size: 18,
              ),
              SizedBox(width: 6),
              Text(
                '2.0x 倍速播放中',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDoubleTapSeekHint() {
    final hint = _doubleTapSeekHint;
    if (hint == null) return const SizedBox.shrink();
    final isRewind = hint.startsWith('快退');
    return Align(
      alignment: isRewind ? Alignment.centerLeft : Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF080A1F).withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFFFE08A).withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isRewind
                    ? Icons.fast_rewind_rounded
                    : Icons.fast_forward_rounded,
                color: const Color(0xFFFFE08A),
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                hint,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
