import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_back_button.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/remote_storage/presentation/remote_storage_player_page.dart';

/// 音乐入口页：输入音频 URL → 下载到本地 → 交给 remote_storage 的播放页。
///
/// 这是 `docs/music_area_entry_plan.md` 里「阶段 1（在线下载 + 播放）」的实现，
/// 播放能力全部复用 remote_storage，不新写播放器。
/// 文件名与类名沿用 `MusicPlaceholderPage`：仓库里已有测试与入口按这个名字引用，
/// 改名的收益（好看）小于它带来的全仓改动面。
class MusicPlaceholderPage extends StatefulWidget {
  const MusicPlaceholderPage({super.key});

  @override
  State<MusicPlaceholderPage> createState() => _MusicPlaceholderPageState();
}

class _MusicPlaceholderPageState extends State<MusicPlaceholderPage> {
  // 默认音频：部署在 box.hpa888.top 同域，Web/App 均可访问，无 CORS 问题。
  // 备选公开源（App 可用，Web 会 CORS 拦截）：
  // https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3
  final _urlController = TextEditingController(
    text:
        'https://box.hpa888.top/updates/box/android/test-music/test-tone-440hz.mp3',
  );
  bool _busy = false;
  double _progress = 0;
  String? _status;

  /// 本次下载落下的临时文件，离开页面时删掉。
  ///
  /// 音频动辄几 MB～几十 MB，而下载目录是**临时目录根**、没有任何清理入口
  /// （设置页的「清理缓存」只管 `comic_online_images` 与 `box_downloads`）。
  File? _lastTempFile;

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // 已删 / 被占用：离开页面时不该因为清理失败而报错。
    }
  }

  @override
  void dispose() {
    // TextEditingController 不 dispose 就是一条泄漏的监听链；
    // 临时音频不删则每播一首就在临时目录里留一份。
    _urlController.dispose();
    final tmp = _lastTempFile;
    _lastTempFile = null;
    if (tmp != null) {
      unawaited(_deleteQuietly(tmp));
    }
    super.dispose();
  }

  Future<void> _downloadAndPlay() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _busy = true;
      _progress = 0;
      _status = '下载中...';
    });
    try {
      final entry = await _buildEntry(url);

      if (kIsWeb) {
        // Web 没有本地文件系统，path_provider 也不支持 Web，所以不落盘。
        // 直接走网络 URL 播放；注意浏览器会按同源策略拦截跨域音频请求。
        // 本页默认 URL 与 Web 部署同域，可避开 CORS。
        await _pushPlayer(url, entry, localPath: null);
        return;
      }

      final file = await _downloadToLocal(url, entry);
      await _pushPlayer(url, entry, localPath: file.path);
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _status = '错误: $e\n\n堆栈:\n$st');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 构造一个能被 [RemoteStoragePlayerPage] 识别的 entry。
  Future<RemoteStorageEntry> _buildEntry(String url) async {
    final uri = Uri.parse(url);
    final name = uri.pathSegments.isNotEmpty
        ? uri.pathSegments.last
        : 'audio.mp3';
    final ext = name.contains('.')
        ? name.substring(name.lastIndexOf('.'))
        : '.mp3';
    final safeName = 'music_${DateTime.now().millisecondsSinceEpoch}$ext';
    return RemoteStorageEntry(
      name: safeName,
      path: '/$safeName',
      isDirectory: false,
      size: 0,
    );
  }

  /// App 端：把音频下载到临时目录并返回本地文件。
  Future<File> _downloadToLocal(String url, RemoteStorageEntry entry) async {
    final tmpDir = await getTemporaryDirectory();
    final file = File('${tmpDir.path}/${entry.name}');

    // 裸 Dio() 没有任何超时：站点挂住时用户会一直停在「下载中…」，只能杀进程。
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    await dio.download(
      url,
      file.path,
      onReceiveProgress: (received, total) {
        if (!mounted) return;
        if (total <= 0) return;
        setState(() => _progress = received / total);
      },
    );

    if (!mounted) throw StateError('页面已离开');
    _lastTempFile = file;
    setState(() => _status = '下载完成，准备播放');
    return file;
  }

  /// 统一跳转到现有播放器。
  ///
  /// - App: [localPath] 非空，播放本地文件。
  /// - Web: [localPath] 为空，[RemoteStoragePlayerPage] 会自动走网络 URL 流。
  Future<void> _pushPlayer(
    String url,
    RemoteStorageEntry entry, {
    required String? localPath,
  }) async {
    final uri = Uri.parse(url);
    final account = RemoteStorageAccount(
      id: 'music-stream',
      label: '音乐在线流',
      baseUrl: uri.hasScheme ? '${uri.scheme}://${uri.host}/' : '',
      username: '',
      password: '',
    );

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RemoteStoragePlayerPage(
          account: account,
          entry: entry,
          localPath: localPath,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: AppBackButton(onPressed: () => Navigator.pop(context)),
        title: const Text('音乐'),
        backgroundColor: AppTokens.surface,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: '音频 URL',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (_busy)
              LinearProgressIndicator(value: _progress > 0 ? _progress : null),
            if (_status != null)
              Text(_status!, style: TextStyle(color: AppTokens.textSecondary)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _downloadAndPlay,
              child: const Text('下载并播放'),
            ),
          ],
        ),
      ),
    );
  }
}
