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
import '../data/playback_progress_store.dart';
import '../domain/playback_progress.dart';
import '../domain/remote_storage_models.dart';
import '../domain/subtitle_support.dart';

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

  /// 续播（B3）：定时记录位置的节拍。5 秒是"熄屏/被杀也不丢太多"与
  /// "别每帧都写盘"之间的折中。
  static const Duration _progressTick = Duration(seconds: 5);
  static const RemotePlaybackProgressStore _progressStore =
      RemotePlaybackProgressStore();
  Timer? _progressTimer;

  /// 字幕（B3）：候选列表（同目录 .srt/.vtt，同名的排前面）与当前生效项。
  List<RemoteStorageEntry> _subtitleCandidates = const [];
  String? _activeSubtitleName;
  bool _subtitleBusy = false;

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
      // 续播（B3）：放在 ready 之后，避免首帧还没出来就被 seek 打断。
      await _applyResume(controller);
      _startProgressTicker();
      // 字幕（B3）：列目录是附加请求，别挡住播放。
      unawaited(_detectSubtitles());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is RemoteStorageException ? e.message : '$e';
      });
    }
  }

  // -------------------------------------------------------------- 续播（B3）

  /// 读取上次位置并 seek。位置不可信（未到阈值 / 已看完）时不打扰用户。
  Future<void> _applyResume(VideoPlayerController controller) async {
    try {
      final saved = await _progressStore.positionFor(
        widget.account,
        widget.entry.path,
      );
      if (saved == null || !mounted) return;
      if (!shouldResumePlayback(saved, controller.value.duration)) return;
      await controller.seekTo(saved);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已从 ${formatPlaybackPosition(saved)} 继续播放'),
          action: SnackBarAction(
            label: '从头播',
            onPressed: () {
              unawaited(_progressStore.clear(widget.account, widget.entry.path));
              unawaited(controller.seekTo(Duration.zero));
            },
          ),
        ),
      );
    } catch (_) {
      // 进度是附加项：读不到就不续播，绝不因此挡住播放。
    }
  }

  /// 定时记录位置。[RemotePlaybackProgressStore.save] 自己会处理
  /// "太短"与"已看完"（清记录）两种情况，这里不用重复判断。
  void _startProgressTicker() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(
      _progressTick,
      (_) => unawaited(_saveProgress()),
    );
  }

  Future<void> _saveProgress() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await _progressStore.save(
        widget.account,
        widget.entry.path,
        position: controller.value.position,
        duration: controller.value.duration,
      );
    } catch (_) {
      // 写盘失败（空间/权限）不该让播放页报错。
    }
  }

  // -------------------------------------------------------------- 字幕（B3）

  /// 列一次同目录找候选字幕；有同名的就直接挂上。
  Future<void> _detectSubtitles() async {
    if (_isLocal) return; // 本地兜底播放没有远端目录上下文
    try {
      final entries = await remoteStorageService().list(
        widget.account,
        parentRemotePath(widget.entry.path),
      );
      if (!mounted) return;
      final candidates = subtitleCandidates(entries, widget.entry.name);
      setState(() => _subtitleCandidates = candidates);
      final preset = defaultSubtitleFor(candidates, widget.entry.name);
      if (preset != null) await _loadSubtitle(preset);
    } catch (_) {
      // 字幕是附加项：列目录失败就当没有字幕。
    }
  }

  /// 加载 / 切换字幕；[entry] 为 null 表示关闭。
  Future<void> _loadSubtitle(RemoteStorageEntry? entry) async {
    final controller = _controller;
    if (controller == null) return;
    setState(() => _subtitleBusy = true);
    try {
      if (entry == null) {
        await controller.setClosedCaptionFile(null);
        if (mounted) setState(() => _activeSubtitleName = null);
        return;
      }
      final payload = await remoteStorageService().readTextPreview(
        widget.account,
        entry.path,
      );
      final text = payload.textOrNull;
      if (text == null || text.isEmpty) {
        throw const RemoteStorageException(
          RemoteStorageError.unknown,
          '字幕文件为空或超出预览上限',
        );
      }
      final cues = parseSubtitleText(text, webVtt: isWebVttFileName(entry.name));
      await controller.setClosedCaptionFile(
        Future<ClosedCaptionFile>.value(_SubtitleFile(cues)),
      );
      if (!mounted) return;
      setState(() => _activeSubtitleName = entry.name);
      if (cues.isEmpty) {
        // 解析出 0 条：最常见的原因不是"文件坏"，而是编码不是 UTF-8（老港台片常见 Big5）。
        _hint('这条字幕没解析出内容（可能是非 UTF-8 编码）');
      } else if (payload.truncated) {
        _hint('字幕超过 512KB，只加载了前半部分');
      }
    } catch (e) {
      _hint('字幕加载失败：${e is RemoteStorageException ? e.message : e}');
    } finally {
      if (mounted) setState(() => _subtitleBusy = false);
    }
  }

  void _hint(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// CC 菜单：候选字幕 + 关闭。返回下标，-1 = 关闭，null = 取消。
  Future<void> _pickSubtitle() async {
    if (_subtitleCandidates.isEmpty && _activeSubtitleName == null) {
      _hint('同目录没有 .srt / .vtt 字幕文件');
      return;
    }
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              dense: true,
              title: Text(
                '字幕（${_subtitleCandidates.length} 个候选）',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              leading: Icon(
                _activeSubtitleName == null
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
              ),
              title: const Text('关闭字幕'),
              onTap: () => Navigator.pop(ctx, -1),
            ),
            for (var i = 0; i < _subtitleCandidates.length; i++)
              ListTile(
                leading: Icon(
                  _activeSubtitleName == _subtitleCandidates[i].name
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                ),
                title: Text(
                  _subtitleCandidates[i].name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: subtitleMatchesVideo(
                  _subtitleCandidates[i].name,
                  widget.entry.name,
                )
                    ? const Text('与视频同名')
                    : null,
                onTap: () => Navigator.pop(ctx, i),
              ),
          ],
        ),
      ),
    );
    if (!mounted || picked == null) return;
    if (picked < 0) {
      await _loadSubtitle(null);
      return;
    }
    if (picked < _subtitleCandidates.length) {
      await _loadSubtitle(_subtitleCandidates[picked]);
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
    _progressTimer?.cancel();
    // 退出这一下要立刻落盘：等定时器可能已经来不及（用户直接返回或进程被杀）。
    unawaited(_saveProgress());
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
        actions: [
          // 本地兜底播放没有远端目录上下文，找不到候选字幕，索性不显示入口。
          if (!_isLocal)
            IconButton(
              tooltip: '字幕',
              onPressed: _subtitleBusy ? null : _pickSubtitle,
              icon: _subtitleBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white70,
                      ),
                    )
                  : Icon(
                      _activeSubtitleName == null
                          ? Icons.subtitles_outlined
                          : Icons.subtitles_rounded,
                    ),
            ),
        ],
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

/// 把解析出的字幕适配成 video_player 需要的 [ClosedCaptionFile]。
///
/// video_player 只导出了抽象类与 [Caption]，自带解析器没导出，所以适配层放在这里，
/// 解析逻辑留在 domain（可单测）。
class _SubtitleFile extends ClosedCaptionFile {
  _SubtitleFile(List<ParsedSubtitleCue> cues)
    : captions = <Caption>[
        for (final cue in cues)
          Caption(
            number: cue.index,
            start: cue.start,
            end: cue.end,
            text: cue.text,
          ),
      ];

  @override
  final List<Caption> captions;
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
