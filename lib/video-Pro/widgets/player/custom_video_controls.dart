import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class CustomVideoControls extends StatefulWidget {
  final String title;
  final String episodeName;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  /// 由父组件接管全屏切换，避免切全屏时触发误暂停
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

  bool _showControls = true;
  bool _isLocked = false;
  bool _showLockOnly = false;

  bool _isScrubbing = false;
  bool _wasPlayingBeforeScrub = false;

  bool _wasPlayingLastTick = false;
  bool _wasBufferingLastTick = false;

  Timer? _hideTimer;

  bool _isLongPressSpeeding = false;
  bool _wasPlayingBeforeLongPress = false;
  double _speedBeforeLongPress = 1.0;
  final double _longPressSpeed = 2.0;

  Duration _scrubBasePosition = Duration.zero;
  Duration _scrubCurrentPosition = Duration.zero;

  double _playbackSpeed = 1.0;

  bool get _isPlaying => _videoController?.value.isPlaying == true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_bound) return;

    final chewie = ChewieController.of(context);
    if (chewie == null) return;

    _chewieController = chewie;
    _videoController = chewie.videoPlayerController;
    _bound = true;

    _videoController!.addListener(_onVideoTick);

    final value = _videoController!.value;
    _wasPlayingLastTick = value.isPlaying;
    _wasBufferingLastTick = value.isBuffering;

    if (value.isPlaying) {
      _startHideTimer();
    } else {
      _showControls = true;
    }
  }

  @override
  void dispose() {
    if (_bound && _videoController != null) {
      _videoController!.removeListener(_onVideoTick);
    }
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onVideoTick() {
    final controller = _videoController;
    if (controller == null) return;

    final value = controller.value;
    final isPlaying = value.isPlaying;
    final isBuffering = value.isBuffering;

    if (isPlaying == _wasPlayingLastTick &&
        isBuffering == _wasBufferingLastTick) {
      return;
    }

    _wasPlayingLastTick = isPlaying;
    _wasBufferingLastTick = isBuffering;

    if (!mounted) return;

    setState(() {
      if (isPlaying) {
        if (isBuffering) {
          if (!_isLocked) {
            _showControls = true;
          }
          _hideTimer?.cancel();
        } else {
          if (!_isLocked && !_isScrubbing && !_isLongPressSpeeding) {
            _startHideTimer();
          }
        }
      } else {
        if (!_isLocked) {
          _showControls = true;
        }
        _hideTimer?.cancel();
      }
    });
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;

      final controller = _videoController;
      if (controller == null) return;

      if (controller.value.isPlaying &&
          !_isLocked &&
          !_isScrubbing &&
          !_isLongPressSpeeding) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  /// 双击：播放 / 暂停
  void _togglePlayPause() {
    final controller = _videoController;
    if (controller == null || _isLocked) return;

    if (controller.value.isPlaying) {
      controller.pause();
      setState(() {
        _showControls = true;
      });
      _hideTimer?.cancel();
    } else {
      controller.play();
      setState(() {
        _showControls = true;
      });
      _startHideTimer();
    }
  }

  /// 单击：只显示/隐藏控制层，不做播放暂停
  void _toggleControls() {
    final controller = _videoController;
    if (controller == null) return;

    if (_isLocked) {
      setState(() {
        _showLockOnly = !_showLockOnly;
      });
      return;
    }

    if (!controller.value.isPlaying) {
      setState(() {
        _showControls = true;
      });
      return;
    }

    setState(() {
      _showControls = !_showControls;
    });

    if (_showControls) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _toggleLock() {
    setState(() {
      if (_isLocked) {
        _isLocked = false;
        _showLockOnly = false;
        _showControls = true;
        _isScrubbing = false;
        _isLongPressSpeeding = false;

        if (_isPlaying) {
          _startHideTimer();
        }
      } else {
        _isLocked = true;
        _showLockOnly = true;
        _showControls = false;
        _isScrubbing = false;
        _isLongPressSpeeding = false;
        _hideTimer?.cancel();
      }
    });
  }

  void _handleBack() {
    final chewie = _chewieController;
    if (chewie != null && chewie.isFullScreen) {
      chewie.exitFullScreen();
      return;
    }

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).maybePop();
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');

    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  String _formatSpeed(double speed) {
    final isInteger = speed.truncateToDouble() == speed;
    return isInteger ? speed.toStringAsFixed(0) : speed.toStringAsFixed(2);
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    final controller = _videoController;
    if (controller == null || _isLocked) return;

    _scrubBasePosition = controller.value.position;
    _scrubCurrentPosition = _scrubBasePosition;
    _wasPlayingBeforeScrub = controller.value.isPlaying;

    if (controller.value.isPlaying) {
      controller.pause();
    }

    setState(() {
      _isScrubbing = true;
      _showControls = true;
    });

    _hideTimer?.cancel();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final controller = _videoController;
    if (controller == null || _isLocked || !_isScrubbing) return;

    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth <= 0) return;

    final dragRatio = details.delta.dx / screenWidth;
    final dragSeconds = (dragRatio * 300).toInt();

    var newPosition = _scrubCurrentPosition + Duration(seconds: dragSeconds);
    final duration = controller.value.duration;

    if (newPosition < Duration.zero) {
      newPosition = Duration.zero;
    }
    if (newPosition > duration) {
      newPosition = duration;
    }

    setState(() {
      _scrubCurrentPosition = newPosition;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final controller = _videoController;
    if (controller == null || _isLocked || !_isScrubbing) return;

    controller.seekTo(_scrubCurrentPosition);

    setState(() {
      _isScrubbing = false;
      _showControls = true;
    });

    if (_wasPlayingBeforeScrub) {
      controller.play();
      _startHideTimer();
    }
  }

  void _onHorizontalDragCancel() {
    final controller = _videoController;
    if (controller == null || _isLocked || !_isScrubbing) return;

    setState(() {
      _isScrubbing = false;
      _showControls = true;
    });

    if (_wasPlayingBeforeScrub) {
      controller.play();
      _startHideTimer();
    }
  }

  void _startLongPressSpeed(LongPressStartDetails details) {
    final controller = _videoController;
    if (controller == null || _isLocked || _isScrubbing) return;

    _speedBeforeLongPress = _playbackSpeed;
    _wasPlayingBeforeLongPress = controller.value.isPlaying;

    if (!controller.value.isPlaying) {
      controller.play();
    }

    controller.setPlaybackSpeed(_longPressSpeed);

    setState(() {
      _isLongPressSpeeding = true;
      _showControls = false;
    });

    _hideTimer?.cancel();
  }

  void _endLongPressSpeed() {
    final controller = _videoController;
    if (controller != null) {
      controller.setPlaybackSpeed(_speedBeforeLongPress);

      if (!_wasPlayingBeforeLongPress) {
        controller.pause();
      }
    }

    if (!mounted) return;

    setState(() {
      _isLongPressSpeeding = false;
    });

    if (_isPlaying && !_isLocked && !_isScrubbing) {
      _startHideTimer();
    }
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    _endLongPressSpeed();
  }

  void _onLongPressCancel() {
    _endLongPressSpeed();
  }

  Future<void> _setSpeed(double speed) async {
    final controller = _videoController;
    if (controller == null) return;

    await controller.setPlaybackSpeed(speed);

    setState(() {
      _playbackSpeed = speed;
    });

    if (_isPlaying &&
        !_isLocked &&
        !_isScrubbing &&
        !_isLongPressSpeeding) {
      _startHideTimer();
    }
  }

  Future<void> _showSpeedSheet() async {
    final speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    '播放速度',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final speed in speeds)
                      ChoiceChip(
                        label: Text('${_formatSpeed(speed)}x'),
                        selected: _playbackSpeed == speed,
                        onSelected: (_) async {
                          Navigator.pop(sheetContext);
                          await _setSpeed(speed);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _bottomStateText() {
    final controller = _videoController;
    if (controller == null) return '';

    final state = controller.value.isPlaying ? '播放中' : '已暂停';
    final buffering = controller.value.isBuffering ? '缓冲中' : '正常';
    return '$state · $buffering · ${_formatSpeed(_playbackSpeed)}x';
  }

  Widget _buildLockOnlyButton() {
    return Positioned(
      left: 0,
      top: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(left: 4, top: 4),
          child: Material(
            color: Colors.black.withOpacity(0.55),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: _isLocked ? '解锁' : '锁定',
              icon: Icon(
                _isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                color: Colors.white,
                size: 22,
              ),
              onPressed: _toggleLock,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(bool controlsVisible) {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: AnimatedOpacity(
        opacity: controlsVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 180),
        child: IgnorePointer(
          ignoring: !controlsVisible,
          child: SafeArea(
            bottom: false,
            child: Container(
              height: 56,
              padding: const EdgeInsets.only(left: 2, right: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.80),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: _isLocked ? '解锁' : '锁定',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 40,
                      height: 40,
                    ),
                    icon: Icon(
                      _isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    onPressed: _toggleLock,
                  ),
                  IconButton(
                    tooltip: '返回',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 40,
                      height: 40,
                    ),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                    ),
                    onPressed: _handleBack,
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      '${widget.title} - ${widget.episodeName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCenterPlayButton(bool controlsVisible) {
    final controller = _videoController;
    if (controller == null) return const SizedBox.shrink();
    if (_isLocked) return const SizedBox.shrink();

    if (controller.value.isPlaying && !_isScrubbing) {
      return const SizedBox.shrink();
    }

    return Center(
      child: AnimatedOpacity(
        opacity: controlsVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 180),
        child: IgnorePointer(
          /// 关键：中间按钮不再接收点击，避免误触播放/暂停
          ignoring: true,
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.35),
              shape: BoxShape.circle,
            ),
            child: Icon(
              controller.value.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 44,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(bool controlsVisible) {
    final controller = _videoController;
    final chewieController = _chewieController;
    if (controller == null || chewieController == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: AnimatedOpacity(
        opacity: controlsVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 180),
        child: IgnorePointer(
          ignoring: !controlsVisible,
          child: SafeArea(
            top: false,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.92),
                    Colors.transparent,
                  ],
                ),
              ),
              padding: const EdgeInsets.only(
                bottom: 20,
                top: 40,
                left: 12,
                right: 12,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (widget.onPrevious != null)
                        IconButton(
                          tooltip: '上一集',
                          icon: const Icon(
                            Icons.skip_previous_rounded,
                            color: Colors.white,
                          ),
                          onPressed: widget.onPrevious,
                        ),
                      if (widget.onNext != null)
                        IconButton(
                          tooltip: '下一集',
                          icon: const Icon(
                            Icons.skip_next_rounded,
                            color: Colors.white,
                          ),
                          onPressed: widget.onNext,
                        ),
                      const SizedBox(width: 8),
                      ValueListenableBuilder<VideoPlayerValue>(
                        valueListenable: controller,
                        builder: (context, value, child) {
                          return Text(
                            '${_formatDuration(value.position)} / ${_formatDuration(value.duration)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          );
                        },
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _showSpeedSheet,
                        child: Text(
                          '${_formatSpeed(_playbackSpeed)}x',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      IconButton(
                        tooltip:
                            chewieController.isFullScreen ? '退出全屏' : '全屏',
                        icon: Icon(
                          chewieController.isFullScreen
                              ? Icons.fullscreen_exit_rounded
                              : Icons.fullscreen_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: widget.onToggleFullScreen ??
                            () => chewieController.toggleFullScreen(),
                      ),
                    ],
                  ),
                  SizedBox(
                    height: 20,
                    child: VideoProgressIndicator(
                      controller,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: Colors.blueAccent,
                        bufferedColor: Colors.white38,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _bottomStateText(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScrubOverlay() {
    final controller = _videoController;
    if (controller == null || !_isScrubbing || _isLocked) {
      return const SizedBox.shrink();
    }

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.75),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _scrubCurrentPosition > _scrubBasePosition
                  ? Icons.fast_forward_rounded
                  : Icons.fast_rewind_rounded,
              color: Colors.blueAccent,
              size: 32,
            ),
            const SizedBox(width: 12),
            Text(
              '${_formatDuration(_scrubCurrentPosition)} / ${_formatDuration(controller.value.duration)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLongPressSpeedHint() {
    if (!_isLongPressSpeeding) return const SizedBox.shrink();

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.75),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.speed_rounded,
              color: Colors.blueAccent,
              size: 30,
            ),
            const SizedBox(width: 12),
            Text(
              '${_formatSpeed(_longPressSpeed)}x',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _videoController;
    final chewieController = _chewieController;

    if (controller == null || chewieController == null) {
      return const SizedBox.shrink();
    }

    final showNormalControls =
        !_isLocked && (_showControls || !controller.value.isPlaying || _isScrubbing);

    final showLockOnly = _isLocked && _showLockOnly;

    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              onDoubleTap: _isLocked ? null : _togglePlayPause,
              onLongPressStart: _isLocked ? null : _startLongPressSpeed,
              onLongPressEnd: _isLocked ? null : _onLongPressEnd,
              onLongPressCancel: _isLocked ? null : _onLongPressCancel,
              onHorizontalDragStart: _isLocked ? null : _onHorizontalDragStart,
              onHorizontalDragUpdate:
                  _isLocked ? null : _onHorizontalDragUpdate,
              onHorizontalDragEnd: _isLocked ? null : _onHorizontalDragEnd,
              onHorizontalDragCancel:
                  _isLocked ? null : _onHorizontalDragCancel,
            ),
          ),

          if (showNormalControls) ...[
            _buildTopBar(showNormalControls),
            _buildCenterPlayButton(showNormalControls),
            _buildBottomBar(showNormalControls),
            if (_isScrubbing) _buildScrubOverlay(),
          ],

          if (showLockOnly) _buildLockOnlyButton(),

          _buildLongPressSpeedHint(),
        ],
      ),
    );
  }
}