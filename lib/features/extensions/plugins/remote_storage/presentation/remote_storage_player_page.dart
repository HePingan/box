// 远程存储：视频 / 音频播放页（拍板 7「直连播」）。
//
// 通道判定（service.resolvePlayback）：
//  - https 且证书可信 → 播放器直连远端，附 Basic 认证头；
//  - http 明文 / 自签证书 → 起 127.0.0.1 回环中继转发（原生播放器不受 NSC 限制）。
// 播放失败（编解码不支持等）→ 提供「下载后播放」兜底。

import 'dart:async';
import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../application/playback_relay.dart';
import '../application/remote_storage_service.dart';
import '../application/transfer_queue.dart';
import '../domain/remote_storage_models.dart';

class RemoteStoragePlayerPage extends StatefulWidget {
  const RemoteStoragePlayerPage({
    super.key,
    required this.account,
    required this.entry,
    this.localPath,
  });

  final RemoteStorageAccount account;
  final RemoteStorageEntry entry;

  /// 非空时直接播放本地文件（下载后播放兜底路径）。
  final String? localPath;

  @override
  State<RemoteStoragePlayerPage> createState() =>
      _RemoteStoragePlayerPageState();
}

class _RemoteStoragePlayerPageState extends State<RemoteStoragePlayerPage> {
  VideoPlayerController? _controller;
  ChewieController? _chewie;
  PlaybackRelay? _relay;
  bool _ready = false;
  String _error = '';
  bool _fallbackQueued = false;

  bool get _isLocal => (widget.localPath ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final service = remoteStorageService();
      VideoPlayerController controller;
      if (_isLocal) {
        controller = VideoPlayerController.file(File(widget.localPath!));
      } else {
        final plan = service.resolvePlayback(widget.account, widget.entry);
        if (plan.needsRelay) {
          final relay = await service.openRelay(widget.account, widget.entry);
          if (!mounted) {
            unawaited(relay.close());
            return;
          }
          _relay = relay;
          controller = VideoPlayerController.networkUrl(Uri.parse(relay.url));
        } else {
          controller = VideoPlayerController.networkUrl(
            plan.directUri,
            httpHeaders: plan.headers,
          );
        }
      }
      _controller = controller;
      await controller.initialize();
      if (!mounted) {
        unawaited(controller.dispose());
        return;
      }
      final ratio = controller.value.aspectRatio;
      _chewie = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        looping: false,
        aspectRatio: ratio > 0 ? ratio : 16 / 9,
        errorBuilder: (context, message) => _PlayErrorView(
          message: message,
          onFallback: _isLocal ? null : _downloadAndPlay,
        ),
      );
      setState(() => _ready = true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is RemoteStorageException ? e.message : '$e';
      });
    }
  }

  /// 播放失败兜底：入队下载，完成后用本地文件替换本页。
  void _downloadAndPlay() {
    if (_fallbackQueued) return;
    _fallbackQueued = true;
    final service = remoteStorageService();
    transferQueue().enqueue(
      kind: TransferKind.download,
      title: widget.entry.name,
      subtitle: '${widget.account.label.isEmpty ? widget.account.displayHost : widget.account.label} · 下载后播放',
      totalBytes: widget.entry.size ?? -1,
      runner: (cancel, onProgress) => service.download(
        widget.account,
        remotePath: widget.entry.path,
        fileName: widget.entry.name,
        onProgress: onProgress,
        cancel: cancel,
      ),
      onFinished: (task) {
        if (!mounted) return;
        if (task.status == TransferStatus.done && task.result is String) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => RemoteStoragePlayerPage(
                account: widget.account,
                entry: widget.entry,
                localPath: task.result! as String,
              ),
            ),
          );
        } else if (task.status == TransferStatus.failed) {
          setState(() => _fallbackQueued = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('下载失败：${task.errorMessage ?? ''}')),
          );
        }
      },
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已加入下载队列，完成后自动播放')),
    );
  }

  Future<void> _retry() async {
    setState(() {
      _ready = false;
      _error = '';
    });
    await _disposePlayers();
    await _start();
  }

  Future<void> _disposePlayers() async {
    _chewie?.dispose();
    _chewie = null;
    await _controller?.dispose();
    _controller = null;
    final relay = _relay;
    _relay = null;
    if (relay != null) {
      await relay.close();
    }
  }

  @override
  void dispose() {
    unawaited(_disposePlayers());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kind = remoteEntryKind(widget.entry);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.entry.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
      ),
      body: _buildBody(kind),
    );
  }

  Widget _buildBody(RemoteEntryKind kind) {
    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.white70, size: 48),
              const SizedBox(height: 12),
              Text(
                _error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: _retry,
                    child: const Text('重试'),
                  ),
                  if (!_isLocal) ...[
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _downloadAndPlay,
                      child: const Text('下载后播放'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
    }
    if (!_ready || _chewie == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white70),
            SizedBox(height: 14),
            Text('正在连接…', style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (kind == RemoteEntryKind.audio)
            const Icon(Icons.music_note_rounded, size: 72, color: Colors.white24),
          AspectRatio(
            aspectRatio: _chewie!.aspectRatio ?? 16 / 9,
            child: Chewie(controller: _chewie!),
          ),
        ],
      ),
    );
  }
}

class _PlayErrorView extends StatelessWidget {
  const _PlayErrorView({required this.message, this.onFallback});

  final String message;
  final VoidCallback? onFallback;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam_off_outlined, color: Colors.white70, size: 44),
          const SizedBox(height: 10),
          Text(
            '播放失败：$message',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          if (onFallback != null) ...[
            const SizedBox(height: 14),
            FilledButton(
              onPressed: onFallback,
              child: const Text('下载后播放'),
            ),
          ],
        ],
      ),
    );
  }
}
