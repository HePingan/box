import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class CustomVideoControls extends StatefulWidget {
  final String title;
  final String episodeName;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const CustomVideoControls({
    super.key,
    required this.title,
    required this.episodeName,
    this.onPrevious,
    this.onNext,
  });

  @override
  State<CustomVideoControls> createState() => _CustomVideoControlsState();
}

class _CustomVideoControlsState extends State<CustomVideoControls> {
  ChewieController? _chewieController;
  VideoPlayerController? _controller;

  bool _bound = false;
  bool _showControls = true;
  bool _isLocked = false;
  bool _isScrubbing = false;
  bool _wasPlayingBeforeScrub = false;
  bool _wasPlayingLastTick = false;

  Timer? _hideTimer;

  Duration _baseScrubPosition = Duration.zero;
  Duration _currentScrubPosition = Duration.zero;

  double _playbackSpeed = 1.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_bound) return;

    final chewie = ChewieController.of(context);
    if (chewie == null) return;

    _chewieController = chewie;
    _controller = chewie.videoPlayerController;
    _bound = true;

    _controller!.addListener(_onControllerTick);

    if (_controller!.value.isPlaying) {
      _startHideTimer();
    }
  }

  @override
  void dispose() {
    if (_bound && _controller != null) {
      _controller!.removeListener(_onControllerTick);
    }
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onControllerTick() {
    final controller = _controller;
    if (controller == null) return;

    final isPlaying = controller.value.isPlaying;
    if (isPlaying != _wasPlayingLastTick) {
      _wasPlayingLastTick = isPlaying;

      if (!mounted) return;
      setState(() {
        if (isPlaying) {
          if (!_isLocked && !_isScrubbing) {
            _startHideTimer();
          }
        } else {
          _showControls = true;
          _hideTimer?.cancel();
        }
      });
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;

      final controller = _controller;
      if (controller == null) return;

      if (controller.value.isPlaying && !_isLocked && !_isScrubbing) {
        setState(() => _showControls = false);
      }
    });
  }

  void _togglePlayPause() {
    final controller = _controller;
    if (controller == null) return;

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

  void _onHorizontalDragStart(DragStartDetails details) {
    final controller = _controller;
    if (controller == null) return;
    if (_isLocked) return;

    _baseScrubPosition = controller.value.position;
    _currentScrubPosition = _baseScrubPosition;
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
    final controller = _controller;
    if (controller == null) return;
    if (_isLocked || !_isScrubbing) return;

    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth <= 0) return;

    // 横向拖动一整屏约等于 300 秒
    final dragRatio = details.delta.dx / screenWidth;
    final dragSeconds = (dragRatio * 300).toInt();

    var newPosition = _currentScrubPosition + Duration(seconds: dragSeconds);
    final duration = controller.value.duration;

    if (newPosition < Duration.zero) {
      newPosition = Duration.zero;
    }
    if (newPosition > duration) {
      newPosition = duration;
    }

    setState(() {
      _currentScrubPosition = newPosition;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final controller = _controller;
    if (controller == null) return;
    if (_isLocked || !_isScrubbing) return;

    controller.seekTo(_currentScrubPosition);

    setState(() {
      _isScrubbing = false;
      _showControls = true;
    });

    if (_wasPlayingBeforeScrub) {
      controller.play();
    }

    _startHideTimer();
  }

  void _onHorizontalDragCancel() {
    final controller = _controller;
    if (controller == null) return;
    if (_isLocked || !_isScrubbing) return;

    setState(() {
      _isScrubbing = false;
      _showControls = true;
    });

    if (_wasPlayingBeforeScrub) {
      controller.play();
    }

    _startHideTimer();
  }

  Future<void> _setSpeed(double speed) async {
    final controller = _controller;
    if (controller == null) return;

    await controller.setPlaybackSpeed(speed);

    setState(() {
      _playbackSpeed = speed;
    });

    _startHideTimer();
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

  void _toggleControls() {
    if (_isLocked) return;

    setState(() {
      _showControls = !_showControls;
    });

    if (_showControls) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  String _formatSpeed(double speed) {
    final isInteger = speed.truncateToDouble() == speed;
    return isInteger ? speed.toStringAsFixed(0) : speed.toStringAsFixed(2);
  }

  String _bottomStateText() {
    final controller = _controller;
    if (controller == null) return '';

    final state = controller.value.isPlaying ? '播放中' : '已暂停';
    final buffering = controller.value.isBuffering ? '缓冲中' : '正常';
    final speed = _playbackSpeed;

    return '$state · $buffering · ${_formatSpeed(speed)}x';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final chewieController = _chewieController;

    if (controller == null || chewieController == null) {
      return const SizedBox.shrink();
    }

    final controlsVisible =
        _showControls || !controller.value.isPlaying || _isScrubbing || _isLocked;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            onHorizontalDragStart: _onHorizontalDragStart,
            onHorizontalDragUpdate: _onHorizontalDragUpdate,
            onHorizontalDragEnd: _onHorizontalDragEnd,
            onHorizontalDragCancel: _onHorizontalDragCancel,
          ),
        ),

        Positioned(
          left: 10,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: !controlsVisible,
            child: AnimatedOpacity(
              opacity: controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: Icon(
                    _isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withOpacity(0.5),
                  ),
                  onPressed: () {
                    setState(() {
                      _isLocked = !_isLocked;
                      _showControls = true;
                    });
                    _startHideTimer();
                  },
                ),
              ),
            ),
          ),
        ),

        if (_isScrubbing)
          Align(
            alignment: Alignment.center,
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
                    _currentScrubPosition > _baseScrubPosition
                        ? Icons.fast_forward_rounded
                        : Icons.fast_rewind_rounded,
                    color: Colors.blueAccent,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_formatDuration(_currentScrubPosition)} / ${_formatDuration(controller.value.duration)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

        IgnorePointer(
          ignoring: !controlsVisible,
          child: AnimatedOpacity(
            opacity: controlsVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 220),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    height: 80,
                    padding: const EdgeInsets.only(top: 10, left: 48, right: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.8),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
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
                        if (chewieController.isFullScreen)
                          IconButton(
                            icon: const Icon(
                              Icons.fullscreen_exit_rounded,
                              color: Colors.white,
                            ),
                            onPressed: () => chewieController.toggleFullScreen(),
                          ),
                      ],
                    ),
                  ),
                ),

                Align(
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (widget.onPrevious != null)
                        _buildMiddleButton(
                          icon: Icons.skip_previous_rounded,
                          label: '上一集',
                          onTap: widget.onPrevious!,
                        )
                      else
                        const SizedBox(width: 72),

                      GestureDetector(
                        onTap: _togglePlayPause,
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
                            size: 42,
                          ),
                        ),
                      ),

                      if (widget.onNext != null)
                        _buildMiddleButton(
                          icon: Icons.skip_next_rounded,
                          label: '下一集',
                          onTap: widget.onNext!,
                        )
                      else
                        const SizedBox(width: 72),
                    ],
                  ),
                ),

                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.9),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    padding: const EdgeInsets.only(
                      bottom: 20,
                      top: 40,
                      left: 16,
                      right: 16,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                controller.value.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 32,
                              ),
                              onPressed: _togglePlayPause,
                            ),
                            if (widget.onPrevious != null)
                              IconButton(
                                icon: const Icon(
                                  Icons.skip_previous_rounded,
                                  color: Colors.white,
                                ),
                                onPressed: widget.onPrevious,
                              ),
                            if (widget.onNext != null)
                              IconButton(
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
                              icon: Icon(
                                chewieController.isFullScreen
                                    ? Icons.fullscreen_exit_rounded
                                    : Icons.fullscreen_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                              onPressed: () => chewieController.toggleFullScreen(),
                            ),
                          ],
                        ),
                        SizedBox(
                          height: 20,
                          child: VideoProgressIndicator(
                            controller,
                            allowScrubbing: true,
                            colors: VideoProgressColors(
                              playedColor: Colors.blueAccent,
                              bufferedColor: Colors.white38,
                              backgroundColor: Colors.white24,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _bottomStateText(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMiddleButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 36),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}