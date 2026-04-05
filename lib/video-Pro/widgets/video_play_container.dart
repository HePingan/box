import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../controller/history_controller.dart';

class VideoPlayContainer extends StatefulWidget {
  final String url;
  final String title;
  final String vodId;
  final String vodPic;
  final String sourceId;
  final String sourceName;
  final String episodeName;
  final int initialPosition;

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
  });

  @override
  State<VideoPlayContainer> createState() => _VideoPlayContainerState();
}

class _VideoPlayContainerState extends State<VideoPlayContainer> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  Timer? _saveTimer;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  @override
  void didUpdateWidget(covariant VideoPlayContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当切换选集时，销毁旧播放器，加载新集数
    if (oldWidget.url != widget.url) {
      _saveCurrentHistory();
      _disposePlayer();
      _initPlayer();
    }
  }

  Future<void> _initPlayer() async {
    setState(() => _isError = false);
    try {
      // 强行把 https 降级为 http，无视所有无效证书错误！
String safeUrl = widget.url.replaceFirst('https://', 'http://');

_videoPlayerController = VideoPlayerController.networkUrl(
  Uri.parse(safeUrl),
      await _videoPlayerController!.initialize();

      // 断点续播
      if (widget.initialPosition > 0) {
        await _videoPlayerController!.seekTo(Duration(milliseconds: widget.initialPosition));
      }

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        aspectRatio: 16 / 9,
        materialProgressColors: ChewieProgressColors(
          playedColor: Theme.of(context).colorScheme.primary,
          handleColor: Theme.of(context).colorScheme.primary,
          backgroundColor: Colors.grey.withOpacity(0.5),
          bufferedColor: Colors.white.withOpacity(0.5),
        ),
        errorBuilder: (context, errorMessage) {
          return const Center(
            child: Text('视频加载失败，请切换选集或源重试', style: TextStyle(color: Colors.white)),
          );
        },
      );

      if (mounted) setState(() {});

      // 定时保存历史记录 (每5秒)
      _saveTimer?.cancel();
      _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _saveCurrentHistory());
    } catch (e) {
      if (mounted) setState(() => _isError = true);
    }
  }

  void _saveCurrentHistory() {
    if (!mounted || _videoPlayerController == null) return;
    if (!_videoPlayerController!.value.isInitialized) return;

    final posMs = _videoPlayerController!.value.position.inMilliseconds;
    final durMs = _videoPlayerController!.value.duration.inMilliseconds;

    if (posMs > 0 && durMs > 0 && widget.vodId.isNotEmpty) {
      context.read<HistoryController>().saveProgress(
            vodId: widget.vodId,
            vodName: widget.title,
            vodPic: widget.vodPic,
            sourceId: widget.sourceId,
            sourceName: widget.sourceName,
            episodeName: widget.episodeName,
            episodeUrl: widget.url,
            position: posMs,
            duration: durMs,
          );
    }
  }

  void _disposePlayer() {
    _saveTimer?.cancel();
    _chewieController?.dispose();
    _videoPlayerController?.dispose();
    _chewieController = null;
    _videoPlayerController = null;
  }

  @override
  void dispose() {
    _saveCurrentHistory(); // 退出前最后存一次
    _disposePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: _buildPlayerContent(),
    );
  }

  Widget _buildPlayerContent() {
    if (_isError) {
      return const Center(child: Text('视频资源失效', style: TextStyle(color: Colors.white)));
    }
    if (_chewieController != null && _videoPlayerController != null && _videoPlayerController!.value.isInitialized) {
      return Chewie(controller: _chewieController!);
    }
    return const Center(child: CircularProgressIndicator(color: Colors.white));
  }
}