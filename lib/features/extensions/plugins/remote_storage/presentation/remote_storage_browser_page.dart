// 远程存储：文件浏览页（列表 / 上传 / 下载 / 预览 / 播放入口）。
//
// 拍板 2：P0 仅上传（含浏览、下载、预览、播放），不做删除/重命名。
// 拍板 3：上传遇同名 → 默认跳过，可手动选择覆盖。
// 拍板 6：图片预览 20MB 上限、文本预览 512KB 前缀。
// 拍板 8：下载先落应用文档目录，导出到公共下载目录推 P1。

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../application/remote_storage_service.dart';
import '../application/transfer_queue.dart';
import '../domain/remote_storage_models.dart';
import 'remote_storage_player_page.dart';

// ------------------------------------------------------------- 页面级排序

/// 浏览页排序字段（名称 / 修改时间 / 大小）。
enum RemoteStorageSortField { name, modifiedTime, size }

/// 当前会话的排序字段（跨目录、跨 route 保持；不落盘）。
RemoteStorageSortField _sessionSortField = RemoteStorageSortField.modifiedTime;

/// 测试用：重置会话级浏览页状态（排序字段 + 滚动位置记忆）。
@visibleForTesting
void debugResetRemoteStorageBrowserSessionState() {
  _sessionSortField = RemoteStorageSortField.modifiedTime;
  _RemoteStorageBrowserPageState._savedScrollOffsets.clear();
}

String _sortFieldLabel(RemoteStorageSortField field) {
  switch (field) {
    case RemoteStorageSortField.name:
      return '名称';
    case RemoteStorageSortField.modifiedTime:
      return '修改时间（新在前）';
    case RemoteStorageSortField.size:
      return '大小（大在前）';
  }
}

/// 页面级排序：目录恒在最前；同一分组内按 [field] 排序。
///
/// - 名称：升序；
/// - 修改时间：新在前，时间缺失的排在最后；
/// - 大小：大在前，大小缺失的排在最后；
/// - 兜底：字段相等/缺失时按名称升序，保证顺序确定且与 client 基准序一致
///   （client 端固定「目录优先 + 名称升序」，见 webdav_client.dart）。
@visibleForTesting
List<RemoteStorageEntry> sortedRemoteStorageEntries(
  List<RemoteStorageEntry> input,
  RemoteStorageSortField field,
) {
  final order = List<int>.generate(input.length, (i) => i);
  order.sort((a, b) {
    final byField = _compareByField(input[a], input[b], field);
    if (byField != 0) return byField;
    return a - b; // 完全相等时保持传入相对顺序（稳定排序）
  });
  return <RemoteStorageEntry>[for (final i in order) input[i]];
}

int _compareByField(
  RemoteStorageEntry a,
  RemoteStorageEntry b,
  RemoteStorageSortField field,
) {
  if (a.isDirectory != b.isDirectory) {
    return a.isDirectory ? -1 : 1; // 目录恒在最前；目录之间同样按所选字段
  }
  if (field == RemoteStorageSortField.modifiedTime) {
    final byTime = _compareDesc(a.modifiedAt, b.modifiedAt);
    if (byTime != 0) return byTime;
  } else if (field == RemoteStorageSortField.size) {
    final bySize = _compareDesc(a.size, b.size);
    if (bySize != 0) return bySize;
  }
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

/// 降序比较；null 视为最小（排在最后），交由名称升序兜底。
int _compareDesc(Comparable<dynamic>? a, Comparable<dynamic>? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return b.compareTo(a);
}

class RemoteStorageBrowserPage extends StatefulWidget {
  const RemoteStorageBrowserPage({
    super.key,
    required this.account,
    this.initialPath = '',
  });

  final RemoteStorageAccount account;

  /// 相对 baseUrl 的目录路径；空串为根。
  final String initialPath;

  @override
  State<RemoteStorageBrowserPage> createState() =>
      _RemoteStorageBrowserPageState();
}

class _RemoteStorageBrowserPageState extends State<RemoteStorageBrowserPage> {
  late String _path = widget.initialPath;
  bool _loading = true;
  String _error = '';
  List<RemoteStorageEntry> _entries = const [];
  bool _uploading = false;

  /// 滚动位置记忆：账户 + 目录 → 离开时的偏移。
  ///
  /// 每个目录都是独立 route（`Navigator.push`），route 级 PageStorage 无法
  /// 跨 route 恢复，故用会话级 Map（static：进程内有效，不落盘）。
  static final Map<String, double> _savedScrollOffsets = <String, double>{};

  final ScrollController _scrollController = ScrollController();

  String get _scrollMemoryKey => '${widget.account.id}\u0000$_path';

  String get _accountTitle => widget.account.label.isEmpty
      ? widget.account.displayHost
      : widget.account.label;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_rememberScrollOffset);
    _load();
  }

  @override
  void dispose() {
    _rememberScrollOffset(); // 兜底：滚动途中被 pop 也要记住位置
    _scrollController.dispose();
    super.dispose();
  }

  /// 记住当前滚动位置（滚动过程中持续更新）。
  void _rememberScrollOffset() {
    if (_scrollController.hasClients) {
      _savedScrollOffsets[_scrollMemoryKey] = _scrollController.offset;
    }
  }

  /// 列表重建后（首帧结束）恢复到该目录上次离开时的位置。
  void _restoreScrollOffset() {
    final saved = _savedScrollOffsets[_scrollMemoryKey];
    if (saved == null || saved <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target =
          saved.clamp(0.0, _scrollController.position.maxScrollExtent);
      if ((_scrollController.offset - target).abs() > 0.5) {
        _scrollController.jumpTo(target);
      }
    });
  }

  void _selectSortField(RemoteStorageSortField field) {
    if (field == _sessionSortField) return;
    _sessionSortField = field;
    setState(() {
      _entries = sortedRemoteStorageEntries(_entries, field);
    });
  }

  /// [force] 为 true 时绕过目录缓存（下拉刷新、刷新按钮、重试按钮）。
  ///
  /// 为什么默认用缓存：进目录 / 返回上一级 / 面包屑跳转都会打同一个请求，
  /// 15 秒内的重复列表在弱 NAS 上是实打实的等待；而"我要看最新的"由 force
  /// 与所有写操作的自动失效保证，用户不会失去控制权。
  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final entries = await remoteStorageService()
          .list(widget.account, _path, forceRefresh: force);
      if (!mounted) return;
      setState(() {
        _entries = sortedRemoteStorageEntries(entries, _sessionSortField);
        _loading = false;
      });
      _restoreScrollOffset();
    } on RemoteStorageException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '目录读取失败：$e';
        _loading = false;
      });
    }
  }

  // ------------------------------------------------------------- 上传（拍板 2/3）

  Future<void> _pickAndUpload() async {
    if (_uploading) return;
    final picked = await FilePicker.pickFiles();
    final files = <LocalUploadFile>[];
    for (final f in picked) {
      final path = f.path;
      if (path == null || path.isEmpty) continue;
      int size;
      try {
        size = f.lengthSync() ?? await f.length();
      } catch (_) {
        size = 0;
      }
      files.add(LocalUploadFile(path: path, name: f.name, size: size));
    }
    if (files.isEmpty || !mounted) return;

    setState(() => _uploading = true);
    try {
      final conflicts = await remoteStorageService().scanConflicts(
        widget.account,
        files: files,
        targetDir: _path,
      );
      if (!mounted) return;

      var overwrite = false;
      if (conflicts.isNotEmpty) {
        final choice = await _askConflictPolicy(conflicts);
        if (choice == null) return; // 用户放弃
        overwrite = choice;
      }
      _enqueueUploads(files, overwrite: overwrite, conflictCount: conflicts.length);
    } on RemoteStorageException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('上传准备失败：${e.message}')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// 返回 true=覆盖，false=跳过，null=放弃。
  Future<bool?> _askConflictPolicy(List<String> conflicts) {
    final preview = conflicts.take(5).join('\n');
    final more = conflicts.length > 5 ? '\n…等 ${conflicts.length} 个' : '';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发现同名文件'),
        content: Text('远端已存在 ${conflicts.length} 个同名文件：\n\n$preview$more'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('跳过同名（推荐）'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('覆盖'),
          ),
        ],
      ),
    );
  }

  void _enqueueUploads(
    List<LocalUploadFile> files, {
    required bool overwrite,
    required int conflictCount,
  }) {
    final service = remoteStorageService();
    final queue = transferQueue();
    final dirLabel = _path.isEmpty ? '根目录' : _path;
    for (final file in files) {
      queue.enqueue(
        kind: TransferKind.upload,
        title: file.name,
        subtitle: '$_accountTitle · $dirLabel',
        totalBytes: file.size,
        runner: (cancel, onProgress) => service.uploadFile(
          widget.account,
          file: file,
          targetDir: _path,
          overwrite: overwrite,
          onProgress: onProgress,
          cancel: cancel,
        ),
        onFinished: (task) {
          if (!mounted) return;
          if (task.status == TransferStatus.done) {
            if (task.result == false) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('「${task.title}」已跳过（远端同名）')),
              );
            }
            if (transferQueue().activeCount == 0) _load();
          } else if (task.status == TransferStatus.failed) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('「${task.title}」上传失败：${task.errorMessage ?? ''}')),
            );
          }
        },
      );
    }
    final note = overwrite && conflictCount > 0
        ? '（同名覆盖 $conflictCount 个）'
        : (conflictCount > 0 ? '（同名跳过 $conflictCount 个）' : '');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已加入上传队列：${files.length} 个文件$note')),
    );
  }

  // ------------------------------------------------------------- 下载

  void _enqueueDownload(RemoteStorageEntry entry, {bool openAfter = false}) {
    final service = remoteStorageService();
    final dirLabel = _path.isEmpty ? '根目录' : _path;
    transferQueue().enqueue(
      kind: TransferKind.download,
      title: entry.name,
      subtitle: '$_accountTitle · $dirLabel',
      totalBytes: entry.size ?? -1,
      runner: (cancel, onProgress) => service.download(
        widget.account,
        remotePath: entry.path,
        fileName: entry.name,
        onProgress: onProgress,
        cancel: cancel,
      ),
      onFinished: (task) {
        if (!mounted) return;
        if (task.status == TransferStatus.done && task.result is String) {
          final path = task.result! as String;
          if (openAfter) {
            OpenFilex.open(path);
          } else {
            _showDownloadedDialog(path, entry.name);
          }
        } else if (task.status == TransferStatus.failed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('下载失败：${task.errorMessage ?? ''}')),
          );
        }
      },
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已加入下载队列：${entry.name}')),
    );
  }

  void _showDownloadedDialog(String path, String name) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('下载完成'),
        content: Text('$name\n已保存到应用目录，可打开或分享。'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              SharePlus.instance.share(ShareParams(files: [XFile(path)]));
            },
            child: const Text('分享'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              OpenFilex.open(path);
            },
            child: const Text('打开'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- 预览 / 播放

  Future<void> _previewEntry(RemoteStorageEntry entry) async {
    final kind = remoteEntryKind(entry);
    switch (kind) {
      case RemoteEntryKind.image:
        await showDialog<void>(
          context: context,
          builder: (_) =>
              _ImagePreviewDialog(account: widget.account, entry: entry),
        );
      case RemoteEntryKind.text:
        await showDialog<void>(
          context: context,
          builder: (_) =>
              _TextPreviewDialog(account: widget.account, entry: entry),
        );
      default:
        break;
    }
  }

  void _playEntry(RemoteStorageEntry entry) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RemoteStoragePlayerPage(
          account: widget.account,
          entry: entry,
        ),
      ),
    );
  }

  void _onEntryTap(RemoteStorageEntry entry) {
    final kind = remoteEntryKind(entry);
    switch (kind) {
      case RemoteEntryKind.folder:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RemoteStorageBrowserPage(
              account: widget.account,
              initialPath: entry.path,
            ),
          ),
        );
      case RemoteEntryKind.video:
      case RemoteEntryKind.audio:
        _playEntry(entry);
      case RemoteEntryKind.image:
      case RemoteEntryKind.text:
        _previewEntry(entry);
      case RemoteEntryKind.other:
        _enqueueDownload(entry);
    }
  }

  Future<void> _showEntryMenu(RemoteStorageEntry entry) async {
    final kind = remoteEntryKind(entry);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              dense: true,
              title: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(ctx).textTheme.labelLarge,
              ),
            ),
            if (kind == RemoteEntryKind.video || kind == RemoteEntryKind.audio)
              ListTile(
                leading: const Icon(Icons.play_arrow_rounded),
                title: const Text('播放'),
                onTap: () => Navigator.pop(ctx, 'play'),
              ),
            if (kind == RemoteEntryKind.image || kind == RemoteEntryKind.text)
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text('预览'),
                onTap: () => Navigator.pop(ctx, 'preview'),
              ),
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('下载'),
              onTap: () => Navigator.pop(ctx, 'download'),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: const Text('下载并打开'),
              onTap: () => Navigator.pop(ctx, 'open'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'play':
        _playEntry(entry);
      case 'preview':
        _previewEntry(entry);
      case 'download':
        _enqueueDownload(entry);
      case 'open':
        _enqueueDownload(entry, openAfter: true);
    }
  }

  // ------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_accountTitle),
        actions: [
          PopupMenuButton<RemoteStorageSortField>(
            tooltip: '排序',
            icon: const Icon(Icons.sort_rounded),
            initialValue: _sessionSortField,
            onSelected: _selectSortField,
            itemBuilder: (_) => [
              for (final field in RemoteStorageSortField.values)
                CheckedPopupMenuItem<RemoteStorageSortField>(
                  value: field,
                  checked: _sessionSortField == field,
                  child: Text(_sortFieldLabel(field)),
                ),
            ],
          ),
          IconButton(
            tooltip: '上传到当前目录',
            onPressed: _uploading ? null : _pickAndUpload,
            icon: _uploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_rounded),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: () => _load(force: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildBreadcrumb(),
          const Divider(height: 1),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb() {
    final theme = Theme.of(context);
    final segments =
        _path.split('/').where((s) => s.isNotEmpty).toList(growable: false);
    final crumbs = <Widget>[
      _crumb('根目录', 0, theme),
    ];
    for (var i = 0; i < segments.length; i++) {
      crumbs.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Icon(
          Icons.chevron_right_rounded,
          size: 16,
          color: theme.colorScheme.outline,
        ),
      ));
      crumbs.add(_crumb(segments[i], i + 1, theme));
    }
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Row(children: crumbs),
      ),
    );
  }

  Widget _crumb(String label, int depth, ThemeData theme) {
    final isCurrent = depth == _path.split('/').where((s) => s.isNotEmpty).length;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: isCurrent
          ? null
          : () {
              final segments = _path
                  .split('/')
                  .where((s) => s.isNotEmpty)
                  .take(depth)
                  .toList(growable: false);
              setState(() => _path = segments.join('/'));
              _load();
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: isCurrent ? theme.colorScheme.primary : null,
            fontWeight: isCurrent ? FontWeight.w600 : null,
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(_error, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => _load(force: true),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 160),
            Icon(Icons.folder_open_outlined, size: 56),
            SizedBox(height: 8),
            Center(child: Text('空目录')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _entries.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
        itemBuilder: (_, i) => _buildEntryTile(_entries[i]),
      ),
    );
  }

  Widget _buildEntryTile(RemoteStorageEntry entry) {
    final kind = remoteEntryKind(entry);
    final subtitleParts = <String>[
      if (!entry.isDirectory) formatRemoteBytes(entry.size),
      if (entry.modifiedAt != null) _formatDate(entry.modifiedAt!),
    ];
    return ListTile(
      leading: Icon(_iconFor(kind), color: _colorFor(kind, context)),
      title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitleParts.isEmpty ? null : Text(subtitleParts.join(' · ')),
      trailing: entry.isDirectory
          ? const Icon(Icons.chevron_right_rounded)
          : IconButton(
              tooltip: '更多',
              onPressed: () => _showEntryMenu(entry),
              icon: const Icon(Icons.more_vert_rounded),
            ),
      onTap: () => _onEntryTap(entry),
    );
  }

  static IconData _iconFor(RemoteEntryKind kind) {
    switch (kind) {
      case RemoteEntryKind.folder:
        return Icons.folder_rounded;
      case RemoteEntryKind.image:
        return Icons.image_outlined;
      case RemoteEntryKind.video:
        return Icons.movie_outlined;
      case RemoteEntryKind.audio:
        return Icons.music_note_outlined;
      case RemoteEntryKind.text:
        return Icons.description_outlined;
      case RemoteEntryKind.other:
        return Icons.insert_drive_file_outlined;
    }
  }

  static Color _colorFor(RemoteEntryKind kind, BuildContext context) {
    switch (kind) {
      case RemoteEntryKind.folder:
        return Colors.amber.shade700;
      case RemoteEntryKind.image:
        return Colors.green.shade600;
      case RemoteEntryKind.video:
        return Colors.deepPurple.shade400;
      case RemoteEntryKind.audio:
        return Colors.orange.shade700;
      case RemoteEntryKind.text:
        return Colors.blueGrey.shade500;
      case RemoteEntryKind.other:
        return Theme.of(context).colorScheme.outline;
    }
  }

  static String _formatDate(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }
}

// ------------------------------------------------------------- 图片预览

class _ImagePreviewDialog extends StatefulWidget {
  const _ImagePreviewDialog({required this.account, required this.entry});

  final RemoteStorageAccount account;
  final RemoteStorageEntry entry;

  @override
  State<_ImagePreviewDialog> createState() => _ImagePreviewDialogState();
}

class _ImagePreviewDialogState extends State<_ImagePreviewDialog> {
  late Future<PreviewPayload> _future;

  @override
  void initState() {
    super.initState();
    _future = remoteStorageService()
        .readImagePreview(widget.account, widget.entry.path);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: FutureBuilder<PreviewPayload>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 240,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return _dialogMessage(
              context,
              '预览失败：${snapshot.error}',
            );
          }
          final payload = snapshot.data!;
          if (payload.oversize) {
            return _dialogMessage(
              context,
              '图片超过 ${formatRemoteBytes(kPreviewImageMaxBytes)}，'
              '已跳过预览。\n可下载后查看。',
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: InteractiveViewer(
                  maxScale: 5,
                  child: Image.memory(
                    Uint8List.fromList(payload.bytes),
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  widget.entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _dialogMessage(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- 文本预览

class _TextPreviewDialog extends StatefulWidget {
  const _TextPreviewDialog({required this.account, required this.entry});

  final RemoteStorageAccount account;
  final RemoteStorageEntry entry;

  @override
  State<_TextPreviewDialog> createState() => _TextPreviewDialogState();
}

class _TextPreviewDialogState extends State<_TextPreviewDialog> {
  late Future<PreviewPayload> _future;

  @override
  void initState() {
    super.initState();
    _future = remoteStorageService()
        .readTextPreview(widget.account, widget.entry.path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = MediaQuery.of(context).size.height * 0.7;
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: SizedBox(
        height: height,
        child: FutureBuilder<PreviewPayload>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('预览失败：${snapshot.error}'),
                ),
              );
            }
            final payload = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                if (payload.truncated)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Text(
                      '文件较大，仅显示前 ${formatRemoteBytes(kPreviewTextMaxBytes)}'
                      '${payload.totalLength != null ? '（共 ${formatRemoteBytes(payload.totalLength)}）' : ''}',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      payload.textOrNull ?? '（无法解码为文本）',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
