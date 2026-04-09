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

class _VideoPlayContainerState extends State<VideoPlayContainer>
    with WidgetsBindingObserver {
  static const String _fallbackUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  static const Duration _probeTimeout = Duration(seconds: 5);
  static const Duration _initTimeout = Duration(seconds: 8);

  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;

  Timer? _historyTimer;

  bool _isError = false;
  bool _isBuffering = true;
  bool _wasPlayingBeforePause = false;
  bool _wasPlayingLastTick = false;
  bool _playbackFailed = false;

  String? _errorMessage;
  int _initToken = 0;

  int _lastSavedPositionMs = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPlayer();
  }

  @override
  void didUpdateWidget(covariant VideoPlayContainer oldWidget) {
    super.didUpdateWidget(oldWidget);

    final shouldRebuildPlayer = oldWidget.url != widget.url ||
        oldWidget.referer != widget.referer ||
        oldWidget.userAgent != widget.userAgent ||
        oldWidget.initialPosition != widget.initialPosition ||
        oldWidget.vodId != widget.vodId ||
        oldWidget.vodPic != widget.vodPic ||
        oldWidget.sourceId != widget.sourceId ||
        oldWidget.sourceName != widget.sourceName ||
        !mapEquals(oldWidget.httpHeaders, widget.httpHeaders);

    if (shouldRebuildPlayer) {
      _saveCurrentHistory(force: true);
      _disposePlayer();
      _initPlayer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _videoPlayerController;
    if (controller == null) return;

    if (state == AppLifecycleState.paused) {
      _wasPlayingBeforePause = controller.value.isPlaying;
      _saveCurrentHistory(force: true);
      if (controller.value.isPlaying) {
        controller.pause();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_wasPlayingBeforePause) {
        controller.play();
      }
      _wasPlayingBeforePause = false;
    }
  }

  Map<String, String> _buildRequestHeaders() {
    if (kIsWeb) return const {};

    final ua = widget.userAgent.trim().isNotEmpty
        ? widget.userAgent.trim()
        : _fallbackUserAgent;

    final headers = <String, String>{
      'User-Agent': ua,
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
            lowerKey == 'referer' ||
            lowerKey == 'origin') {
          continue;
        }

        headers[key] = value;
      }
    }

    final referer = widget.referer?.trim();
    if (referer != null && referer.isNotEmpty) {
      headers['Referer'] = referer;

      final origin = _originFromUrl(referer);
      if (origin != null && origin.isNotEmpty) {
        headers['Origin'] = origin;
      }
    }

    return headers;
  }

  String? _originFromUrl(String raw) {
    try {
      final uri = Uri.parse(raw);
      if (!uri.hasScheme || uri.host.isEmpty) return null;
      return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
    } catch (_) {
      return null;
    }
  }

  String _normalizeUrl(String raw) {
    var url = raw.trim().replaceAll('\\', '');
    if (url.startsWith('//')) {
      url = 'https:$url';
    }
    return url;
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
    Duration timeout = _probeTimeout,
  }) {
    return client.get(uri, headers: headers).timeout(timeout);
  }

  /// 把 m3u8 的 master playlist 尽量降到 media playlist
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
          return currentUri;
        }

        final body = utf8.decode(res.bodyBytes, allowMalformed: true);
        final lines = _playlistLines(body);

        final isMaster = lines.any((e) => e.startsWith('#EXT-X-STREAM-INF'));
        if (!isMaster) {
          return finalUrl;
        }

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
          return finalUrl;
        }

        final nextUri = finalUrl.resolve(childPath);
        if (nextUri == currentUri) {
          return finalUrl;
        }

        AppLogger.instance.log(
          'HLS Master 降维成功，切入内核直连 -> $nextUri',
          tag: 'PLAYER',
        );
        currentUri = nextUri;
      }
    } catch (e, st) {
      AppLogger.instance.logError(e, st, 'PLAYER');
      return uri;
    } finally {
      client.close();
    }

    return currentUri;
  }

  /// HLS 预探测：
  /// 1. 拉 m3u8
  /// 2. 如果是 master playlist，再拉子 playlist
  /// 3. 找首个分片
  /// 4. 只探测首个分片
  ///
  /// 任何一步失败都直接返回 false，
  /// 这样播放器不会傻等到底层超时。
  Future<bool> _probeHls(Uri uri) async {
    if (kIsWeb) return true;
    if (!uri.path.toLowerCase().contains('.m3u8')) return true;

    final client = http.Client();
    final headers = _buildRequestHeaders();

    try {
      Uri mediaPlaylistUri = uri;

      AppLogger.instance.log('HLS探测开始 -> $uri', tag: 'PLAYER');

      final entryRes = await _httpGetWithTimeout(
        client,
        uri,
        headers: headers,
        timeout: _probeTimeout,
      );

      final entryFinalUrl = entryRes.request?.url ?? uri;
      AppLogger.instance.log(
        'HLS探测 entry: code=${entryRes.statusCode}, final=$entryFinalUrl, ct=${entryRes.headers['content-type']}, len=${entryRes.bodyBytes.length}',
        tag: 'PLAYER',
      );

      if (entryRes.statusCode != 200) {
        AppLogger.instance.log('HLS探测终止: entry 非 200', tag: 'PLAYER');
        return false;
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
          AppLogger.instance.log(
            'HLS探测: master playlist 未找到子线路',
            tag: 'PLAYER',
          );
          return false;
        }

        mediaPlaylistUri = entryFinalUrl.resolve(childPath);

        final mediaRes = await _httpGetWithTimeout(
          client,
          mediaPlaylistUri,
          headers: headers,
          timeout: _probeTimeout,
        );

        mediaPlaylistUri = mediaRes.request?.url ?? mediaPlaylistUri;
        AppLogger.instance.log(
          'HLS探测 media: code=${mediaRes.statusCode}, final=$mediaPlaylistUri, ct=${mediaRes.headers['content-type']}, len=${mediaRes.bodyBytes.length}',
          tag: 'PLAYER',
        );

        if (mediaRes.statusCode != 200) {
          AppLogger.instance.log('HLS探测终止: media 非 200', tag: 'PLAYER');
          return false;
        }

        body = utf8.decode(mediaRes.bodyBytes, allowMalformed: true);
        lines = _playlistLines(body);
      } else {
        mediaPlaylistUri = entryFinalUrl;
        AppLogger.instance.log('HLS探测: 入口本身就是 media playlist', tag: 'PLAYER');
      }

      /// 可选：探一下 KEY / MAP，帮助更早发现异常，但失败不直接判死
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

      /// 找首个分片
      String? firstSegment;
      for (final line in lines) {
        if (!line.startsWith('#')) {
          firstSegment = line;
          break;
        }
      }

      if (firstSegment == null || firstSegment.isEmpty) {
        AppLogger.instance.log(
          'HLS探测: media playlist 没有找到分片行',
          tag: 'PLAYER',
        );
        return true;
      }

      /// 只探测首个分片，拿不到就直接失败
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

      if (segRes.statusCode != 200 && segRes.statusCode != 206) {
        return false;
      }

      if (segRes.bodyBytes.isEmpty) {
        return false;
      }

      AppLogger.instance.log('HLS探测结束', tag: 'PLAYER');
      return true;
    } catch (e, st) {
      AppLogger.instance.logError(e, st, 'PLAYER');
      return false;
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
      _playbackFailed = false;
    });

    final rawUrl = _normalizeUrl(widget.url);
    if (rawUrl.isEmpty) {
      _failFast('播放地址为空');
      return;
    }

    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !uri.hasScheme) {
      _failFast('播放地址格式不正确');
      return;
    }

    if (_isInvalidWebPageUrl(uri)) {
      _failFast('该资源更像网页跳转链接，无法直接播放\n请尝试切换其他播放源或线路');
      return;
    }

    try {
      AppLogger.instance.log('原始播放地址: $uri', tag: 'PLAYER');
      AppLogger.instance.log('开始解析播放地址...', tag: 'PLAYER');

      final playableUri = await _resolveDirectM3u8(uri);

      if (!mounted || token != _initToken) return;

      AppLogger.instance.log('最终播放地址: $playableUri', tag: 'PLAYER');

      /// 关键改动：
      /// 只要是 HLS，就先探测首片。
      if (!kIsWeb && playableUri.path.toLowerCase().contains('.m3u8')) {
        final probeOk = await _probeHls(playableUri);
        if (!probeOk) {
          if (mounted && token == _initToken) {
            _failFast('该线路的分片服务器拒绝了当前设备连接，请切换线路');
          }
          return;
        }
      }

      if (!mounted || token != _initToken) return;

      final headers = _buildRequestHeaders();
      final formatHint = playableUri.path.toLowerCase().contains('.m3u8')
          ? VideoFormat.hls
          : null;

      final controller = kIsWeb
          ? VideoPlayerController.networkUrl(
              playableUri,
              formatHint: formatHint,
              videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
            )
          : VideoPlayerController.networkUrl(
              playableUri,
              formatHint: formatHint,
              httpHeaders: headers,
              videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
            );

      _videoPlayerController = controller;
      _wasPlayingLastTick = false;
      _lastSavedPositionMs = -1;

      controller.addListener(() {
        if (!mounted || token != _initToken) return;

        final value = controller.value;

        if (value.hasError) {
          final msg = value.errorDescription ?? '视频播放失败';

          AppLogger.instance.log(
            '视频播放器错误: $msg | url=${widget.url}',
            tag: 'PLAYER_ERROR',
          );

          /// 关键改动：
          /// 只要播放器本身报错，直接 fail-fast
          if (!_playbackFailed) {
            _failFast(msg, value.errorDescription);
          }
          return;
        }

        final isPlaying = value.isPlaying;
        if (isPlaying != _wasPlayingLastTick) {
          _wasPlayingLastTick = isPlaying;

          if (mounted) {
            setState(() {
              if (!isPlaying) {
                _isBuffering = value.isBuffering;
              }
            });
          }

          if (isPlaying) {
            _scheduleHistoryTimer();
            _scheduleHideControlsFromChewie();
          } else {
            _historyTimer?.cancel();
            _historyTimer = null;
          }
        }

        final buffering = value.isBuffering;
        if (buffering != _isBuffering) {
          if (mounted) {
            setState(() {
              _isBuffering = buffering;
            });
          } else {
            _isBuffering = buffering;
          }
        }
      });

      AppLogger.instance.log('开始初始化底层播放器...', tag: 'PLAYER');

      /// 这里修复了你刚才报错的点：
      /// 不再对可空 Future<void>? 调用 timeout
      /// 改成局部非空变量 initFuture
      final initFuture = controller.initialize();

      await initFuture.timeout(_initTimeout);

      if (!mounted || token != _initToken) {
        await controller.dispose();
        return;
      }

      if (controller.value.hasError) {
        final msg = controller.value.errorDescription ?? '视频初始化失败';
        await controller.dispose();
        _failFast(msg, controller.value.errorDescription);
        return;
      }

      if (widget.initialPosition > 0) {
        final initial = Duration(milliseconds: widget.initialPosition);
        final safeInitial = controller.value.duration > initial
            ? initial
            : controller.value.duration;

        if (safeInitial > Duration.zero) {
          await controller.seekTo(safeInitial);
          AppLogger.instance.log(
            '已跳转到历史位置：${safeInitial.inMilliseconds}ms',
            tag: 'PLAYER',
          );
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
        aspectRatio: controller.value.aspectRatio > 0
            ? controller.value.aspectRatio
            : 16 / 9,
      );

      if (!mounted || token != _initToken) {
        _disposePlayer();
        return;
      }

      setState(() {
        _isError = false;
        _errorMessage = null;
        _isBuffering = false;
      });

      _scheduleHistoryTimer();
    } on TimeoutException catch (e) {
      _disposePlayer();
      _failFast('播放器初始化超时，请切换线路或稍后重试', e);
    } catch (e, st) {
      AppLogger.instance.logError(e, st, 'PLAYER');
      _disposePlayer();

      if (mounted && token == _initToken) {
        _failFast('视频播放失败，请切换线路', e);
      }
    }
  }

  void _scheduleHistoryTimer() {
    _historyTimer?.cancel();
    _historyTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _saveCurrentHistory(),
    );
  }

  void _scheduleHideControlsFromChewie() {
    final chewie = _chewieController;
    if (chewie == null) return;

    // 保留接口位，具体隐藏逻辑放在自定义 controls 里
  }

  void _failFast(String msg, [Object? debugObject]) {
    if (_playbackFailed) return;
    _playbackFailed = true;

    AppLogger.instance.log('异常阻断: $msg', tag: 'PLAYER');

    if (debugObject != null && kDebugMode) {
      AppLogger.instance.log('debug: $debugObject', tag: 'PLAYER');
    }

    if (!mounted) return;

    setState(() {
      _isError = true;
      _errorMessage = msg;
      _isBuffering = false;
    });

    _historyTimer?.cancel();
    _historyTimer = null;

    _disposePlayer();
  }

  Future<void> _retry() async {
    _saveCurrentHistory(force: true);
    _disposePlayer();

    if (!mounted) return;

    setState(() {
      _isError = false;
      _errorMessage = null;
      _isBuffering = true;
      _playbackFailed = false;
    });

    await _initPlayer();
  }

  void _saveCurrentHistory({bool force = false}) {
    final controller = _videoPlayerController;
    if (!mounted || controller == null) return;
    if (!controller.value.isInitialized) return;

    final posMs = controller.value.position.inMilliseconds;
    final durMs = controller.value.duration.inMilliseconds;

    if (posMs <= 0 || durMs <= 0 || widget.vodId.isEmpty) return;

    if (!force && _lastSavedPositionMs >= 0) {
      final delta = (posMs - _lastSavedPositionMs).abs();
      if (delta < 3000) {
        return;
      }
    }

    _lastSavedPositionMs = posMs;

    try {
      if (kDebugMode || widget.showDebugInfo) {
        AppLogger.instance.log(
          '保存历史: vodId=${widget.vodId}, pos=$posMs, dur=$durMs, episode=${widget.episodeName}',
          tag: 'HISTORY',
        );
      }

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

  void _disposePlayer() {
    _historyTimer?.cancel();
    _historyTimer = null;

    _chewieController?.dispose();
    _chewieController = null;

    _videoPlayerController?.dispose();
    _videoPlayerController = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveCurrentHistory(force: true);
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

    final controller = _videoPlayerController;
    final chewieController = _chewieController;

    if (controller == null ||
        chewieController == null ||
        !controller.value.isInitialized) {
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
            Chewie(controller: chewieController),
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
                '拼命缓冲中…',
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

class _CustomVideoControlsState extends State<_CustomVideoControls> {
  ChewieController? _chewieController;
  late VideoPlayerController _controller;

  bool _showControls = true;
  bool _isLocked = false;
  bool _isSpeeding = false;
  bool _isScrubbing = false;

  bool _wasPlayingBeforeScrub = false;

  Timer? _hideTimer;

  Duration _baseScrubPosition = Duration.zero;
  Duration _currentScrubPosition = Duration.zero;

  double _playbackSpeed = 1.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _chewieController = ChewieController.of(context);
    _controller = _chewieController!.videoPlayerController;

    if (_controller.value.isPlaying) {
      _startHideTimer();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (_controller.value.isPlaying && !_isSpeeding && !_isScrubbing) {
        setState(() => _showControls = false);
      }
    });
  }

  void _togglePlayPause() {
    if (_controller.value.isPlaying) {
      _controller.pause();
      setState(() {
        _showControls = true;
      });
      _hideTimer?.cancel();
    } else {
      _controller.play();
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

  void _skipTime(Duration offset) {
    final duration = _controller.value.duration;
    final newPos = _controller.value.position + offset;

    final clampedPos = newPos < Duration.zero
        ? Duration.zero
        : (newPos > duration ? duration : newPos);

    _controller.seekTo(clampedPos);
    _startHideTimer();
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (_isLocked) return;

    _baseScrubPosition = _controller.value.position;
    _currentScrubPosition = _baseScrubPosition;
    _wasPlayingBeforeScrub = _controller.value.isPlaying;

    if (_controller.value.isPlaying) {
      _controller.pause();
    }

    setState(() {
      _isScrubbing = true;
      _showControls = true;
    });

    _hideTimer?.cancel();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_isLocked || !_isScrubbing) return;

    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth <= 0) return;

    // 保留原本的“左右滑动调进度”逻辑：
    // 横向拖动一整屏约等于 300 秒
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

    setState(() {
      _currentScrubPosition = newPosition;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_isLocked || !_isScrubbing) return;

    _controller.seekTo(_currentScrubPosition);

    setState(() {
      _isScrubbing = false;
      _showControls = true;
    });

    if (_wasPlayingBeforeScrub) {
      _controller.play();
    }

    _startHideTimer();
  }

  Future<void> _setSpeed(double speed) async {
    await _controller.setPlaybackSpeed(speed);

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
                        label: Text('${speed}x'),
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

  String _bottomStateText() {
    final state = _controller.value.isPlaying ? '播放中' : '已暂停';
    final buffering = _controller.value.isBuffering ? '缓冲中' : '正常';
    final speed = _playbackSpeed;

    return '$state · $buffering · ${speed.toStringAsFixed(speed.truncateToDouble() == speed ? 0 : 2)}x';
  }

  @override
  Widget build(BuildContext context) {
    if (_chewieController == null) return const SizedBox.shrink();

    final controlsVisible =
        _showControls || !_controller.value.isPlaying || _isScrubbing || _isLocked;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            onHorizontalDragStart: _onHorizontalDragStart,
            onHorizontalDragUpdate: _onHorizontalDragUpdate,
            onHorizontalDragEnd: _onHorizontalDragEnd,
          ),
        ),

        Positioned(
          left: 10,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: false,
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

        if (controlsVisible)
          IgnorePointer(
            ignoring: false,
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
                          if (_chewieController!.isFullScreen)
                            IconButton(
                              icon: const Icon(
                                Icons.fullscreen_exit_rounded,
                                color: Colors.white,
                              ),
                              onPressed: () =>
                                  _chewieController!.toggleFullScreen(),
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
                              _controller.value.isPlaying
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
                                  _controller.value.isPlaying
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
                              TextButton(
                                onPressed: _showSpeedSheet,
                                child: Text(
                                  '${_playbackSpeed.toStringAsFixed(_playbackSpeed.truncateToDouble() == _playbackSpeed ? 0 : 2)}x',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
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