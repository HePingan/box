import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/features/music/data/music_favorites_store.dart';
import 'package:box/design_system/widgets/app_back_button.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/remote_storage/presentation/remote_storage_player_page.dart';

/// 音乐入口页。两种来源，同一个播放器：
///
/// 1. **在线音频**（阶段 1）：贴一个音频 URL → 下载到本地 → 交给 remote_storage 播放页；
/// 2. **本地文件**（阶段 3）：用系统文件选择器挑音频 → 直接播。
///
/// 播放能力 100% 复用 remote_storage（video_player + chewie + 中继），不新写播放器。
///
/// 为什么阶段 3 用**文件选择器**而不是扫描整个存储：
/// `docs/music_area_entry_plan.md` 原计划是 MediaStore 全盘扫描，但那需要
/// `READ_MEDIA_AUDIO`（Android 13+）/ `READ_EXTERNAL_STORAGE`（更早版本）的运行时权限，
/// 而这个仓库**没有任何权限申请插件**（所有现有权限都是安装时授权或系统 Intent 触发）。
/// 走 SAF 文件选择器拿 URI 则**零权限**：用户挑哪个文件，App 才看得到哪个文件 ——
/// 这既是 Android 现在推荐的做法，也省掉一次"申请权限被拒"的困惑。
/// 代价是不能"打开就列出我手机里所有歌"，需要用户主动挑一次。
///
/// ⚠ 另一个容易被忽略的事实：`file_picker` 的 Android 实现会把选中的文件**复制**到
/// `cacheDir/file_picker/<时间戳>/`，Dart 侧拿到的 `path` 指向那份副本，而不是用户原件。
/// 所以这里会再复制一份到我们自己的临时目录（系统清插件缓存时正在播的音频不会断），
/// 并在复制完成后清掉插件那份（否则每挑一次就多一份，谁也清不到）。
///
/// 文件名与类名沿用 `MusicPlaceholderPage`：仓库里已有测试与入口按这个名字引用，
/// 改名的收益（好看）小于它带来的全仓改动面。
class MusicPlaceholderPage extends StatefulWidget {
  const MusicPlaceholderPage({
    super.key,
    this.pickAudioPath,
    this.initialAudioUrl = '',
    this.initialTitle = '',
    this.autoPlay = false,
    this.loop = false,
  });

  /// 本地音频选择口的注入点（测试用）。
  ///
  /// 生产不传即走系统文件选择器。widget 测试里真调 FilePicker 会碰平台通道
  /// （纯 test 环境没有插件 → MissingPluginException），所以留这个口子。
  final Future<String?> Function()? pickAudioPath;

  /// 插件/market 条目预填的音频地址（`openMusic` 的 payload，见 MusicLaunchSpec）。
  /// 非空时会覆盖输入框默认值。
  final String initialAudioUrl;

  /// 预填条目的显示名（白噪音、睡眠电台之类），只用于页面提示，不改元数据。
  final String initialTitle;

  /// 是否进来就自动下载并播放（插件声明的 `autoplay`）。
  ///
  /// 默认 false：普通入口是给人手动贴链接的，自动播会吓人。
  final bool autoPlay;

  /// 交给播放器的 `looping`（白噪音/电台需要单曲循环，否则 5 分钟就停）。
  final bool loop;

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

  final MusicFavoritesStore _favorites = MusicFavoritesStore();

  /// 当前输入框里的 URL 是否已收藏（只用于按钮显示"收藏/已收藏"）。
  bool _favorited = false;

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
  void initState() {
    super.initState();
    final preset = widget.initialAudioUrl.trim();
    if (preset.isNotEmpty) {
      _urlController.text = preset;
    }
    // 进来先看一眼默认 URL 是否已收藏，按钮上直接显示「已收藏」。
    unawaited(_refreshFavorited());
    // 插件声明了 autoplay：等首帧之后再落 URL 下载播放，
    // 避免在 build 期触发 setState / 弹页面。
    if (preset.isNotEmpty && widget.autoPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _busy) return;
        unawaited(_downloadAndPlay());
      });
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

  Future<void> _refreshFavorited() async {
    try {
      final has = await _favorites.contains(_urlController.text.trim());
      if (mounted) setState(() => _favorited = has);
    } catch (_) {
      // 查不到就当没收藏，不影响其它功能
    }
  }

  /// 把输入框里那条 URL 加入音乐收藏。
  ///
  /// 只收藏 URL 与显示名：音乐区没有歌单/元数据概念，存多了都是猜的。
  Future<void> _favoriteCurrentUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _status = '先填一个音频 URL 再收藏');
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      setState(() => _status = '只能收藏 http(s) 地址');
      return;
    }

    try {
      final added = await _favorites.add(url: url);
      if (!mounted) return;
      setState(() {
        _favorited = true;
        _status = added
            ? '已加入收藏，可在「内容 → 收藏库 → 音乐收藏」里找到'
            : '这条已经在收藏里了';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = '收藏失败：$e');
    }
  }

  /// 挑一个本地音频并播放（阶段 3）。
  ///
  /// 走 SAF 文件选择器：**不需要任何存储权限** —— 用户挑了哪个文件，App 才拿到
  /// 那个文件的访问权。这与"扫描全盘音频"是两条路，后者要 READ_MEDIA_AUDIO。
  Future<void> _pickLocalAndPlay() async {
    setState(() {
      _busy = true;
      _status = '选择中...';
    });
    try {
      final picker = widget.pickAudioPath ?? _defaultPickAudioPath;
      final path = await picker();
      if (!mounted) return;
      if (path == null || path.isEmpty) {
        // 用户取消：不是错误，别弹红字。
        setState(() {
          _busy = false;
          _status = null;
        });
        return;
      }

      final file = File(path);
      if (!await file.exists()) {
        setState(() {
          _busy = false;
          _status = '选中的文件读不到了（可能已被移动或删除）';
        });
        return;
      }

      final name = path.split(Platform.pathSeparator).last;

      // ⚠ 这里拿到的 `path` **不是**用户的原文件：`file_picker` 的 Android 实现
      // 会把选中的文件复制到 `context.cacheDir/file_picker/<时间戳>/`，返回的是
      // 那份**缓存副本**（见 android_file_picker 的 FileUtils.getFileInfo）。
      // 两个后果都得处理：
      //   1. 缓存随时可能被系统清掉 —— 正在播的音频会断，所以复制一份到我们自己的
      //      目录再播（这也解释了为什么"不复制"是错的）；
      //   2. 每选一次就留一份副本 —— 播完就把插件缓存清掉，别让它越积越多。
      final owned = await _copyToOwnedDir(file, name);
      // 复制可能要几十毫秒到几秒（大文件/慢存储）：用户完全可能在这期间退出本页。
      if (!mounted) return;
      setState(() => _status = '准备播放 $name');
      await _pushPlayer(
        owned.path,
        _entryForName(name),
        localPath: owned.path,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = '打开本地音频失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 把插件给的缓存副本复制到我们自己的目录，返回那份文件。
  ///
  /// 为什么不直接播插件给的那份：那是 `cacheDir/file_picker/...` 下的临时副本，
  /// 系统在低存储时会整目录清理，播到一半断掉是必然发生的。我们自己的目录由
  /// 本页的 `dispose` 负责收尾（见 [_lastTempFile]）。
  ///
  /// 复制失败就退回原路径：能用总比不能用好，只是要接受"可能被系统清掉"。
  Future<File> _copyToOwnedDir(File source, String name) async {
    try {
      final tmpDir = await getTemporaryDirectory();
      final dir = Directory('${tmpDir.path}/music_local');
      if (!await dir.exists()) await dir.create(recursive: true);
      final ext = name.contains('.') ? name.substring(name.lastIndexOf('.')) : '';
      final target = File(
        '${dir.path}/picked_${DateTime.now().microsecondsSinceEpoch}$ext',
      );
      await source.copy(target.path);
      _lastTempFile = target;

      // 复制完就清掉插件那份（否则每挑一次就多一份，谁也清不到）。
      // 失败无所谓：下次挑文件时插件自己也会清。
      unawaited(_clearPickerCacheQuietly());
      return target;
    } catch (_) {
      return source;
    }
  }

  static Future<void> _clearPickerCacheQuietly() async {
    try {
      await FilePicker.clearTemporaryFiles();
    } catch (_) {
      // 清不掉不影响播放。
    }
  }

  /// 系统文件选择器：只列音频类扩展名。
  static Future<String?> _defaultPickAudioPath() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const [
        'mp3', 'flac', 'wav', 'aac', 'm4a', 'ogg', 'opus', 'wma', 'amr', 'ape',
      ],
    );
    return picked?.path;
  }

  /// 由文件名造一个 entry（播放页要求 entry 非空，哪怕播的是本地文件）。
  RemoteStorageEntry _entryForName(String name) {
    final ext = name.contains('.')
        ? name.substring(name.lastIndexOf('.'))
        : '.mp3';
    final safeName = 'local_${DateTime.now().millisecondsSinceEpoch}$ext';
    return RemoteStorageEntry(
      name: safeName,
      path: '/$safeName',
      isDirectory: false,
      size: 0,
    );
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
          looping: widget.loop,
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 本地文件（阶段 3）──
          _SectionTitle(title: '本地音频', icon: Icons.audio_file_outlined),
          const SizedBox(height: 8),
          Text(
            '从手机上挑一个音频文件播放。不需要给 App 存储权限 —— '
            '你选哪个文件，App 才看得到哪个。',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: AppTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickLocalAndPlay,
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('选择本地音频'),
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // ── 在线音频（阶段 1）──
          _SectionTitle(title: '在线音频', icon: Icons.language_rounded),
          const SizedBox(height: 8),
          Text(
            '贴一个音频链接，App 下载完再播放（不是在线流播）。'
            '仅用于你自己有权使用的音频。',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: AppTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: '音频 URL',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _downloadAndPlay,
                  child: const Text('下载并播放'),
                ),
              ),
              const SizedBox(width: 10),
              // 收藏是「内容页 → 收藏库 → 音乐收藏」的唯一入口。
              // 收藏的是这条 URL 本身（音乐区的能力就是「贴地址 → 播」）。
              OutlinedButton.icon(
                onPressed: _busy ? null : _favoriteCurrentUrl,
                icon: Icon(
                  _favorited ? Icons.bookmark_added : Icons.bookmark_add_outlined,
                  size: 18,
                ),
                label: Text(_favorited ? '已收藏' : '收藏'),
              ),
            ],
          ),

          if (_busy || _status != null) ...[
            const SizedBox(height: 20),
            if (_busy)
              LinearProgressIndicator(value: _progress > 0 ? _progress : null),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SelectableText(
                  _status!,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: AppTokens.textSecondary,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// 页面里的小节标题（本地 / 在线两类来源各一节，别混在一屏里）。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTokens.primaryBlue),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
