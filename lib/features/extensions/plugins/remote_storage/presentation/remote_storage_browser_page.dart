// 远程存储：文件浏览页（列表 / 上传 / 下载 / 预览 / 播放入口）。
//
// 拍板 2：P0 仅上传（含浏览、下载、预览、播放），不做删除/重命名。
// 拍板 3：上传遇同名 → 默认跳过，可手动选择覆盖。
// 拍板 6：图片预览 20MB 上限、文本预览 512KB 前缀。
// 拍板 8：下载先落应用文档目录；279 B2 起补上「保存到…」（小文件走系统 SAF 另存，
//         超过 64MB 只给分享/打开指引——saveFile 需要整文件进内存，大文件会 OOM）。

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../application/remote_storage_service.dart';
import '../application/transfer_queue.dart';
import '../domain/remote_storage_models.dart';
import 'remote_storage_player_page.dart';
import 'remote_thumbnail.dart';

/// 顶栏「更多」里的动作（目前只有缩略图开关；后续视图选项都放这里）。
enum _BrowserMenuAction { toggleThumbnails }

// ------------------------------------------------------------- 页面级排序

/// 浏览页排序字段（名称 / 修改时间 / 大小）。
enum RemoteStorageSortField { name, modifiedTime, size }

/// 当前会话的排序字段（跨目录、跨 route 保持；不落盘）。
RemoteStorageSortField _sessionSortField = RemoteStorageSortField.modifiedTime;

/// 超过这么多条目才显示搜索入口（279 C3）。
///
/// 小目录（十几个文件）用眼睛扫比打字快，多一个搜索图标只是噪音；大目录里
/// 它是刚需。阈值取 30 是两者之间的经验分界。
const int kSearchEntryThreshold = 30;

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

  /// 写操作进行中（删除/移动/复制/新建）——期间禁用入口，避免同一目标被并发改。
  bool _busy = false;

  /// 列表是否给图片显示缩略图（顶栏"更多"里可关；持久化，默认开）。
  bool _thumbnailsEnabled = true;

  /// 多选态（B1+）：按 [RemoteStorageEntry.path] 记录而不是按对象，
  /// 这样列表刷新（重新 fetch 出全新对象）后选中态不会丢。
  final Set<String> _selectedPaths = <String>{};

  /// 本目录的完整内容；[_entries] 是它经本地搜索过滤后的视图（279 C3）。
  /// 两者分开是为了：多选/批量统计按"整目录"算，用户看到的筛选不改变已选项。
  List<RemoteStorageEntry> _allEntries = const [];

  /// 本地搜索（C3）：纯前端过滤，不发请求。
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _searching = false;

  bool get _selectionMode => _selectedPaths.isNotEmpty;

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
    _loadThumbnailPreference();
    _load();
  }

  /// 读缩略图开关（默认开）。读不到也不影响列表，只是保持默认。
  Future<void> _loadThumbnailPreference() async {
    final enabled = await remoteStorageService().loadThumbnailsEnabled();
    if (!mounted) return;
    setState(() => _thumbnailsEnabled = enabled);
  }

  Future<void> _toggleThumbnails() async {
    final next = !_thumbnailsEnabled;
    setState(() => _thumbnailsEnabled = next);
    await remoteStorageService().saveThumbnailsEnabled(next);
  }

  @override
  void dispose() {
    _rememberScrollOffset(); // 兜底：滚动途中被 pop 也要记住位置
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// 应用本地搜索：只重算可见列表，不动 [_allEntries]（C3）。
  void _applyFilter() {
    _entries = filterRemoteEntries(_allEntries, _query);
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value;
      _applyFilter();
    });
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _query = '';
        _searchController.clear();
        _applyFilter();
      }
    });
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
      // 排序作用于整目录（[_allEntries]），再套一层当前搜索的过滤。
      _allEntries = sortedRemoteStorageEntries(_allEntries, field);
      _applyFilter();
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
        _allEntries = sortedRemoteStorageEntries(entries, _sessionSortField);
        _applyFilter();
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

  // ------------------------------------------------------------------ 多选

  void _enterSelection(RemoteStorageEntry entry) {
    setState(() => _selectedPaths.add(entry.path));
  }

  void _toggleSelected(RemoteStorageEntry entry) {
    setState(() {
      if (!_selectedPaths.remove(entry.path)) _selectedPaths.add(entry.path);
    });
  }

  void _clearSelection() => setState(_selectedPaths.clear);

  void _toggleSelectAll() {
    setState(() {
      if (_selectedPaths.length == _entries.length) {
        _selectedPaths.clear();
      } else {
        _selectedPaths
          ..clear()
          ..addAll(_entries.map((e) => e.path));
      }
    });
  }

  /// 已选项按**整目录**求值：本地搜索隐藏掉的条目仍在选中集合里，
  /// 否则"筛一下就少删几个"这种静默偏差最难查（C3）。
  List<RemoteStorageEntry> _selectedEntries() =>
      _allEntries.where((e) => _selectedPaths.contains(e.path)).toList();

  /// 批量下载：复用传输队列（逐个入队），不阻塞 UI。
  void _downloadSelected() {
    final files = _selectedEntries().where((e) => !e.isDirectory).toList();
    if (files.isEmpty) {
      _snack('选中的都是文件夹：文件夹请先进入后逐项下载');
      return;
    }
    for (final entry in files) {
      _enqueueDownload(entry, silent: true);
    }
    _snack('已加入下载队列：${files.length} 个文件');
    _clearSelection();
  }

  /// 删除确认：目录必须写清"内容一并删除、不可恢复"（服务器多为递归删除）。
  Future<bool> _confirmDelete(List<RemoteStorageEntry> entries) async {
    final hasDir = entries.any((e) => e.isDirectory);
    final names = entries.take(3).map((e) => e.name).join('、');
    final more = entries.length > 3 ? ' 等 ${entries.length} 项' : '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(hasDir ? '删除文件夹及其内容？' : '删除这些文件？'),
        content: Text(
          '$names$more\n\n'
          '${hasDir ? '文件夹内的所有内容会一并删除。' : ''}'
          '删除后无法恢复（不进回收站）。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _deleteSelected() async {
    final entries = _selectedEntries();
    if (entries.isEmpty || _busy) return;
    if (!await _confirmDelete(entries)) return;
    if (!mounted) return;

    final result = await _runWrite(
      () => remoteStorageService().deleteEntries(widget.account, entries),
    );
    if (result == null) return;
    _clearSelection();
    _reportBatch('删除', result);
  }

  Future<void> _deleteEntry(RemoteStorageEntry entry) async {
    if (_busy) return;
    if (!await _confirmDelete([entry])) return;
    if (!mounted) return;

    final result = await _runWrite(
      () => remoteStorageService().deleteEntries(widget.account, [entry]),
    );
    if (result == null) return;
    _reportBatch('删除', result);
  }

  /// 复制 / 移动到别的目录（都走同一套目录选择 + 批量执行）。
  Future<void> _copyOrMoveSelected({required bool copy}) async {
    final entries = _selectedEntries();
    if (entries.isEmpty || _busy) return;
    await _copyOrMoveEntries(entries, copy: copy);
    if (!mounted) return;
    _clearSelection();
  }

  Future<void> _copyOrMoveEntry(
    RemoteStorageEntry entry, {
    required bool copy,
  }) async {
    if (_busy) return;
    await _copyOrMoveEntries([entry], copy: copy);
  }

  Future<void> _copyOrMoveEntries(
    List<RemoteStorageEntry> entries, {
    required bool copy,
  }) async {
    final action = copy ? '复制' : '移动';
    final targetDir = await _pickDirectory(
      title: '$action到…',
      excludePaths: entries.map((e) => e.path).toSet(),
    );
    if (targetDir == null || !mounted) return;

    final service = remoteStorageService();
    final result = await _runWrite(
      () => copy
          ? service.copyEntries(
              widget.account,
              entries: entries,
              targetDir: targetDir,
            )
          : service.moveEntries(
              widget.account,
              entries: entries,
              targetDir: targetDir,
            ),
    );
    if (result == null) return;
    _reportBatch(action, result);
  }

  Future<void> _createFolder() async {
    if (_busy) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '文件夹名',
            hintText: '例如：备份',
          ),
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;

    final result = await _runWrite(() async {
      await remoteStorageService().createFolder(
        widget.account,
        parentPath: _path,
        name: name,
      );
      return const RemoteBatchResult(succeeded: 1, failures: []);
    });
    if (result == null) return;
    _reportBatch('新建文件夹', result);
  }

  Future<void> _renameEntry(RemoteStorageEntry entry) async {
    if (_busy) return;
    final controller = TextEditingController(text: entry.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '新名称'),
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;

    final result = await _runWrite(() async {
      await remoteStorageService().renameEntry(
        widget.account,
        entry: entry,
        newName: name,
      );
      return const RemoteBatchResult(succeeded: 1, failures: []);
    });
    if (result == null) return;
    _reportBatch('重命名', result);
  }

  /// 目录选择器：只列文件夹，可逐级进入；返回选中的目录路径。
  ///
  /// [excludePaths] 用于"移动到自己所在目录"这类空操作提示（服务层本身会 no-op，
  /// 这里先给出提示，省一次往返）。
  Future<String?> _pickDirectory({
    required String title,
    Set<String> excludePaths = const <String>{},
  }) {
    var current = '';
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            height: 340,
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: '上一级',
                      onPressed: current.isEmpty
                          ? null
                          : () => setDlg(() => current = parentRemotePath(current)),
                      icon: const Icon(Icons.arrow_upward_rounded),
                    ),
                    Expanded(
                      child: Text(
                        current.isEmpty ? '根目录' : '/$current',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 1),
                Expanded(
                  child: FutureBuilder<List<RemoteStorageEntry>>(
                    future: remoteStorageService().list(
                      widget.account,
                      current,
                      forceRefresh: true,
                    ),
                    builder: (ctx, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final err = snap.error;
                      if (err != null) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text('$err', textAlign: TextAlign.center),
                          ),
                        );
                      }
                      final dirs = (snap.data ?? const <RemoteStorageEntry>[])
                          .where((e) => e.isDirectory)
                          .toList();
                      if (dirs.isEmpty) {
                        return const Center(child: Text('没有子文件夹'));
                      }
                      return ListView(
                        children: [
                          for (final dir in dirs)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.folder_rounded),
                              title: Text(
                                dir.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => setDlg(() => current = dir.path),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              // 目标不能是「被移动项自己」或「它自己的子树」——服务器多半回 409/412，
              // 而且把目录移进自身子树在语义上就说不通，这里先拦住。
              onPressed: excludePaths.any(
                (item) => current == item || current.startsWith('$item/'),
              )
                  ? null
                  : () => Navigator.pop(ctx, current),
              child: const Text('选此目录'),
            ),
          ],
        ),
      ),
    );
  }

  /// 包一层统一的忙态 + 异常提示；成功返回结果，失败返回 null（已提示）。
  Future<RemoteBatchResult?> _runWrite(
    Future<RemoteBatchResult> Function() action,
  ) async {
    setState(() => _busy = true);
    try {
      final result = await action();
      if (mounted) await _load(force: true);
      return result;
    } on RemoteStorageException catch (e) {
      if (mounted) _snack(e.message);
      return null;
    } catch (e) {
      if (mounted) _snack('操作失败：$e');
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 汇报批量结果：全成功一句 SnackBar；有失败则列出明细。
  void _reportBatch(String action, RemoteBatchResult result) {
    if (!result.hasFailures) {
      _snack('$action完成：${result.succeeded} 项');
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$action：部分未完成'),
        content: SingleChildScrollView(
          child: Text(result.failures.join('\n')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
      // O5：上传前问一次剩余配额（读不到就不显示，不影响上传）。
      final quota = await _safeQuota();
      if (!mounted) return;
      final totalBytes = files.fold<int>(0, (sum, f) => sum + f.size);
      if (uploadExceedsQuota(quota, totalBytes)) {
        final proceed = await _askInsufficientSpace(
          available: quota!.availableBytes!,
          needed: totalBytes,
        );
        if (proceed != true) return;
      }

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

  /// 读配额；任何失败都吞掉返回 null（配额只用于提示，绝不能挡住上传）。
  Future<RemoteStorageQuota?> _safeQuota() async {
    try {
      final quota =
          await remoteStorageService().quota(widget.account, path: _path);
      return quota.hasAny ? quota : null;
    } catch (_) {
      return null;
    }
  }

  /// 空间可能不足时确认一次（只在服务端给了配额、且本次上传超出它时出现）。
  Future<bool?> _askInsufficientSpace({
    required int available,
    required int needed,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('剩余空间可能不足'),
        content: Text(
          '服务端剩余约 ${formatRemoteBytes(available)}，'
          '本次要上传 ${formatRemoteBytes(needed)}。\n\n'
          '空间不足时服务端会以 507 拒绝，大文件往往传到一半才失败。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('先不传'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('仍然上传'),
          ),
        ],
      ),
    );
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

  /// [silent] 用于批量下载：逐个入队时不要每项弹一次 SnackBar，由调用方汇总。
  void _enqueueDownload(
    RemoteStorageEntry entry, {
    bool openAfter = false,
    bool silent = false,
  }) {
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
    if (silent) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已加入下载队列：${entry.name}')),
    );
  }

  void _showDownloadedDialog(String path, String name) {
    // 大小取自当前列表里的条目（缩略图下载等场景取不到就给 null → 保守策略）。
    int? sizeBytes;
    for (final entry in _entries) {
      if (entry.name == name) {
        sizeBytes = entry.size;
        break;
      }
    }
    final canSafSave =
        exportStrategyFor(sizeBytes) == RemoteExportStrategy.safSave;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('下载完成'),
        content: Text('$name\n已保存到应用目录，可打开或分享。'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _exportToDevice(path, name, sizeBytes: sizeBytes);
            },
            child: Text(canSafSave ? '保存到…' : '保存到…（大文件）'),
          ),
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

  /// 导出到设备（B2）：小文件走系统「另存为」（SAF），大文件只给说明——
  /// 让用户用「分享 → 保存到文件」而不是赌一次 OOM。
  Future<void> _exportToDevice(
    String path,
    String name, {
    required int? sizeBytes,
  }) async {
    final strategy = exportStrategyFor(sizeBytes);
    if (strategy == RemoteExportStrategy.shareFromAppDir) {
      final sizeLabel = sizeBytes == null ? '未知大小' : formatRemoteBytes(sizeBytes);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('文件较大'),
          content: Text(
            '$name（$sizeLabel）超过 64MB，系统「另存为」需要先把整个文件读进内存，'
            '大文件走这条路会拖垮 App。\n\n请改用「分享」→ 保存到文件/相册，'
            '或先用「打开」交给能接收大文件的 App。',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    try {
      final bytes = await File(path).readAsBytes();
      final saved = await FilePicker.saveFile(
        fileName: name,
        bytes: bytes,
        mimeType: mimeTypeForFileName(name),
        dialogTitle: '保存 $name',
      );
      if (!mounted) return;
      if (saved != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已保存到所选位置')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
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
            if (!entry.isDirectory &&
                (kind == RemoteEntryKind.video ||
                    kind == RemoteEntryKind.audio))
              ListTile(
                leading: const Icon(Icons.play_arrow_rounded),
                title: const Text('播放'),
                onTap: () => Navigator.pop(ctx, 'play'),
              ),
            if (!entry.isDirectory &&
                (kind == RemoteEntryKind.image ||
                    kind == RemoteEntryKind.text))
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text('预览'),
                onTap: () => Navigator.pop(ctx, 'preview'),
              ),
            if (!entry.isDirectory)
              ListTile(
                leading: const Icon(Icons.download_rounded),
                title: const Text('下载'),
                onTap: () => Navigator.pop(ctx, 'download'),
              ),
            if (!entry.isDirectory)
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: const Text('下载并打开'),
                onTap: () => Navigator.pop(ctx, 'open'),
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('重命名'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('复制到…'),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_rounded),
              title: const Text('移动到…'),
              onTap: () => Navigator.pop(ctx, 'move'),
            ),
            ListTile(
              leading: const Icon(Icons.checklist_rounded),
              title: const Text('多选'),
              onTap: () => Navigator.pop(ctx, 'multi'),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: Theme.of(ctx).colorScheme.error,
              ),
              title: Text(
                '删除',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
              onTap: () => Navigator.pop(ctx, 'delete'),
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
      case 'rename':
        await _renameEntry(entry);
      case 'copy':
        await _copyOrMoveEntry(entry, copy: true);
      case 'move':
        await _copyOrMoveEntry(entry, copy: false);
      case 'multi':
        _enterSelection(entry);
      case 'delete':
        await _deleteEntry(entry);
    }
  }

  // ------------------------------------------------------------- UI

  /// 顶栏：多选态与常态是两套（多选时把排序/上传/刷新收起来，只留批量动作）。
  PreferredSizeWidget _buildAppBar() {
    if (_selectionMode) {
      final allSelected =
          _entries.isNotEmpty && _selectedPaths.length == _entries.length;
      return AppBar(
        leading: IconButton(
          tooltip: '退出多选',
          onPressed: _clearSelection,
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text('已选 ${_selectedPaths.length} 项'),
        actions: [
          TextButton(
            onPressed: _toggleSelectAll,
            child: Text(allSelected ? '取消全选' : '全选'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _buildSelectionActions(),
        ),
      );
    }
    return AppBar(
      title: Text(_accountTitle),
      bottom: _searching
          ? PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  onChanged: _onQueryChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '在本目录里筛选名称（多个词用空格）',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清空',
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _onQueryChanged('');
                            },
                          ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            )
          : null,
      actions: [
        if (_allEntries.length > kSearchEntryThreshold)
          IconButton(
            tooltip: _searching ? '关闭筛选' : '在本目录筛选',
            onPressed: _toggleSearch,
            icon: Icon(
              _searching ? Icons.search_off_rounded : Icons.search_rounded,
            ),
          ),
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
          tooltip: '新建文件夹',
          onPressed: _busy ? null : _createFolder,
          icon: const Icon(Icons.create_new_folder_outlined),
        ),
        IconButton(
          tooltip: '上传到当前目录',
          onPressed: _uploading || _busy ? null : _pickAndUpload,
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
        // 视图选项放"更多"里：顶栏图标已经不少，且这类开关不需要常驻。
        PopupMenuButton<_BrowserMenuAction>(
          tooltip: '更多',
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (action) {
            if (action == _BrowserMenuAction.toggleThumbnails) {
              _toggleThumbnails();
            }
          },
          itemBuilder: (_) => [
            CheckedPopupMenuItem<_BrowserMenuAction>(
              value: _BrowserMenuAction.toggleThumbnails,
              checked: _thumbnailsEnabled,
              child: const Text('显示图片缩略图'),
            ),
          ],
        ),
      ],
    );
  }

  /// 多选态下的批量动作条（横向可滚动，窄屏不挤爆）。
  Widget _buildSelectionActions() {
    final entries = _selectedEntries();
    final hasFile = entries.any((e) => !e.isDirectory);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: _busy || !hasFile ? null : _downloadSelected,
            icon: const Icon(Icons.download_rounded, size: 20),
            label: const Text('下载'),
          ),
          TextButton.icon(
            onPressed: _busy ? null : () => _copyOrMoveSelected(copy: true),
            icon: const Icon(Icons.copy_rounded, size: 20),
            label: const Text('复制到'),
          ),
          TextButton.icon(
            onPressed: _busy ? null : () => _copyOrMoveSelected(copy: false),
            icon: const Icon(Icons.drive_file_move_rounded, size: 20),
            label: const Text('移动到'),
          ),
          TextButton.icon(
            onPressed: _busy ? null : _deleteSelected,
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 20,
              color: Theme.of(context).colorScheme.error,
            ),
            label: Text(
              '删除',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
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
      // 区分"目录真的空"与"筛掉了"：后者要给一键清空，否则用户会以为文件没了（C3）。
      final filtered = _allEntries.isNotEmpty;
      return RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 160),
            Icon(
              filtered ? Icons.search_off_rounded : Icons.folder_open_outlined,
              size: 56,
            ),
            const SizedBox(height: 8),
            Center(child: Text(filtered ? '本目录没有匹配「$_query」的条目' : '空目录')),
            if (filtered) ...[
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () {
                    _searchController.clear();
                    _onQueryChanged('');
                  },
                  child: const Text('清空筛选'),
                ),
              ),
            ],
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: Column(
        children: [
          if (_query.trim().isNotEmpty)
            Container(
              width: double.infinity,
              color: Theme.of(
                context,
              ).colorScheme.secondaryContainer.withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                '筛选出 ${_entries.length} / ${_allEntries.length} 项',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Expanded(
            child: ListView.separated(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
              itemBuilder: (_, i) => _buildEntryTile(_entries[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryTile(RemoteStorageEntry entry) {
    final kind = remoteEntryKind(entry);
    final selected = _selectedPaths.contains(entry.path);
    final subtitleParts = <String>[
      if (!entry.isDirectory) formatRemoteBytes(entry.size),
      if (entry.modifiedAt != null) _formatDate(entry.modifiedAt!),
    ];
    return ListTile(
      selected: selected,
      selectedTileColor:
          Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
      leading: _selectionMode
          ? Checkbox(
              value: selected,
              onChanged: (_) => _toggleSelected(entry),
            )
          : _leadingFor(entry, kind),
      title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitleParts.isEmpty ? null : Text(subtitleParts.join(' · ')),
      trailing: entry.isDirectory
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.chevron_right_rounded),
                IconButton(
                  tooltip: '更多',
                  onPressed: _busy ? null : () => _showEntryMenu(entry),
                  icon: const Icon(Icons.more_vert_rounded),
                ),
              ],
            )
          : IconButton(
              tooltip: '更多',
              onPressed: _busy ? null : () => _showEntryMenu(entry),
              icon: const Icon(Icons.more_vert_rounded),
            ),
      // 长按进多选：这是"批量操作"的入口，也避免给每个条目再塞一个图标。
      onLongPress: () => _enterSelection(entry),
      onTap: () =>
          _selectionMode ? _toggleSelected(entry) : _onEntryTap(entry),
    );
  }

  /// 行首图标：图片条目且开关打开时换成缩略图（取不到就回退通用图标）。
  Widget _leadingFor(RemoteStorageEntry entry, RemoteEntryKind kind) {
    final icon = Icon(_iconFor(kind), color: _colorFor(kind, context));
    if (!_thumbnailsEnabled || !isThumbnailableEntry(entry)) return icon;
    final account = widget.account;
    return RemoteThumbnail(
      // key 里带账户+路径+大小+修改时间：列表复用到别的图片时重建，不贴错图。
      key: ValueKey(thumbnailCacheKey(account.id, entry)),
      load: () => remoteStorageService().readThumbnail(account, entry),
      placeholder: icon,
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
          // 降采样解码（C4）：20MB 的图可能解码成近 200MB 的位图，全尺寸解码在
          // 小内存设备上直接 OOM。按屏幕宽度 ×2 解，视网膜屏上看不出差别。
          final media = MediaQuery.maybeOf(context);
          final decodeWidth = media == null
              ? null
              : previewImageDecodeWidth(
                  logicalWidth: media.size.width,
                  devicePixelRatio: media.devicePixelRatio,
                );
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
                    cacheWidth: decodeWidth,
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
