import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core/models.dart';
import '../video_module.dart';

class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    super.key,
    required this.detail,
    this.initialEpisodeIndex = 0,
  });

  final VideoDetail detail;
  final int initialEpisodeIndex;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;

  int _currentEpisodeIndex = 0;
  VideoEpisode? _currentEpisode;

  bool _loading = true;
  String? _errorMessage;

  bool _isDragging = false;
  double _dragValue = 0;

  double _playbackSpeed = 1.0;
  bool _completionHandled = false;

  Timer? _saveTimer;
  VideoPlaybackProgress? _savedProgress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final count = widget.detail.episodes.length;
    _currentEpisodeIndex = count == 0
        ? 0
        : widget.initialEpisodeIndex.clamp(0, count - 1).toInt();
    _currentEpisode = count > 0 ? widget.detail.episodes[_currentEpisodeIndex] : null;

    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _savedProgress = await VideoModule.repository.getProgress(widget.detail.item.id);

    if (!mounted) return;

    if (widget.detail.episodes.isEmpty) {
      setState(() {
        _loading = false;
        _errorMessage = '当前没有可播放片源';
      });
      return;
    }

    await _prepareEpisode(_currentEpisodeIndex, restoreProgress: true);
  }

  VideoPlaybackProgress? _currentProgress() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return null;

    final value = c.value;
    return VideoPlaybackProgress(
      videoId: widget.detail.item.id,
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
    } catch (_) {
      // ignore
    }
  }

  void _startSaveTimer() {
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _saveProgress();
    });
  }

  Future<void> _prepareEpisode(
    int episodeIndex, {
    required bool restoreProgress,
  }) async {
    if (widget.detail.episodes.isEmpty) return;

    final index = episodeIndex.clamp(0, widget.detail.episodes.length - 1).toInt();
    final episode = widget.detail.episodes[index];

    _saveTimer?.cancel();
    _saveTimer = null;

    final oldController = _controller;
    if (oldController != null) {
      oldController.removeListener(_controllerListener);
      try {
        await oldController.pause();
      } catch (_) {}
      await oldController.dispose();
    }

    final controller = VideoPlayerController.networkUrl(Uri.parse(episode.url));

    setState(() {
      _loading = true;
      _errorMessage = null;
      _controller = controller;
      _currentEpisodeIndex = index;
      _currentEpisode = episode;
      _completionHandled = false;
      _isDragging = false;
      _dragValue = 0;
    });

    try {
      await controller.initialize();
      await controller.setLooping(false);
      await controller.setPlaybackSpeed(_playbackSpeed);
      controller.addListener(_controllerListener);

      if (restoreProgress &&
          _savedProgress != null &&
          _savedProgress!.episodeIndex == index &&
          _savedProgress!.positionSeconds > 3) {
        final target = Duration(milliseconds: (_savedProgress!.positionSeconds * 1000).round());
        final duration = controller.value.duration;
        if (duration > Duration.zero && target < duration - const Duration(seconds: 3)) {
          await controller.seekTo(target);
        }
      }

      if (!mounted) {
        controller.removeListener(_controllerListener);
        await controller.dispose();
        return;
      }

      setState(() {
        _loading = false;
      });

      await controller.play();
      _startSaveTimer();
    } catch (e) {
      await controller.dispose();
      if (!mounted) return;

      setState(() {
        _loading = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _controllerListener() {
    final c = _controller;
    if (c == null || !mounted) return;

    final value = c.value;

    if (value.isInitialized && value.duration > Duration.zero) {
      final isCompleted = value.position >= value.duration - const Duration(milliseconds: 300);
      if (isCompleted && !_completionHandled) {
        _completionHandled = true;
        Future.microtask(_onEpisodeCompleted);
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _onEpisodeCompleted() async {
    await _saveProgress();
    if (!mounted) return;

    if (_currentEpisodeIndex + 1 < widget.detail.episodes.length) {
      await _prepareEpisode(_currentEpisodeIndex + 1, restoreProgress: true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已经播放到最后一集')),
      );
    }
  }

  Future<void> _togglePlayPause() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;

    if (c.value.isPlaying) {
      await c.pause();
      await _saveProgress();
    } else {
      await c.play();
    }

    if (mounted) setState(() {});
  }

  Future<void> _setSpeed(double speed) async {
    _playbackSpeed = speed;
    final c = _controller;
    if (c != null && c.value.isInitialized) {
      await c.setPlaybackSpeed(speed);
    }
    if (mounted) setState(() {});
  }

  Future<void> _switchEpisode(int index) async {
    if (index == _currentEpisodeIndex) return;
    await _saveProgress();
    await _prepareEpisode(index, restoreProgress: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _saveProgress();
      _controller?.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _saveTimer?.cancel();
    _saveTimer = null;

    final progress = _currentProgress();
    if (progress != null) {
      VideoModule.repository.saveProgress(progress);
    }

    _controller?.removeListener(_controllerListener);
    _controller?.dispose();

    super.dispose();
  }

  String _formatDuration(Duration duration) {
    if (duration.inMilliseconds <= 0) return '--:--';

    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);

    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatSeconds(double seconds) {
    if (seconds <= 0) return '--:--';
    return _formatDuration(Duration(milliseconds: (seconds * 1000).round()));
  }

  Widget _loadingOverlay(String text) {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 12),
            Text(text, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  Widget _errorOverlay() {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 44, color: Colors.white),
              const SizedBox(height: 12),
              Text(
                _errorMessage ?? '播放失败',
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _prepareEpisode(_currentEpisodeIndex, restoreProgress: true),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerSurface() {
    final c = _controller;
    final ready = c?.value.isInitialized ?? false;

    final aspectRatio =
        ready && c!.value.aspectRatio > 0 ? c.value.aspectRatio : 16 / 9;

    final duration = ready ? c!.value.duration : Duration.zero;
    final position = ready ? c!.value.position : Duration.zero;

    final displayPosition = _isDragging
        ? Duration(milliseconds: _dragValue.round())
        : position;

    final maxMs = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;

    final sliderValue = displayPosition.inMilliseconds
        .clamp(0, maxMs.toInt())
        .toDouble();

    return Container(
      color: Colors.black,
      child: AspectRatio(
        aspectRatio: aspectRatio <= 0 ? 16 / 9 : aspectRatio,
        child: Stack(
          children: [
            Positioned.fill(
              child: ready
                  ? GestureDetector(
                      onTap: _togglePlayPause,
                      child: VideoPlayer(c!),
                    )
                  : Container(
                      color: Colors.black,
                      child: Center(
                        child: Icon(
                          Icons.play_circle_fill,
                          size: 72,
                          color: Colors.white24,
                        ),
                      ),
                    ),
            ),
            if (ready && c!.value.isBuffering) Positioned.fill(child: _loadingOverlay('缓冲中...')),
            if (_loading) Positioned.fill(child: _loadingOverlay('加载中...')),
            if (_errorMessage != null) Positioned.fill(child: _errorOverlay()),
            Positioned(
              left: 12,
              right: 12,
              bottom: 8,
              child: Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      overlayColor: Colors.white24,
                      trackHeight: 2,
                    ),
                    child: Slider(
                      min: 0,
                      max: maxMs,
                      value: sliderValue,
                      onChangeStart: ready
                          ? (_) {
                              setState(() {
                                _isDragging = true;
                                _completionHandled = false;
                              });
                            }
                          : null,
                      onChanged: ready
                          ? (value) {
                              setState(() {
                                _dragValue = value;
                              });
                            }
                          : null,
                      onChangeEnd: ready
                          ? (value) async {
                              final controller = _controller;
                              if (controller == null || !controller.value.isInitialized) return;

                              final wasPlaying = controller.value.isPlaying;
                              await controller.seekTo(Duration(milliseconds: value.round()));

                              if (wasPlaying) {
                                await controller.play();
                              } else {
                                await controller.pause();
                              }

                              if (mounted) {
                                setState(() {
                                  _isDragging = false;
                                });
                              }

                              await _saveProgress();
                            }
                          : null,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(displayPosition),
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Text(
                        _formatDuration(duration),
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildControlRow(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlRow() {
    final c = _controller;
    final ready = c?.value.isInitialized ?? false;
    final hasPrev = _currentEpisodeIndex > 0;
    final hasNext = _currentEpisodeIndex + 1 < widget.detail.episodes.length;

    return Row(
      children: [
        IconButton(
          onPressed: ready && hasPrev ? () => _switchEpisode(_currentEpisodeIndex - 1) : null,
          icon: const Icon(Icons.skip_previous, color: Colors.white),
        ),
        IconButton(
          onPressed: ready ? _togglePlayPause : null,
          icon: Icon(
            c?.value.isPlaying == true
                ? Icons.pause_circle_filled
                : Icons.play_circle_fill,
            color: Colors.white,
            size: 42,
          ),
        ),
        IconButton(
          onPressed: ready && hasNext ? () => _switchEpisode(_currentEpisodeIndex + 1) : null,
          icon: const Icon(Icons.skip_next, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _currentEpisode == null
                ? '未选择片源'
                : '第 ${_currentEpisodeIndex + 1} / ${widget.detail.episodes.length} 集 · ${_currentEpisode!.title}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          onPressed: widget.detail.episodes.length > 1 ? _openEpisodeSheet : null,
          icon: const Icon(Icons.list_alt_outlined),
          label: const Text('选集'),
        ),
      ],
    );
  }

  Widget _metaChip(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.blueGrey),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    final progress = _savedProgress;
    final episode = _currentEpisode;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: Colors.blue.shade100,
              child: Icon(Icons.play_circle_fill, color: Colors.blue.shade700),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '当前播放',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    episode?.title ?? '暂无片源',
                    style: TextStyle(color: Colors.grey[700], fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    progress == null
                        ? '暂无历史进度'
                        : '上次记录：第 ${progress.episodeIndex + 1} 集 · ${_formatSeconds(progress.positionSeconds)}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: widget.detail.episodes.isEmpty ? null : _openEpisodeSheet,
                        icon: const Icon(Icons.list_alt_outlined),
                        label: const Text('选集'),
                      ),
                      if (progress != null)
                        FilledButton.icon(
                          onPressed: () {
                            final index = progress.episodeIndex
                                .clamp(0, widget.detail.episodes.length - 1)
                                .toInt();
                            _switchEpisode(index);
                          },
                          icon: const Icon(Icons.replay),
                          label: const Text('继续'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (widget.detail.item.sourceName.isNotEmpty)
              _metaChip(widget.detail.item.sourceName, Icons.source),
            if (widget.detail.item.category.isNotEmpty)
              _metaChip(widget.detail.item.category, Icons.folder_outlined),
            if (widget.detail.item.yearText.isNotEmpty)
              _metaChip(widget.detail.item.yearText, Icons.event_outlined),
            if (widget.detail.creator.isNotEmpty)
              _metaChip(widget.detail.creator, Icons.person_outline),
          ],
        ),
      ),
    );
  }

  Widget _buildDescriptionCard() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          widget.detail.description.isNotEmpty ? widget.detail.description : '暂无简介',
          style: const TextStyle(height: 1.6, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildEpisodeListCard() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('选集', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (widget.detail.episodes.isEmpty)
              Text('当前没有可播放片源', style: TextStyle(color: Colors.grey[600]))
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: widget.detail.episodes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final episode = widget.detail.episodes[index];
                  final isCurrent = index == _currentEpisodeIndex;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    tileColor: isCurrent ? Colors.blue.shade50 : const Color(0xFFF8F9FA),
                    leading: Icon(
                      isCurrent ? Icons.play_circle_fill : Icons.play_circle_outline,
                      color: isCurrent ? Colors.blue : Colors.grey,
                    ),
                    title: Text(
                      episode.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCurrent ? Colors.blue.shade700 : Colors.black87,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: episode.durationText.isNotEmpty ? Text(episode.durationText, style: const TextStyle(fontSize: 12)) : null,
                    onTap: () => _switchEpisode(index),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  /// 构建页面主体
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F5),
      appBar: AppBar(
        title: Text(widget.detail.item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<double>(
            icon: const Icon(Icons.speed),
            tooltip: '倍速播放',
            onSelected: _setSpeed,
            itemBuilder: (context) {
              return [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((speed) {
                return PopupMenuItem<double>(
                  value: speed,
                  child: Text('${speed}x ${speed == _playbackSpeed ? " ✓" : ""}'),
                );
              }).toList();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 顶部视频播放层
          _buildPlayerSurface(),
          // 底部信息与选集层
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSummaryCard(),
                const SizedBox(height: 12),
                _buildInfoCard(),
                const SizedBox(height: 12),
                _buildDescriptionCard(),
                const SizedBox(height: 12),
                _buildEpisodeListCard(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 底部唤起选集面板
  void _openEpisodeSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.6,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('选集 (${widget.detail.episodes.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: widget.detail.episodes.length,
                  itemBuilder: (context, index) {
                    final episode = widget.detail.episodes[index];
                    final isCurrent = index == _currentEpisodeIndex;
                    return ListTile(
                      leading: isCurrent ? const Icon(Icons.play_arrow, color: Colors.blue) : null,
                      title: Text(
                        '第 ${index + 1} 集 · ${episode.title}',
                        style: TextStyle(color: isCurrent ? Colors.blue : Colors.black87),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _switchEpisode(index);
                      },
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