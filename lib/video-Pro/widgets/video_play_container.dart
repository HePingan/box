import 'dart:async';
import 'dart:convert';

import 'package:chewie/chewie.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../controller/history_controller.dart';
import '../../utils/app_logger.dart';

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

  final String? referer;
  final Map<String, String>? httpHeaders;
  final String userAgent;
  final bool showDebugInfo;

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
    this.referer,
    this.httpHeaders,
    this.userAgent =
        'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0 Mobile Safari/537.36',
    this.showDebugInfo = false,
  });

  @override
  State<VideoPlayContainer> createState() => _VideoPlayContainerState();
}

class _VideoPlayContainerState extends State<VideoPlayContainer> {
  static const String _fallbackUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  Timer? _saveTimer;

  bool _isError = false;
  bool _isBuffering = true;
  String? _errorMessage;
  int _initToken = 0;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  @override
  void didUpdateWidget(covariant VideoPlayContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.referer != widget.referer ||
        oldWidget.userAgent != widget.userAgent ||
        oldWidget.initialPosition != widget.initialPosition ||
        !mapEquals(oldWidget.httpHeaders, widget.httpHeaders)) {
      _saveCurrentHistory();
      _disposePlayer();
      _initPlayer();
    }
  }

  Map<String, String> _buildRequestHeaders() {
    if (kIsWeb) return const {};

    final userAgent = widget.userAgent.trim().isNotEmpty
        ? widget.userAgent.trim()
        : _fallbackUserAgent;

    final headers = <String, String>{
      'User-Agent': userAgent,
      'Accept': '*/*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Accept-Encoding': 'identity',
      'Connection': 'keep-alive',
    };

    final extraHeaders = widget.httpHeaders;
    if (extraHeaders != null && extraHeaders.isNotEmpty) {
      for (final entry in extraHeaders.entries) {
        final key = entry.key.trim();
        final value = entry.value.trim();
        if (key.isEmpty || value.isEmpty) continue;

        final lowerKey = key.toLowerCase();
        if (lowerKey == 'host' ||
            lowerKey == 'content-length' ||
            lowerKey == 'referer') {
          continue;
        }

        headers[key] = value;
      }
    }

    return headers;
  }

  bool _isInvalidWebPageUrl(Uri uri) {
    final path = uri.path.toLowerCase();
    final host = uri.host.toLowerCase();

    if (path.endsWith('.html') || path.endsWith('.htm')) return true;

    if ((host.contains('iqiyi.com') ||
            host.contains('v.qq.com') ||
            host.contains('mgtv.com') ||
            host.contains('youku.com')) &&
        !path.endsWith('.m3u8') &&
        !path.endsWith('.mp4') &&
        !path.endsWith('.flv')) {
      return true;
    }

    return false;
  }

  List<String> _playlistLines(String text) {
    return const LineSplitter()
        .convert(text)
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  String? _extractQuotedAttr(String line, String key) {
    final match = RegExp('$key="([^"]+)"').firstMatch(line);
    return match?.group(1);
  }

  String _hexPreview(List<int> bytes, {int count = 8}) {
    if (bytes.isEmpty) return '';
    return bytes
        .take(count)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
  }

  Future<http.Response> _httpGetWithTimeout(
    http.Client client,
    Uri uri, {
    Map<String, String>? headers,
  }) {
    return client
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 8));
  }

  Future<Uri> _resolveDirectM3u8(Uri uri) async {
    if (!uri.path.toLowerCase().contains('.m3u8')) return uri;

    Uri currentUri = uri;
    final headers = _buildRequestHeaders();
    final client = http.Client();

    try {
      for (int i = 0; i < 2; i++) {
        final res = await client
            .get(currentUri, headers: headers)
            .timeout(const Duration(milliseconds: 2500));

        final finalUrl = res.request?.url ?? currentUri;
        AppLogger.instance.log(
          'HLS检查: code=${res.statusCode}, final=$finalUrl, ct=${res.headers['content-type']}',
          tag: 'PLAYER',
        );

        if (res.statusCode != 200) {
          break;
        }

        final body = utf8.decode(res.bodyBytes, allowMalformed: true);
        final lines = _playlistLines(body);

        String? childPath;
        for (int k = 0; k < lines.length; k++) {
          if (lines[k].startsWith('#EXT-X-STREAM-INF')) {
            for (int j = k + 1; j < lines.length; j++) {
              final nextLine = lines[j];
              if (!nextLine.startsWith('#')) {
                childPath = nextLine;
                break;
              }
            }
            if (childPath != null) break;
          }
        }

        if (childPath == null || childPath.isEmpty) {
          break;
        }

        final nextUri = finalUrl.resolve(childPath);
        if (nextUri == currentUri) {
          break;
        }

        AppLogger.instance.log(
          'HLS Master 降维成功，切入内核直连 -> $nextUri',
          tag: 'PLAYER',
        );
        currentUri = nextUri;
      }
    } catch (e, st) {
      AppLogger.instance.logError(e, st, 'PLAYER');
    } finally {
      client.close();
    }

    return currentUri;
  }

  Future<void> _probeHls(Uri uri) async {
    if (kIsWeb) return;
    if (!uri.path.toLowerCase().contains('.m3u8')) return;

    final client = http.Client();
    final headers = _buildRequestHeaders();

    try {
      Uri mediaPlaylistUri = uri;
      AppLogger.instance.log('HLS探测开始 -> $uri', tag: 'PLAYER');

      final entryRes = await _httpGetWithTimeout(
        client,
        uri,
        headers: headers,
      );

      final entryFinalUrl = entryRes.request?.url ?? uri;
      AppLogger.instance.log(
        'HLS探测 entry: code=${entryRes.statusCode}, final=$entryFinalUrl, ct=${entryRes.headers['content-type']}, len=${entryRes.bodyBytes.length}',
        tag: 'PLAYER',
      );

      if (entryRes.statusCode != 200) {
        AppLogger.instance.log('HLS探测终止: entry 非 200', tag: 'PLAYER');
        return;
      }

      String body = utf8.decode(entryRes.bodyBytes, allowMalformed: true);
      List<String> lines = _playlistLines(body);
      final isMaster = lines.any((e) => e.startsWith('#EXT-X-STREAM-INF'));

      if (isMaster) {
        String? childPath;
        for (int i = 0; i < lines.length; i++) {
          if (lines[i].startsWith('#EXT-X-STREAM-INF')) {
            for (int j = i + 1; j < lines.length; j++) {
              final next = lines[j];
              if (!next.startsWith('#')) {
                childPath = next;
                break;
              }
            }
            if (childPath != null) break;
          }
        }

        if (childPath == null || childPath.isEmpty) {
          AppLogger.instance.log('HLS探测: master playlist 未找到子线路', tag: 'PLAYER');
          return;
        }

        mediaPlaylistUri = entryFinalUrl.resolve(childPath);

        final mediaRes = await _httpGetWithTimeout(
          client,
          mediaPlaylistUri,
          headers: headers,
        );

        mediaPlaylistUri = mediaRes.request?.url ?? mediaPlaylistUri;
        AppLogger.instance.log(
          'HLS探测 media: code=${mediaRes.statusCode}, final=$mediaPlaylistUri, ct=${mediaRes.headers['content-type']}, len=${mediaRes.bodyBytes.length}',
          tag: 'PLAYER',
        );

        if (mediaRes.statusCode != 200) {
          AppLogger.instance.log('HLS探测终止: media 非 200', tag: 'PLAYER');
          return;
        }

        body = utf8.decode(mediaRes.bodyBytes, allowMalformed: true);
        lines = _playlistLines(body);
      } else {
        mediaPlaylistUri = entryFinalUrl;
        AppLogger.instance.log('HLS探测: 入口本身就是 media playlist', tag: 'PLAYER');
      }

      String? keyLine;
      for (final line in lines) {
        if (line.startsWith('#EXT-X-KEY')) {
          keyLine = line;
          break;
        }
      }

      if (keyLine != null) {
        final keyPath = _extractQuotedAttr(keyLine, 'URI');
        if (keyPath != null && keyPath.isNotEmpty) {
          final keyUri = mediaPlaylistUri.resolve(keyPath);
          final keyRes = await _httpGetWithTimeout(
            client,
            keyUri,
            headers: {
              ...headers,
              'Range': 'bytes=0-15',
            },
          );

          AppLogger.instance.log(
            'HLS探测 key: code=${keyRes.statusCode}, final=${keyRes.request?.url ?? keyUri}, ct=${keyRes.headers['content-type']}, len=${keyRes.bodyBytes.length}, hex=${_hexPreview(keyRes.bodyBytes)}',
            tag: 'PLAYER',
          );
        }
      }

      String? mapLine;
      for (final line in lines) {
        if (line.startsWith('#EXT-X-MAP')) {
          mapLine = line;
          break;
        }
      }

      if (mapLine != null) {
        final mapPath = _extractQuotedAttr(mapLine, 'URI');
        if (mapPath != null && mapPath.isNotEmpty) {
          final mapUri = mediaPlaylistUri.resolve(mapPath);
          final mapRes = await _httpGetWithTimeout(
            client,
            mapUri,
            headers: {
              ...headers,
              'Range': 'bytes=0-63',
            },
          );

          AppLogger.instance.log(
            'HLS探测 map: code=${mapRes.statusCode}, final=${mapRes.request?.url ?? mapUri}, ct=${mapRes.headers['content-type']}, len=${mapRes.bodyBytes.length}, hex=${_hexPreview(mapRes.bodyBytes)}',
            tag: 'PLAYER',
          );
        }
      }

      String? firstSegment;
      for (final line in lines) {
        if (!line.startsWith('#')) {
          firstSegment = line;
          break;
        }
      }

      if (firstSegment == null || firstSegment.isEmpty) {
        AppLogger.instance.log('HLS探测: media playlist 没有找到分片行', tag: 'PLAYER');
        return;
      }

      final segUri = mediaPlaylistUri.resolve(firstSegment);
      final segRes = await _httpGetWithTimeout(
        client,
        segUri,
        headers: {
          ...headers,
          'Range': 'bytes=0-63',
        },
      );

      AppLogger.instance.log(
        'HLS探测 seg: code=${segRes.statusCode}, final=${segRes.request?.url ?? segUri}, ct=${segRes.headers['content-type']}, len=${segRes.bodyBytes.length}, hex=${_hexPreview(segRes.bodyBytes)}',
        tag: 'PLAYER',
      );

      AppLogger.instance.log('HLS探测结束', tag: 'PLAYER');
    } catch (e, st) {
      AppLogger.instance.logError(e, st, 'PLAYER');
    } finally {
      client.close();
    }
  }

  Future<void> _initPlayer() async {
    if (!mounted) return;
    final int token = ++_initToken;

    setState(() {
      _isError = false;
      _errorMessage = null;
      _isBuffering = true;
    });

    final rawUrl = widget.url.trim();
    if (rawUrl.isEmpty) {
      _failFast('播放地址为空');
      return;
    }

    var normalizedUrl = rawUrl.replaceAll('\\', '');
    if (normalizedUrl.startsWith('//')) {
      normalizedUrl = 'https:$normalizedUrl';
    }

    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null || !uri.hasScheme) {
      _failFast('播放地址格式不正确');
      return;
    }

    if (_isInvalidWebPageUrl(uri)) {
      _failFast('该资源为网页跳转链接，无法直接播放\n请尝试切换其他播放源或线路');
      return;
    }

    try {
      AppLogger.instance.log('原始播放地址: $uri', tag: 'PLAYER');
      AppLogger.instance.log('执行极速 HLS 检查...', tag: 'PLAYER');

      final playableUri = await _resolveDirectM3u8(uri);
      AppLogger.instance.log('最终播放地址: $playableUri', tag: 'PLAYER');

      if (!mounted || token != _initToken) return;

      if (!kIsWeb && playableUri.path.toLowerCase().contains('.m3u8')) {
        await _probeHls(playableUri);
      }

      if (!mounted || token != _initToken) return;

      final headers = _buildRequestHeaders();

      final controller = kIsWeb
          ? VideoPlayerController.networkUrl(
              playableUri,
              formatHint: VideoFormat.hls,
              videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
            )
          : VideoPlayerController.networkUrl(
              playableUri,
              formatHint: VideoFormat.hls,
              httpHeaders: headers,
              videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
            );

      _videoPlayerController = controller;

      controller.addListener(() {
        if (!mounted || token != _initToken) return;
        final value = controller.value;

        if (value.hasError) {
          final msg = value.errorDescription ?? '视频播放失败';
          AppLogger.instance.log('视频播放器错误: $msg', tag: 'PLAYER');

          if (!_isError && mounted) {
            setState(() {
              _isError = true;
              _errorMessage = msg;
            });
          }
          return;
        }

        if (mounted) {
          final buffering = value.isBuffering;
          if (buffering != _isBuffering) {
            setState(() {
              _isBuffering = buffering;
            });
          }
        }
      });

      AppLogger.instance.log('开始初始化底层播放器...', tag: 'PLAYER');
      await controller.initialize();
      AppLogger.instance.log('播放器初始化完成', tag: 'PLAYER');

      if (!mounted || token != _initToken) {
        await controller.dispose();
        return;
      }

      if (widget.initialPosition > 0) {
        final initial = Duration(milliseconds: widget.initialPosition);
        if (controller.value.duration > initial) {
          await controller.seekTo(initial);
        }
      }

      _chewieController?.dispose();
      _chewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        looping: false,
        allowMuting: true,
        allowFullScreen: true,
        showControlsOnInitialize: false,
        customControls: _CustomVideoControls(
          title: widget.title,
          episodeName: widget.episodeName,
          onPrevious: widget.onPreviousEpisode,
          onNext: widget.onNextEpisode,
        ),
        aspectRatio:
            controller.value.aspectRatio > 0 ? controller.value.aspectRatio : 16 / 9,
      );

      if (mounted && token == _initToken) {
        setState(() {
          _isError = false;
          _errorMessage = null;
          _isBuffering = false;
        });
      }

      _saveTimer?.cancel();
      _saveTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _saveCurrentHistory(),
      );
    } catch (e, st) {
      AppLogger.instance.logError(e, st, 'PLAYER');
      _disposePlayer();
      if (mounted && token == _initToken) {
        setState(() {
          _isError = true;
          _errorMessage = '播放器启动失败：请检测网络或更换线路';
        });
      }
    }
  }

  void _failFast(String msg) {
    if (!mounted) return;
    setState(() {
      _isError = true;
      _errorMessage = msg;
    });
    AppLogger.instance.log('异常阻断: $msg', tag: 'PLAYER');
  }

  Future<void> _retry() async {
    _saveCurrentHistory();
    _disposePlayer();
    if (!mounted) return;
    setState(() {
      _isError = false;
      _errorMessage = null;
      _isBuffering = true;
    });
    await _initPlayer();
  }

  void _saveCurrentHistory() {
    if (!mounted || _videoPlayerController == null) return;
    if (!_videoPlayerController!.value.isInitialized) return;

    final posMs = _videoPlayerController!.value.position.inMilliseconds;
    final durMs = _videoPlayerController!.value.duration.inMilliseconds;

    if (posMs > 0 && durMs > 0 && widget.vodId.isNotEmpty) {
      try {
        AppLogger.instance.log(
          '保存历史: vodId=${widget.vodId}, pos=$posMs, dur=$durMs, episode=${widget.episodeName}',
          tag: 'HISTORY',
        );

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
      } catch (e, st) {
        AppLogger.instance.logError(e, st, 'HISTORY');
      }
    }
  }

  void _disposePlayer() {
    _saveTimer?.cancel();
    _saveTimer = null;

    _chewieController?.dispose();
    _chewieController = null;

    _videoPlayerController?.dispose();
    _videoPlayerController = null;
  }

  @override
  void dispose() {
    _saveCurrentHistory();
    _disposePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isError) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: Colors.black,
          child: _buildErrorOverlay(
            errorMessage: _errorMessage ?? '资源失效',
          ),
        ),
      );
    }

    if (_videoPlayerController == null ||
        _chewieController == null ||
        !_videoPlayerController!.value.isInitialized) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: Colors.black,
          child: const Center(
            child: CircularProgressIndicator(color: Colors.blueAccent),
          ),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Chewie(controller: _chewieController!),
            if (_isBuffering) _buildBufferingOverlay(),
            if (widget.showDebugInfo) _buildDebugOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildBufferingOverlay() {
    return IgnorePointer(
      child: Container(
        color: Colors.transparent,
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Text(
                '拼命缓冲中...',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorOverlay({required String errorMessage}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.videocam_off_rounded,
              color: Colors.white54,
              size: 46,
            ),
            const SizedBox(height: 12),
            Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: _retry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重试线路'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDebugOverlay() {
    final controller = _videoPlayerController;
    final pos = controller?.value.position.inSeconds ?? 0;
    final dur = controller?.value.duration.inSeconds ?? 0;

    return Positioned(
      right: 12,
      top: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.45),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'pos: $pos s / $dur s',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }
}

class _CustomVideoControls extends StatefulWidget {
  final String title;
  final String episodeName;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _CustomVideoControls({
    required this.title,
    required this.episodeName,
    this.onPrevious,
    this.onNext,
  });

  @override
  State<_CustomVideoControls> createState() => _CustomVideoControlsState();
}

class _CustomVideoControlsState extends State<_CustomVideoControls>
    with SingleTickerProviderStateMixin {
  late VideoPlayerController _controller;
  ChewieController? _chewieController;

  bool _showControls = true;
  bool _isLocked = false;
  bool _isSpeeding = false;
  Timer? _hideTimer;

  Offset? _tapPosition;
  String? _skipFeedbackText;

  bool _isScrubbing = false;
  Duration _baseScrubPosition = Duration.zero;
  Duration _currentScrubPosition = Duration.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chewieController = ChewieController.of(context);
    _controller = _chewieController!.videoPlayerController;
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _playPause() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
        _showControls = true;
        _hideTimer?.cancel();
      } else {
        _controller.play();
        _startHideTimer();
      }
    });
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted &&
          _controller.value.isPlaying &&
          !_isSpeeding &&
          !_isScrubbing) {
        setState(() => _showControls = false);
      }
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return duration.inHours > 0
        ? '$hours:$minutes:$seconds'
        : '$minutes:$seconds';
  }

  void _skipTime(Duration offset) {
    final duration = _controller.value.duration;
    final newPos = _controller.value.position + offset;
    final clampedPos = newPos < Duration.zero
        ? Duration.zero
        : (newPos > duration ? duration : newPos);

    _controller.seekTo(clampedPos);

    setState(() {
      _skipFeedbackText = offset.isNegative ? '⏪  -10s' : '⏩  +10s';
    });

    _startHideTimer();

    Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() => _skipFeedbackText = null);
      }
    });
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (_isLocked) return;
    _baseScrubPosition = _controller.value.position;
    _currentScrubPosition = _baseScrubPosition;
    setState(() {
      _isScrubbing = true;
      _hideTimer?.cancel();
    });
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_isLocked || !_isScrubbing) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final dragRatio = details.delta.dx / screenWidth;
    final dragSeconds = (dragRatio * 300).toInt();

    var newPosition = _currentScrubPosition + Duration(seconds: dragSeconds);
    final duration = _controller.value.duration;

    if (newPosition < Duration.zero) {
      newPosition = Duration.zero;
    }
    if (newPosition > duration) {
      newPosition = duration;
    }

    setState(() => _currentScrubPosition = newPosition);
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_isLocked || !_isScrubbing) return;

    _controller.seekTo(_currentScrubPosition);

    setState(() {
      _isScrubbing = false;
    });

    _startHideTimer();

    if (!_controller.value.isPlaying) {
      _controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_chewieController == null) return const SizedBox.shrink();

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _tapPosition = details.localPosition,
            onTap: () {
              setState(() => _showControls = !_showControls);
              if (_showControls) {
                _startHideTimer();
              }
            },
            onDoubleTap: () {
              if (_isLocked || _tapPosition == null) return;

              final width = MediaQuery.of(context).size.width;
              final dx = _tapPosition!.dx;

              if (dx < width * 0.35) {
                _skipTime(const Duration(seconds: -10));
              } else if (dx > width * 0.65) {
                _skipTime(const Duration(seconds: 10));
              } else {
                _playPause();
              }
            },
            onLongPressStart: (_) {
              if (_isLocked) return;
              setState(() => _isSpeeding = true);
              _controller.setPlaybackSpeed(2.0);
            },
            onLongPressEnd: (_) {
              if (_isLocked) return;
              setState(() => _isSpeeding = false);
              _controller.setPlaybackSpeed(1.0);
            },
            onHorizontalDragStart: _onHorizontalDragStart,
            onHorizontalDragUpdate: _onHorizontalDragUpdate,
            onHorizontalDragEnd: _onHorizontalDragEnd,
          ),
        ),
        if (_isSpeeding)
          const Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.only(top: 20),
              child: Chip(
                backgroundColor: Colors.black87,
                avatar: Icon(
                  Icons.fast_forward_rounded,
                  color: Colors.blueAccent,
                  size: 18,
                ),
                label: Text(
                  '2.0X 极速播放中',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        if (_skipFeedbackText != null)
          Align(
            alignment: _skipFeedbackText!.contains('⏪')
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  _skipFeedbackText!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        if (_isScrubbing)
          Align(
            alignment: Alignment.center,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
                    '${_formatDuration(_currentScrubPosition)} / ${_formatDuration(_controller.value.duration)}',
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
        AnimatedOpacity(
          opacity: _showControls && !_isScrubbing ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 20),
              child: IgnorePointer(
                ignoring: !_showControls || _isScrubbing,
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
                    setState(() => _isLocked = !_isLocked);
                    _startHideTimer();
                  },
                ),
              ),
            ),
          ),
        ),
        if (!_isLocked)
          AnimatedOpacity(
            opacity: _showControls && !_isScrubbing ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: IgnorePointer(
              ignoring: !_showControls || _isScrubbing,
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      height: 80,
                      padding: const EdgeInsets.only(top: 10),
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
                          if (_chewieController!.isFullScreen)
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: Colors.white,
                              ),
                              onPressed: () =>
                                  _chewieController!.toggleFullScreen(),
                            )
                          else
                            const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              '${widget.title} - ${widget.episodeName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
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
                                  _controller.value.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 32,
                                ),
                                onPressed: _playPause,
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
                                valueListenable: _controller,
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
                              IconButton(
                                icon: Icon(
                                  _chewieController!.isFullScreen
                                      ? Icons.fullscreen_exit_rounded
                                      : Icons.fullscreen_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                                onPressed: () =>
                                    _chewieController!.toggleFullScreen(),
                              ),
                            ],
                          ),
                          SizedBox(
                            height: 20,
                            child: VideoProgressIndicator(
                              _controller,
                              allowScrubbing: true,
                              colors: VideoProgressColors(
                                playedColor: Colors.blueAccent,
                                bufferedColor: Colors.white38,
                                backgroundColor: Colors.white24,
                              ),
                            ),
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
}