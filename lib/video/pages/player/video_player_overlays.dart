import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerOverlays extends StatelessWidget {
  final VideoPlayerController? controller;
  final bool isFullscreen;
  final bool controlsVisible;
  final bool loading;
  final String? errorMessage;
  final bool isDragging;
  final double dragValue;
  final double paddingTop;
  final double playbackSpeed;

  final String headerTitle;
  final String sourceName;
  final String episodeTitle;

  final bool hasPrev;
  final bool hasNext;
  final bool hasSources;

  final bool isLocked;
  final bool isLongPressAccelerating;
  final VoidCallback onToggleLock;
  final VoidCallback onOpenQualitySheet;

  final VoidCallback onTogglePlayPause;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onExit;
  final VoidCallback onRetry;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onOpenEpisodeSheet;

  final ValueChanged<double> onSeekStart;
  final ValueChanged<double> onSeekUpdate;
  final ValueChanged<double> onSeekEnd;
  final ValueChanged<double> onSpeedChange;

  const VideoPlayerOverlays({
    super.key,
    required this.controller,
    required this.isFullscreen,
    required this.controlsVisible,
    required this.loading,
    required this.errorMessage,
    required this.isDragging,
    required this.dragValue,
    required this.paddingTop,
    required this.playbackSpeed,
    required this.headerTitle,
    required this.sourceName,
    required this.episodeTitle,
    required this.hasPrev,
    required this.hasNext,
    required this.hasSources,
    
    required this.isLocked,
    required this.isLongPressAccelerating,
    required this.onToggleLock,
    required this.onOpenQualitySheet,

    required this.onTogglePlayPause,
    required this.onToggleFullscreen,
    required this.onExit,
    required this.onRetry,
    required this.onPrev,
    required this.onNext,
    required this.onOpenEpisodeSheet,
    
    required this.onSeekStart,
    required this.onSeekUpdate,
    required this.onSeekEnd,
    required this.onSpeedChange,
  });

  String _formatDuration(Duration duration) {
    if (duration.inMilliseconds <= 0) return '00:00';
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);

    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _loadingOverlay(String text) {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
            const SizedBox(height: 16),
            Text(
              text,
              style: const TextStyle(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    final webNotice = kIsWeb && (errorMessage?.toLowerCase().contains('m3u8') == true)
        ? '\n(提醒：电脑浏览器可能不支持直接播放此类源，请在 App 端观看)'
        : '';

    return Container(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 48, color: Colors.white),
                const SizedBox(height: 16),
                Text(
                  (errorMessage ?? '播放失败') + webNotice,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    height: 1.6,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重试'),
                    ),
                    if (hasSources)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white30),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: onOpenQualitySheet,
                        icon: const Icon(Icons.router_rounded),
                        label: const Text('切换解析线路'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCenterOverlayPlayButton() {
    final c = controller;
    final ready = c?.value.isInitialized ?? false;
    final isPlaying = c?.value.isPlaying ?? false;

    if (loading || errorMessage != null || isPlaying) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      ignoring: !controlsVisible,
      child: AnimatedOpacity(
        opacity: controlsVisible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Center(
          child: GestureDetector(
            onTap: ready ? onTogglePlayPause : null,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopOverlayBar() {
    final title = episodeTitle.isEmpty
        ? '$headerTitle · $sourceName'
        : '$headerTitle · $sourceName · $episodeTitle';

    return IgnorePointer(
      ignoring: !controlsVisible,
      child: AnimatedOpacity(
        opacity: controlsVisible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black87, Color(0x66000000), Colors.transparent],
            ),
          ),
          padding: EdgeInsets.only(
            top: isFullscreen ? 32 : (paddingTop > 0 ? paddingTop + 4 : 10),
            left: isFullscreen ? 40 : 8,
            right: isFullscreen ? 40 : 8,
            bottom: 32,
          ),
          child: Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onExit,
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 2))],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              PopupMenuButton<double>(
                padding: EdgeInsets.zero,
                tooltip: '播放速度',
                icon: const Icon(Icons.speed_rounded, color: Colors.white, size: 24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: onSpeedChange,
                itemBuilder: (context) {
                  // 新增了 3.0 倍速选项
                  const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];
                  return speeds
                      .map(
                        (s) => PopupMenuItem<double>(
                          value: s,
                          child: Text(
                            '${s}x${s == playbackSpeed ? '   ✓' : ''}',
                            style: TextStyle(
                              fontWeight: s == playbackSpeed ? FontWeight.bold : FontWeight.normal,
                              color: s == playbackSpeed ? Colors.blue : Colors.black87,
                            ),
                          ),
                        ),
                      )
                      .toList();
                },
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onToggleFullscreen,
                icon: Icon(
                  isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomOverlayControls(BuildContext context) {
    final c = controller;
    final ready = c?.value.isInitialized ?? false;
    final isPlaying = c?.value.isPlaying ?? false;
    final duration = ready ? c!.value.duration : Duration.zero;
    final position = ready ? c!.value.position : Duration.zero;

    final displayPosition = isDragging ? Duration(milliseconds: dragValue.round()) : position;

    final maxMs = duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
    final sliderValue = displayPosition.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();

    return IgnorePointer(
      ignoring: !controlsVisible,
      child: AnimatedOpacity(
        opacity: controlsVisible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            padding: EdgeInsets.only(
              bottom: isFullscreen ? 32 : 12,
              top: 36,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0x99000000), Colors.black87],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: isFullscreen ? 40 : 16),
                  child: Row(
                    children: [
                      Text(
                        _formatDuration(displayPosition),
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: Colors.blueAccent,
                            inactiveTrackColor: Colors.white30,
                            thumbColor: Colors.white,
                            overlayColor: Colors.blueAccent.withOpacity(0.25),
                            trackHeight: 3.0,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                          ),
                          child: Slider(
                            min: 0,
                            max: maxMs,
                            value: sliderValue,
                            onChangeStart: ready ? onSeekStart : null,
                            onChanged: ready ? onSeekUpdate : null,
                            onChangeEnd: ready ? onSeekEnd : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDuration(duration),
                        style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: isFullscreen ? 32 : 8),
                  child: Row(
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: ready ? onTogglePlayPause : null,
                        icon: Icon(
                          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      if (hasNext)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: ready ? onNext : null,
                          icon: Icon(
                            Icons.skip_next_rounded,
                            color: ready ? Colors.white : Colors.white30,
                            size: 30,
                          ),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              sourceName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (episodeTitle.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                episodeTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ]
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (hasSources)
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            minimumSize: Size.zero,
                          ),
                          onPressed: onOpenQualitySheet,
                          child: const Text('清晰度', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        ),
                      const SizedBox(width: 2),
                      if (hasSources)  
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.white.withOpacity(0.15),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            minimumSize: Size.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: onOpenEpisodeSheet,
                          icon: const Icon(Icons.format_list_bulleted_rounded, size: 18),
                          label: const Text('选集', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLockOverlay() {
    if (!isFullscreen) return const SizedBox.shrink();

    return IgnorePointer(
      ignoring: !controlsVisible,
      child: AnimatedOpacity(
        opacity: controlsVisible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                padding: const EdgeInsets.all(12),
                iconSize: 26,
                color: Colors.white,
                icon: Icon(isLocked ? Icons.lock_rounded : Icons.lock_open_rounded),
                onPressed: onToggleLock,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAcceleratingIndicator() {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(top: isFullscreen ? 32 : 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
            ),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 4))],
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fast_forward_rounded, color: Colors.white, size: 20),
              SizedBox(width: 6),
              Text('3.0x 极速快进中', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (controller?.value.isInitialized == true &&
              controller!.value.isBuffering &&
              !loading)
            Positioned.fill(child: _loadingOverlay('缓冲中...')),
          if (loading) Positioned.fill(child: _loadingOverlay('连接资源加载中...')),
          if (errorMessage != null) Positioned.fill(child: _buildErrorOverlay()),
          if (isLongPressAccelerating) _buildAcceleratingIndicator(),
          if (!isLocked) _buildCenterOverlayPlayButton(),
          if (!isLocked)
            Positioned.fill(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildTopOverlayBar(),
                  const Spacer(),
                  _buildBottomOverlayControls(context),
                ],
              ),
            ),
          _buildLockOverlay(),
        ],
      ),
    );
  }
}
