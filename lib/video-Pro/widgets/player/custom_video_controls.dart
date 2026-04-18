import 'dart:async';
import 'dart:ui';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

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
  bool _showControls = true;
  bool _isLocked = false;

  // 手势与防抖
  bool _isReallyScrubbing = false;
  bool _isScrubbing = false;
  bool _wasPlayingBeforeScrub = false;

  int _lastTapTime = 0;
  Timer? _singleTapTimer;

  // 记录上一次播放状态，防止自动触发导致的 UI 闪烁
  bool? _lastKnownPlayingState;

  Timer? _hideTimer;

  bool _isLongPressSpeeding = false;
  double _speedBeforeLongPress = 1.0;
  final double _longPressSpeed = 2.0;

  Duration _scrubBasePosition = Duration.zero;
  Duration _scrubCurrentPosition = Duration.zero;
  double _playbackSpeed = 1.0;

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
    _lastKnownPlayingState = _videoController!.value.isPlaying;

    if (_videoController!.value.isPlaying) {
      _startHideTimer();
    } else {
      _showControls = true; // 初始暂停时显示
    }
  }

  @override
  void dispose() {
    _videoController?.removeListener(_onVideoTick);
    _hideTimer?.cancel();
    _singleTapTimer?.cancel();
    super.dispose();
  }

  // 🚀 核心优化：监控播放器状态变化
  void _onVideoTick() {
    if (!mounted || _videoController == null) return;

    final isPlaying = _videoController!.value.isPlaying;
    
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
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 3000), () {
      // 只有在视频正在播放且没锁定时，才隐去控制栏
      if (mounted && _videoController?.value.isPlaying == true && !_isLocked && !_isScrubbing) {
        setState(() => _showControls = false);
      }
    });
  }

  // 🚀 核心优化：手动由于单双击，彻底拦截任何点击穿透
  void _handleTap() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final delta = now - _lastTapTime;
    _lastTapTime = now;

    if (delta < 300) {
      // 【双击动作】判定发生
      _singleTapTimer?.cancel();
      if (!_isLocked) {
        _togglePlayPause(); // 仅在这里执行视频的暂停/播放
      }
    } else {
      // 【单击动作】候选
      _singleTapTimer?.cancel();
      _singleTapTimer = Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        
        // 🚨 核心改动：单击只准由控制 UI，绝对不去碰视频的 play() 或 pause()
        setState(() {
          _showControls = !_showControls;
          if (_showControls) {
            // 如果点亮了控制面板
            if (_videoController?.value.isPlaying == true) {
              _startHideTimer(); // 播放中则开启倒计时隐藏
            } else {
              _hideTimer?.cancel(); // 暂停中则永久显示
            }
          } else {
            _hideTimer?.cancel();
          }
        });
      });
    }
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
      if (!_isLocked && _videoController?.value.isPlaying == true) {
        _startHideTimer();
      } else {
        _hideTimer?.cancel();
      }
    });
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return d.inHours > 0 
        ? '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}'
        : '${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }

  // ============== 手势逻辑（修正 clamp 报错） ==============

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_videoController == null || _isLocked) return;

    if (!_isReallyScrubbing) {
      _isReallyScrubbing = true;
      _wasPlayingBeforeScrub = _videoController!.value.isPlaying;
      if (_wasPlayingBeforeScrub) _videoController!.pause();
      setState(() {
        _isScrubbing = true;
        _showControls = true;
      });
      _hideTimer?.cancel();
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final dragSeconds = (details.delta.dx / screenWidth * 180).toInt();
    
    var newPos = _scrubCurrentPosition + Duration(seconds: dragSeconds);
    
    // 🚀 修复编译错误：手动替换 clamp 逻辑
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

  void _onHorizontalDragEnd(DragEndDetails? details) {
    if (_isReallyScrubbing && _videoController != null) {
      _videoController!.seekTo(_scrubCurrentPosition);
      if (_wasPlayingBeforeScrub) _videoController!.play();
    }
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

    return SizedBox.expand(
      child: Stack(
        children: [
          // 🚀 核心透明拦截层：强制使用 HitTestBehavior.opaque 拦截所有底层穿透
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleTap,
              onLongPressStart: _isLocked ? null : (d) {
                _wasPlayingBeforeScrub = _videoController!.value.isPlaying;
                _videoController!.setPlaybackSpeed(_longPressSpeed);
                setState(() => _isLongPressSpeeding = true);
              },
              onLongPressEnd: _isLocked ? null : (d) {
                _videoController!.setPlaybackSpeed(_playbackSpeed);
                if (!_wasPlayingBeforeScrub) _videoController!.pause();
                setState(() => _isLongPressSpeeding = false);
              },
              onHorizontalDragStart: _isLocked ? null : (d) {
                _scrubCurrentPosition = _videoController!.value.position;
                _isReallyScrubbing = false;
              },
              onHorizontalDragUpdate: _isLocked ? null : _onHorizontalDragUpdate,
              onHorizontalDragEnd: _isLocked ? null : _onHorizontalDragEnd,
            ),
          ),

          // 顶部
          _buildAnimatedBar(
            alignment: Alignment.topCenter,
            visible: _showControls && !_isLocked,
            child: _buildTopBar(),
          ),

          // 底部
          _buildAnimatedBar(
            alignment: Alignment.bottomCenter,
            visible: _showControls && !_isLocked,
            child: _buildBottomBar(),
          ),

          // 锁按钮
          _buildAnimatedLock(),

          // 中心播放按钮：仅在暂停时或面板开启时显示
          if (!_isLocked && (_showControls || !_videoController!.value.isPlaying))
            Center(child: _buildLargePlayButton()),

          // Overlay 提示层
          if (_isScrubbing) _buildScrubOverlay(),
          if (_isLongPressSpeeding) _buildSpeedHint(),
        ],
      ),
    );
  }

  Widget _buildAnimatedBar({required Alignment alignment, required bool visible, required Widget child}) {
    return Positioned(
      left: 0, right: 0,
      top: alignment == Alignment.topCenter ? 0 : null,
      bottom: alignment == Alignment.bottomCenter ? 0 : null,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
        child: visible ? child : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 70, padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.black87, Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
      child: SafeArea(child: Row(children: [
        IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white), onPressed: () => Navigator.maybePop(context)),
        Expanded(child: Text('${widget.title} - ${widget.episodeName}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
      ])),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Colors.black87], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
      child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Text('${_formatDuration(_videoController!.value.position)} / ${_formatDuration(_videoController!.value.duration)}', style: const TextStyle(color: Colors.white, fontSize: 12)),
          const Spacer(),
          IconButton(
            icon: Icon(_chewieController!.isFullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, color: Colors.white),
            onPressed: widget.onToggleFullScreen ?? () => _chewieController!.toggleFullScreen(),
          ),
        ]),
        VideoProgressIndicator(_videoController!, allowScrubbing: true, colors: const VideoProgressColors(playedColor: Colors.blueAccent)),
      ])),
    );
  }

  Widget _buildLargePlayButton() {
    final playing = _videoController!.value.isPlaying;
    return GestureDetector(
      onTap: _togglePlayPause,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
        child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 48),
      ),
    );
  }

  Widget _buildAnimatedLock() {
    return Positioned(
      left: 20, top: 0, bottom: 0,
      child: Center(
        child: AnimatedOpacity(
          opacity: _showControls || _isLocked ? 1 : 0, duration: const Duration(milliseconds: 200),
          child: IconButton(
            icon: Icon(_isLocked ? Icons.lock_rounded : Icons.lock_open_rounded, color: Colors.white, size: 28),
            onPressed: _toggleLock,
          ),
        ),
      ),
    );
  }

  Widget _buildScrubOverlay() {
    return Center(child: Container(
      padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
      child: Text('${_formatDuration(_scrubCurrentPosition)} / ${_formatDuration(_videoController!.value.duration)}', 
        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, fontFeatures: [FontFeature.tabularFigures()])),
    ));
  }

  Widget _buildSpeedHint() {
    return Align(alignment: Alignment.topCenter, child: SafeArea(child: Container(
      margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.8), borderRadius: BorderRadius.circular(20)),
      child: const Text('2.0x 倍速播放中', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    )));
  }
}