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

  /// 推荐传入详情页或来源页地址，播放器会自动补 Referer / Origin
  final String? referer;

  /// 额外请求头，例如 Cookie
  final Map<String, String>? httpHeaders;

  /// 自定义 UA
  final String userAgent;

  /// 是否显示调试信息
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
    // Web 端不能自定义 User-Agent / Referer / Origin / Cookie 等危险请求头
    if (kIsWeb) {
      return const {};
    }

    final headers = <String, String>{};

    final ua = widget.userAgent.trim();
    if (ua.isNotEmpty) {
      headers['User-Agent'] = ua;
    }

    final referer = widget.referer?.trim() ?? '';
    if (referer.isNotEmpty) {
      headers['Referer'] = referer;

      final uri = Uri.tryParse(referer);
      if (uri != null && uri.hasScheme) {
        final origin = uri.origin;
        if (origin.isNotEmpty && origin.toLowerCase() != 'null') {
          headers['Origin'] = origin;
        }
      }
    }

    headers['Accept'] = '*/*';
    headers['Connection'] = 'keep-alive';

    if (widget.httpHeaders != null && widget.httpHeaders!.isNotEmpty) {
      headers.addAll(widget.httpHeaders!);
    }

    return headers;
  }

  void _logBlock(String title, String content, {String tag = 'PLAYER'}) {
    AppLogger.instance.logBlock(title, content, tag: tag);
  }

  bool _looksLikeHls(Uri uri) {
    final path = uri.path.toLowerCase();
    return path.endsWith('.m3u8') || path.contains('.m3u8?');
  }

  String? _extractFirstVariantUrlFromM3u8(String body) {
    final lines = const LineSplitter().convert(body);

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      if (line.startsWith('#EXT-X-STREAM-INF')) {
        // 找到它下面的第一个非注释、非空行
        for (var j = i + 1; j < lines.length; j++) {
          final next = lines[j].trim();
          if (next.isEmpty) continue;
          if (next.startsWith('#')) continue;
          return next;
        }
      }
    }

    return null;
  }

  String? _extractFirstMediaSegmentFromM3u8(String body) {
    final lines = const LineSplitter().convert(body);

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) continue;
      return line;
    }

    return null;
  }

  Future<Uri> _resolvePlayableHlsUri(Uri uri) async {
    // 非 HLS 地址直接返回
    if (!_looksLikeHls(uri)) {
      return uri;
    }

    final headers = _buildRequestHeaders();
    Uri current = uri;

    // 最多递归 3 层：
    // master.m3u8 -> variant.m3u8 -> maybe another variant.m3u8
    for (var depth = 0; depth < 3; depth++) {
      try {
        final res = await http.get(
          current,
          headers: headers,
        );

        final bodyText = utf8.decode(
          res.bodyBytes,
          allowMalformed: true,
        );

        final preview = bodyText.length > 300
            ? bodyText.substring(0, 300)
            : bodyText;

        _logBlock(
          'HLS 解析层级 $depth',
          'uri: $current\n'
              'statusCode: ${res.statusCode}\n'
              'content-type: ${res.headers['content-type']}\n'
              'location: ${res.headers['location']}\n'
              'body preview:\n$preview',
        );

        // 请求失败就直接返回当前层，避免死循环
        if (res.statusCode != 200) {
          return current;
        }

        final nextVariant = _extractFirstVariantUrlFromM3u8(bodyText);

        // 如果不是 master playlist，说明已经到了最终 media playlist
        if (nextVariant == null) {
          final firstSegment = _extractFirstMediaSegmentFromM3u8(bodyText);

          if (firstSegment != null) {
            final segmentUri = current.resolve(firstSegment);
            AppLogger.instance.log(
              '已解析为 media playlist，首个分片: $segmentUri',
              tag: 'PLAYER',
            );
          }

          return current;
        }

        final nextUri = current.resolve(nextVariant);

        AppLogger.instance.log(
          'HLS master -> variant: $current -> $nextUri',
          tag: 'PLAYER',
        );

        current = nextUri;
      } catch (e, st) {
        AppLogger.instance.logError(e, st, 'PLAYER');
        return current;
      }
    }

    return current;
  }

  VideoPlayerController _createController(Uri uri) {
    if (kIsWeb) {
      return VideoPlayerController.networkUrl(
        uri,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
    }

    final headers = _buildRequestHeaders();

    return VideoPlayerController.networkUrl(
      uri,
      httpHeaders: headers,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
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
      if (!mounted) return;
      setState(() {
        _isError = true;
        _errorMessage = '播放地址为空';
      });
      AppLogger.instance.log('播放地址为空', tag: 'PLAYER');
      return;
    }

    var normalizedUrl = rawUrl.replaceAll('\\', '');

    if (normalizedUrl.startsWith('//')) {
      normalizedUrl = 'https:$normalizedUrl';
    }

    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null || !uri.hasScheme) {
      if (!mounted) return;
      setState(() {
        _isError = true;
        _errorMessage = '播放地址格式不正确';
      });
      AppLogger.instance.log('播放地址格式不正确: $normalizedUrl', tag: 'PLAYER');
      return;
    }

    try {
      AppLogger.instance.log(
        '原始播放地址: $uri',
        tag: 'PLAYER',
      );

      final playableUri = await _resolvePlayableHlsUri(uri);

      AppLogger.instance.log(
        '最终用于播放的 URI: $playableUri',
        tag: 'PLAYER',
      );

      final controller = _createController(playableUri);
      _videoPlayerController = controller;

      controller.addListener(() {
        if (!mounted || token != _initToken) return;

        final value = controller.value;

        if (value.hasError) {
          final msg = value.errorDescription ?? '视频播放失败';
          AppLogger.instance.log('视频播放器错误: $msg', tag: 'PLAYER');

          if (mounted) {
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

      AppLogger.instance.log('开始初始化播放器...', tag: 'PLAYER');
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
        aspectRatio: controller.value.aspectRatio > 0
            ? controller.value.aspectRatio
            : 16 / 9,
        materialProgressColors: ChewieProgressColors(
          playedColor: Theme.of(context).colorScheme.primary,
          handleColor: Theme.of(context).colorScheme.primary,
          backgroundColor: Colors.grey.withOpacity(0.5),
          bufferedColor: Colors.white.withOpacity(0.5),
        ),
        errorBuilder: (context, errorMessage) {
          return _buildErrorOverlay(
            errorMessage: errorMessage.isNotEmpty
                ? errorMessage
                : '视频加载失败，请切换选集或重试',
          );
        },
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
          _errorMessage = '播放器初始化失败：$e';
        });
      }
    }
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
    return Container(
      color: Colors.black,
      child: _buildPlayerContent(),
    );
  }

  Widget _buildPlayerContent() {
    if (_isError) {
      return _buildErrorOverlay(
        errorMessage: _errorMessage ?? '视频资源失效',
      );
    }

    if (_videoPlayerController == null ||
        _chewieController == null ||
        !_videoPlayerController!.value.isInitialized) {
      return _buildLoadingOverlay();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Chewie(controller: _chewieController!),
        if (_isBuffering) _buildBufferingOverlay(),
        if (widget.showDebugInfo) _buildDebugOverlay(),
      ],
    );
  }

  Widget _buildLoadingOverlay() {
    return const Center(
      child: CircularProgressIndicator(color: Colors.white),
    );
  }

  Widget _buildBufferingOverlay() {
    return IgnorePointer(
      child: Container(
        color: Colors.transparent,
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.55),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 10),
              Text(
                '缓冲中…',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorOverlay({required String errorMessage}) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.white,
            size: 46,
          ),
          const SizedBox(height: 10),
          Text(
            errorMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重试播放'),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugOverlay() {
    final controller = _videoPlayerController;
    final pos = controller?.value.position.inSeconds ?? 0;
    final dur = controller?.value.duration.inSeconds ?? 0;

    return Positioned(
      left: 12,
      top: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.45),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'pos: $pos s / $dur s',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}