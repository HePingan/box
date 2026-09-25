// 服务器运维插件：「文件」页签 —— 直连运维通道的整盘 WebDAV。
//
// 为什么直连而不用「远端存储」插件：那个插件是给**用户自己的网盘**用的
// （多账户、限速、传输队列、断点续传），运维通道要的是"打开就能翻盘"的
// 最小可用集：目录浏览 / 新建文件夹 / 上传 / 下载 / 重命名 / 删除。
//
// 规矩：
//   * 错误一律翻译成中文人话（serverOpsErrorMessage，复用远端存储的映射表）；
//   * 传输中给**有界进度**（底部一条进度条），不做整页 spinner：翻目录时
//     用户还要能继续点，整页转圈会让人以为卡死了；
//   * 删除目录的确认文案必须写清"目录内所有内容一并删除"（服务端递归删）。

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_files_service.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_runtime.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';

/// 文本预览最多读这么多字节（够看配置/日志片段，又不会把大文件拖下来）。
const int kOpsPreviewMaxBytes = 64 * 1024;

class ServerOpsFilesTab extends StatefulWidget {
  const ServerOpsFilesTab({super.key, required this.settings});

  final ServerOpsSettings settings;

  @override
  State<ServerOpsFilesTab> createState() => _ServerOpsFilesTabState();
}

class _ServerOpsFilesTabState extends State<ServerOpsFilesTab> {
  late ServerOpsFilesService _service;
  String _path = '';
  List<RemoteStorageEntry> _entries = const [];
  bool _loading = false;
  bool _busy = false;
  String? _error;
  String _progressText = '';

  @override
  void initState() {
    super.initState();
    _service = serverOpsFilesService(widget.settings);
    _load();
  }

  @override
  void didUpdateWidget(covariant ServerOpsFilesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 设置改了（比如刚填上口令）→ 换一个 client，否则会一直拿旧凭据 401。
    if (oldWidget.settings != widget.settings) {
      _service = serverOpsFilesService(widget.settings);
      _load();
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    setState(() {
      if (!silent) _loading = true;
      _error = null;
    });
    try {
      final entries = await _service.list(_path);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = serverOpsErrorMessage(e);
        _loading = false;
      });
    }
  }

  void _enter(RemoteStorageEntry entry) {
    setState(() {
      _path = entry.path;
      _entries = const [];
      _error = null;
    });
    _load();
  }

  void _goUp() {
    final parent = ServerOpsFilesService.parentOf(_path);
    if (parent == _path) return;
    setState(() {
      _path = parent;
      _entries = const [];
      _error = null;
    });
    _load();
  }

  void _goTo(String path) {
    if (path == _path) return;
    setState(() {
      _path = path;
      _entries = const [];
      _error = null;
    });
    _load();
  }

  /// 包住一次"会改远端"的操作：忙标记 + 中文错误 + 成功后刷新。
  Future<void> _runTask(
    Future<void> Function() action, {
    String? success,
  }) async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      _toast(success ?? '已完成');
      setState(() {
        _busy = false;
        _progressText = '';
      });
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progressText = '';
      });
      _toast(serverOpsErrorMessage(e), error: true);
    }
  }

  void _toast(String text, {bool error = false}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _newFolder() async {
    final name = await _promptText(
      title: '新建文件夹',
      hint: '文件夹名',
      confirm: '创建',
    );
    if (name == null) return;
    final target = ServerOpsFilesService.joinPath(_path, name);
    await _runTask(
      () => _service.createDirectory(target),
      success: '已创建 $name',
    );
  }

  Future<void> _upload() async {
    final picked = await FilePicker.pickFile();
    if (picked == null) return;
    final localPath = picked.path;
    if (localPath == null) {
      _toast('选中的文件在本机没有可直接读取的路径', error: true);
      return;
    }
    if (!mounted) return;
    final target = ServerOpsFilesService.joinPath(_path, picked.name);
    await _runTask(
      () => _service.upload(
        File(localPath),
        target,
        onProgress: (sent, total) {
          if (!mounted) return;
          final pct = total <= 0 ? 0 : (sent * 100 ~/ total);
          setState(() => _progressText = '上传中 $pct%');
        },
      ),
      success: '已上传 ${picked.name}',
    );
  }

  Future<void> _download(RemoteStorageEntry entry) async {
    await _runTask(
      () async {
        final dir = await getTemporaryDirectory();
        final dest = File('${dir.path}/${entry.name}');
        await _service.download(
          entry.path,
          dest,
          onProgress: (received, total) {
            if (!mounted) return;
            final pct = total <= 0 ? 0 : (received * 100 ~/ total);
            setState(() => _progressText = '下载中 $pct%');
          },
        );
        if (!mounted) return;
        final opened = await OpenFilex.open(dest.path);
        if (!mounted) return;
        if (opened.type != ResultType.done) {
          // 打不开也要让用户拿得到文件在哪 —— 只说"失败了"等于没说。
          _toast('已下载到 ${dest.path}（本机没有能打开它的应用）');
        }
      },
      success: '已下载 ${entry.name}',
    );
  }

  Future<void> _rename(RemoteStorageEntry entry) async {
    final name = await _promptText(
      title: '重命名',
      hint: '新名字',
      initial: entry.name,
      confirm: '重命名',
    );
    if (name == null || name == entry.name) return;
    final target =
        ServerOpsFilesService.joinPath(ServerOpsFilesService.parentOf(entry.path), name);
    await _runTask(
      () => _service.rename(entry.path, target),
      success: '已重命名为 $name',
    );
  }

  Future<void> _delete(RemoteStorageEntry entry) async {
    final isDir = entry.isDirectory;
    final ok = await _confirm(
      title: '删除${isDir ? '目录' : '文件'}',
      // 目录是否递归由服务端决定（运维通道是递归的），文案必须写清。
      message: isDir
          ? '「${entry.name}」及目录内所有内容将一并删除，且无法恢复。'
          : '「${entry.name}」将被删除，且无法恢复。',
    );
    if (ok != true) return;
    await _runTask(
      () => _service.delete(entry.path),
      success: '已删除 ${entry.name}',
    );
  }

  Future<void> _preview(RemoteStorageEntry entry) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _TextPreviewDialog(service: _service, entry: entry),
    );
  }

  Future<String?> _promptText({
    required String title,
    required String hint,
    required String confirm,
    String initial = '',
  }) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TextPromptDialog(
        title: title,
        hint: hint,
        confirm: confirm,
        initial: initial,
      ),
    );
    if (result == null || result.trim().isEmpty) return null;
    return result.trim();
  }

  Future<bool?> _confirm({required String title, required String message}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        if (!widget.settings.hasPassword) const _NoPasswordHint(),
        _BreadcrumbBar(
          path: _path,
          busy: _busy,
          onTapPath: _goTo,
          onUp: _goUp,
          onRefresh: () => _load(),
        ),
        if (_error != null)
          _ErrorBanner(message: _error!, onRetry: () => _load()),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(),
            child: _loading && _entries.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _buildList(theme),
          ),
        ),
        if (_progressText.isNotEmpty)
          LinearProgressIndicator(
            minHeight: 2,
            semanticsLabel: _progressText,
          ),
        _ActionBar(
          busy: _busy,
          path: _path,
          onNewFolder: _newFolder,
          onUpload: _upload,
        ),
      ],
    );
  }

  Widget _buildList(ThemeData theme) {
    if (_entries.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text(
                _error == null ? '这个目录是空的' : '这里没列出内容',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = _entries[index];
        return ListTile(
          dense: true,
          leading: Icon(
            entry.isDirectory
                ? Icons.folder_rounded
                : Icons.insert_drive_file_outlined,
            color: entry.isDirectory
                ? const Color(0xFFF59E0B)
                : theme.colorScheme.outline,
          ),
          title: Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: _subtitleFor(entry, theme),
          onTap: entry.isDirectory ? () => _enter(entry) : () => _preview(entry),
          trailing: PopupMenuButton<String>(
            tooltip: '更多',
            enabled: !_busy,
            onSelected: (value) async {
              switch (value) {
                case 'download':
                  await _download(entry);
                case 'rename':
                  await _rename(entry);
                case 'delete':
                  await _delete(entry);
              }
            },
            itemBuilder: (context) => [
              if (!entry.isDirectory)
                const PopupMenuItem(
                  value: 'download',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.download_rounded),
                    title: Text('下载到本机'),
                  ),
                ),
              const PopupMenuItem(
                value: 'rename',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.drive_file_rename_outline_rounded),
                  title: Text('重命名'),
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline_rounded),
                  title: Text('删除'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget? _subtitleFor(RemoteStorageEntry entry, ThemeData theme) {
    final parts = <String>[];
    if (entry.isDirectory) {
      parts.add('目录');
    } else {
      parts.add(_prettySize(entry.size));
    }
    final modified = entry.modifiedAt;
    if (modified != null) {
      parts.add(_prettyTime(modified));
    }
    return Text(
      parts.join(' · '),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.outline,
      ),
    );
  }
}

class _BreadcrumbBar extends StatelessWidget {
  const _BreadcrumbBar({
    required this.path,
    required this.busy,
    required this.onTapPath,
    required this.onUp,
    required this.onRefresh,
  });

  final String path;
  final bool busy;
  final void Function(String) onTapPath;
  final VoidCallback onUp;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final crumbs = ServerOpsFilesService.breadcrumbs(path);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.4,
          ),
      child: Row(
        children: [
          IconButton(
            tooltip: '上一级',
            onPressed: busy ? null : onUp,
            icon: const Icon(Icons.arrow_upward_rounded, size: 18),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  for (var i = 0; i < crumbs.length; i++) ...[
                    if (i > 0)
                      const Icon(Icons.chevron_right_rounded, size: 16),
                    TextButton(
                      onPressed: busy ? null : () => onTapPath(crumbs[i].$1),
                      child: Text(
                        crumbs[i].$2,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: i == crumbs.length - 1
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: busy ? null : onRefresh,
            icon: const Icon(Icons.refresh_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.busy,
    required this.path,
    required this.onNewFolder,
    required this.onUpload,
  });

  final bool busy;
  final String path;
  final VoidCallback onNewFolder;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                path.isEmpty ? '/' : '/$path',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : onNewFolder,
              icon: const Icon(Icons.create_new_folder_outlined, size: 16),
              label: const Text('新建文件夹'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: busy ? null : onUpload,
              icon: const Icon(Icons.upload_rounded, size: 16),
              label: const Text('上传'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoPasswordHint extends StatelessWidget {
  const _NoPasswordHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF3CD),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        '还没配置运维通道口令：请到右上角设置里填写（构建注入过就不用填）。',
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: theme.textTheme.bodySmall),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

/// 文本输入对话框。
///
/// 为什么单独一个 StatefulWidget：controller 必须随对话框一起销毁。
/// 在 `await showDialog(...)` 之后立刻 dispose，对话框还在播放关闭动画、
/// TextField 仍持有它 → "A TextEditingController was used after being disposed"。
class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.hint,
    required this.confirm,
    required this.initial,
  });

  final String title;
  final String hint;
  final String confirm;
  final String initial;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: widget.hint,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(widget.confirm),
        ),
      ],
    );
  }
}

class _TextPreviewDialog extends StatefulWidget {
  const _TextPreviewDialog({required this.service, required this.entry});

  final ServerOpsFilesService service;
  final RemoteStorageEntry entry;

  @override
  State<_TextPreviewDialog> createState() => _TextPreviewDialogState();
}

class _TextPreviewDialogState extends State<_TextPreviewDialog> {
  String? _text;
  String? _error;
  bool _truncated = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final result =
          await widget.service.readUpTo(widget.entry.path, kOpsPreviewMaxBytes);
      if (!mounted) return;
      setState(() {
        _text = _decodeText(result.bytes);
        _truncated = result.truncated;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = serverOpsErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: _error != null
              ? Text(_error!)
              : _text == null
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          _text!.isEmpty ? '（空文件）' : _text!,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        if (_truncated)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              '（内容较长，只显示开头部分）',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ),
                      ],
                    ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

/// 尽力把字节解成文本（UTF-8，坏字节替换而不是抛错）。
String _decodeText(List<int> bytes) =>
    utf8.decode(bytes, allowMalformed: true);

String _prettySize(int? bytes) {
  if (bytes == null || bytes < 0) return '大小未知';
  const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  if (unit == 0) return '$bytes B';
  return '${value.toStringAsFixed(1)} ${units[unit]}';
}

String _prettyTime(DateTime at) {
  final local = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
