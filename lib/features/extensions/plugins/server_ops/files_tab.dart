// 服务器运维插件：「文件」页签 —— 直连运维通道的整盘 WebDAV。
//
// 为什么直连而不用「远端存储」插件：那个插件是给**用户自己的网盘**用的
// （多账户、限速、传输队列、断点续传），运维通道要的是"打开就能翻盘"的
// 最小可用集：目录浏览 / 新建文件夹 / 上传 / 下载 / 重命名 / 删除 / 复制移动。
//
// 规矩：
//   * 错误一律翻译成中文人话（serverOpsErrorMessage，复用远端存储的映射表）；
//   * 传输中给**有界进度**（底部一条进度条），不做整页 spinner：翻目录时
//     用户还要能继续点，整页转圈会让人以为卡死了；
//   * 删除目录的确认文案必须写清"目录内所有内容一并删除"（服务端递归删）；
//   * 批量/目录级操作走**串行队列**（并发恒为 1，见 server_ops_transfer_queue.dart），
//     进度显示"第 i/n"，可取消，单项失败不打断整批。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_api_client.dart';
import 'package:box/features/extensions/plugins/server_ops/file_editor_page.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_files_service.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_request_log.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_runtime.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_transfer_queue.dart';

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

  // ── A3：排序 / 过滤 / 多选 ──────────────────────────────────────
  OpsSortMode _sortMode = OpsSortMode.name;
  bool _sortDescending = false;
  String _filter = '';
  bool _selecting = false;
  final Set<String> _selected = <String>{};

  /// A2/A4：当前可取消的传输（null = 当前操作不可取消）。
  TransferCancelToken? _cancelToken;

  // ── D1：大目录的呈现上限 / 慢提示 / 停止等待 ────────────────────────
  /// 一次最多渲染多少条：`/usr/lib64` 这种目录实测 758 条要 54 秒、484 KB，
  /// 一次把上千条塞进 ListView 只会让首帧更慢、更不像话。先给前 300 条。
  static const int _initialRows = 300;
  static const int _moreRows = 300;

  /// 当前允许渲染的条数（过滤/排序/换目录/重新列举都会回到初值）。
  int _renderLimit = _initialRows;

  /// 列举的"停止等待"：传输层没有给 `list` 的取消能力（那是共享给远端存储插件的
  /// WebdavClient，不动它），所以这里改成"结果回来也不再用"—— 用户看到的是转圈停了。
  int _listAttempt = 0;
  bool _slowList = false;
  Timer? _slowTimer;
  DateTime? _listStarted;

  /// 过滤 + 排序后的可见列表（`_entries` 始终是服务端返回的本地全量）。
  List<RemoteStorageEntry> get _visibleEntries =>
      ServerOpsFilesService.sortEntries(
        ServerOpsFilesService.filterEntries(_entries, _filter),
        _sortMode,
        descending: _sortDescending,
      );

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
    final attempt = ++_listAttempt;
    setState(() {
      if (!silent) _loading = true;
      _error = null;
    });
    final started = DateTime.now();
    _listStarted = started;
    if (!silent) {
      // 大目录要几十秒：5 秒还没回来就把话说清楚（别让人以为卡死了）
      _slowTimer?.cancel();
      _slowTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted || attempt != _listAttempt) return;
        setState(() => _slowList = true);
      });
    }
    try {
      final entries = await _service.list(_path);
      // "停止等待"之后回来的结果一律丢掉：不再 setState，也不写请求日志
      if (!mounted || attempt != _listAttempt) return;
      _slowTimer?.cancel();
      setState(() {
        _entries = entries;
        _loading = false;
        _slowList = false;
        _renderLimit = _initialRows; // 新的一份列表，从头给
      });
      // silent 是"操作成功后的自动刷新"，记下来只会把面板淹成一片"列举"；
      // 失败的 silent 刷新要记（那正是"上传成功了但列表没刷新"这种怪现象的证据）。
      if (!silent) _log('文件', true, '列举 $_path：${entries.length} 项', started);
    } catch (e) {
      if (!mounted || attempt != _listAttempt) return;
      _slowTimer?.cancel();
      setState(() {
        _error = serverOpsErrorMessage(e);
        _loading = false;
        _slowList = false;
      });
      _log('文件', false, serverOpsErrorMessage(e), started);
    }
  }

  /// D1：停止等待这次列举（服务端可能还在跑，但结果不再影响界面）。
  void _cancelList() {
    _slowTimer?.cancel();
    final started = _listStarted;
    setState(() {
      _listAttempt++; // 让在途请求的结果作废
      _loading = false;
      _slowList = false;
    });
    if (started != null) {
      _log('文件', false, '已停止等待列举 $_path（服务端可能仍在列举）', started);
    }
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  /// A9：把一次操作的元数据记进共享请求日志。
  ///
  /// **只记 入口 / 机器 / 行不行 / 人话结论 / 耗时** —— 口令不进这里（面板会被截图、
  /// 会被共享屏幕，口令出现一次就等于泄露一次；`OpsRequestRecord` 的约定有用例守着）。
  void _log(String entry, bool ok, String detail, DateTime started) {
    final s = widget.settings.currentServer;
    serverOpsRequestLog.record(
      OpsRequestRecord(
        entry: entry,
        serverId: s.id,
        serverLabel: s.label,
        ok: ok,
        detail: detail,
        duration: DateTime.now().difference(started),
        at: started,
      ),
    );
  }

  void _enter(RemoteStorageEntry entry) {
    setState(() {
      _path = entry.path;
      _entries = const [];
      _error = null;
      _exitSelectingLocked();
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
      _exitSelectingLocked();
    });
    _load();
  }

  void _goTo(String path) {
    if (path == _path) return;
    setState(() {
      _path = path;
      _entries = const [];
      _error = null;
      _exitSelectingLocked();
    });
    _load();
  }

  /// 包住一次"会改远端"的操作：忙标记 + 中文错误 + 成功后刷新。
  Future<void> _runTask(
    Future<void> Function() action, {
    String? success,
    String op = '文件操作',
  }) async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final started = DateTime.now();
    try {
      await action();
      if (!mounted) return;
      _log(op, true, success ?? '已完成', started);
      _toast(success ?? '已完成');
      setState(() {
        _busy = false;
        _progressText = '';
      });
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      _log(op, false, serverOpsErrorMessage(e), started);
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
      op: '新建文件夹',
    );
  }

  // ── A2：上传（多选 + 串行队列 + 可取消） ─────────────────────────

  Future<void> _upload() async {
    final picked = await serverOpsPickFiles();
    if (!mounted) return;
    if (picked.isEmpty) return;
    final usable =
        picked.where((p) => p.path.isNotEmpty).toList(growable: false);
    final skipped = picked.length - usable.length;
    if (usable.isEmpty) {
      _toast('选中的文件在本机都没有可直接读取的路径', error: true);
      return;
    }
    if (skipped > 0) {
      _toast('有 $skipped 个文件本机没有可直接读取的路径，已跳过');
    }
    await _runUploadQueue(usable);
  }

  /// 串行上传：一次一个（并发=1），每项可取消，中间失败继续下一项。
  Future<void> _runUploadQueue(List<OpsPickedFile> files) async {
    final started = DateTime.now();
    final cancel = TransferCancelToken();
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _cancelToken = cancel;
      _progressText = '';
    });

    final result = await runOpsSerialQueue(
      total: files.length,
      cancel: cancel,
      onStart: (i) {
        if (!mounted) return;
        setState(() => _progressText = '上传中 第 ${i + 1}/${files.length} 项');
      },
      task: (i) {
        final picked = files[i];
        return _service.upload(
          File(picked.path),
          ServerOpsFilesService.joinPath(_path, picked.name),
          cancel: cancel,
          onProgress: (sent, total) {
            if (!mounted) return;
            final pct = total <= 0 ? 0 : sent * 100 ~/ total;
            setState(
              () => _progressText =
                  '上传中 第 ${i + 1}/${files.length} 项 $pct%',
            );
          },
        );
      },
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _progressText = '';
      _cancelToken = null;
    });
    _log('上传', result.allSucceeded, result.summary('上传'), started);
    _toast(result.summary('上传'), error: !result.allSucceeded);
    await _load(silent: true);
  }

  void _cancelCurrent() {
    _cancelToken?.cancel();
  }

  // ── A4：复制 / 移动到… ────────────────────────────────────────

  Future<void> _copyTo(RemoteStorageEntry entry) async {
    final target = await _pickTargetDir(entry, verb: '复制');
    if (target == null) return;
    await _runClipboard(entry, target, copy: true);
  }

  Future<void> _moveTo(RemoteStorageEntry entry) async {
    final target = await _pickTargetDir(entry, verb: '移动');
    if (target == null) return;
    await _runClipboard(entry, target, copy: false);
  }

  /// 让用户选目标目录，返回"目标目录 + 原名"的完整路径；取消/非法返回 null。
  Future<String?> _pickTargetDir(
    RemoteStorageEntry entry, {
    required String verb,
  }) async {
    final dir = await showDialog<String>(
      context: context,
      builder: (_) => _DirectoryPickerDialog(
        service: _service,
        title: '$verb「${entry.name}」到…',
        initialPath: _path,
      ),
    );
    if (!mounted) return null;
    if (dir == null) return null;
    final target = ServerOpsFilesService.joinPath(dir, entry.name);
    if (target == entry.path) {
      _toast('目标就是它自己，没有可做的');
      return null;
    }
    // 目录不能塞进自己的子目录里：服务端递归 COPY 会无限展开（或直接报错）。
    if (entry.isDirectory &&
        (dir == entry.path || dir.startsWith('${entry.path}/'))) {
      _toast('不能把目录放进它自己的子目录里', error: true);
      return null;
    }
    return target;
  }

  Future<void> _runClipboard(
    RemoteStorageEntry entry,
    String target, {
    required bool copy,
  }) async {
    final started = DateTime.now();
    final cancel = TransferCancelToken();
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _cancelToken = cancel;
      // 目录复制必须写清"逐文件进行、可取消"（服务端整目录 COPY 会丢子文件）。
      _progressText =
          copy && entry.isDirectory ? '复制中（逐文件进行，可取消）' : '';
      _exitSelectingLocked();
    });
    try {
      if (copy) {
        await _service.copyEntry(
          entry.path,
          target,
          isDirectory: entry.isDirectory,
          cancel: cancel,
          onProgress: (done, total) {
            if (!mounted) return;
            setState(() => _progressText = '复制中 $done/$total 个文件');
          },
        );
        if (!mounted) return;
        _log('复制', true, '已复制到 /$target', started);
        _toast('已复制到 /$target');
      } else {
        await _service.moveEntry(entry.path, target);
        if (!mounted) return;
        _log('移动', true, '已移动到 /$target', started);
        _toast('已移动到 /$target');
      }
    } catch (e) {
      if (!mounted) return;
      _toast(serverOpsErrorMessage(e), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progressText = '';
          _cancelToken = null;
        });
      }
    }
    await _load(silent: true);
  }

  // ── A3：多选与批量删除 ────────────────────────────────────────

  void _startSelecting(RemoteStorageEntry entry) {
    setState(() {
      _selecting = true;
      _selected.add(entry.path);
    });
  }

  void _toggleSelected(RemoteStorageEntry entry) {
    setState(() {
      if (!_selected.remove(entry.path)) {
        _selected.add(entry.path);
      }
      if (_selected.isEmpty) _selecting = false;
    });
  }

  void _exitSelecting() {
    setState(_exitSelectingLocked);
  }

  /// 供 setState 内复用（已持有 setState 时不能嵌套调用 setState）。
  void _exitSelectingLocked() {
    _selecting = false;
    _selected.clear();
  }

  void _selectAllVisible() {
    setState(() {
      _selected
        ..clear()
        ..addAll(_visibleEntries.map((e) => e.path));
    });
  }

  /// 压缩包后缀（与服务端认的那批一致）。用它决定"解压"这一项显不显示。
  static bool _looksLikeArchive(String name) {
    final lower = name.toLowerCase();
    return const ['.zip', '.tar', '.tar.gz', '.tgz', '.tar.bz2', '.tbz2',
            '.tar.xz', '.txz', '.gz']
        .any(lower.endsWith);
  }

  /// 远端**绝对**路径（当前目录 + 条目名）。
  ///
  /// 注意两套路径口径不一样：文件通道（WebDAV）用的是相对根目录的 'a/b.txt'，
  /// 而只读接口的写动作要求绝对路径 '/a/b.txt'（它要 resolve() 之后比对保护名单）。
  /// 这两台机器的 DAV 根就是 '/'，所以补一个前导斜杠即可对齐；少了它会直接 400「必须是绝对路径」。
  String _remotePathOf(RemoteStorageEntry entry) {
    final dir = _path.endsWith('/') ? _path.substring(0, _path.length - 1) : _path;
    final full = '$dir/${entry.name}';
    return full.startsWith('/') ? full : '/$full';
  }

  /// **解压**（写档，走只读接口）：服务端解，手机不用把包下下来再传上去。
  ///
  /// 这条动作以前只能"下载到手机 → 本机解压 → 再传回去"，一个几百 MB 的包光流量就够呛。
  Future<void> _extract(RemoteStorageEntry entry) async {
    final path = _remotePathOf(entry);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('解压「${entry.name}」'),
        content: Text('服务端会把它解到当前目录（$_path）。\n'
            '同名的文件会被覆盖 —— 服务端只做白名单动作，不执行压缩包里的脚本。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('解压')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _runApiTask('解压', () async {
      final api = serverOpsApiClient(widget.settings);
      final d = await api.extract(path);
      return '已解压 ${d['count'] ?? 0} 个条目到 $_path'
          '${d['truncated'] == true ? '（到上限被截断）' : ''}';
    });
  }

  /// **权限 / 属主**（写档）：宝塔里最常用的一格。
  ///
  /// 输入框的控制器交给对话框自己持有 —— 早先的写法是"showDialog 返回后立刻 dispose()"，
  /// 结果退场动画还在跑、TextField 还在用那个控制器，直接抛
  /// `A TextEditingController was used after being disposed`（用例里抓到）。
  Future<void> _editPermissions(RemoteStorageEntry entry) async {
    final path = _remotePathOf(entry);
    final r = await showDialog<_PermResult>(
      context: context,
      builder: (_) => _PermissionsDialog(
        name: entry.name,
        isDirectory: entry.isDirectory,
      ),
    );
    if (r == null || !mounted) return;
    await _runApiTask('改权限', () async {
      final api = serverOpsApiClient(widget.settings);
      final parts = <String>[];
      if (r.mode.isNotEmpty) {
        final d = await api.chmod(path, r.mode, recursive: r.recursive);
        parts.add('权限 ${d['mode'] ?? r.mode}');
      }
      if (r.owner.isNotEmpty || r.group.isNotEmpty) {
        await api.chown(
          path,
          owner: r.owner,
          group: r.group,
          recursive: r.recursive,
        );
        parts.add('属主 ${r.owner.isEmpty ? '(不改)' : r.owner}'
            ':${r.group.isEmpty ? '(不改)' : r.group}');
      }
      if (parts.isEmpty) return '没改任何东西（权限与属主都留空了）';
      return '已改 ${entry.name}：${parts.join('，')}';
    });
  }

  /// 写动作的统一壳：成功后刷新列表 + 记日志（失败把服务端原话给出来）。
  Future<void> _runApiTask(String op, Future<String> Function() run) async {
    final started = DateTime.now();
    setState(() => _busy = true);
    try {
      final detail = await run();
      if (!mounted) return;
      _toast(detail);
      _log(op, true, detail, started);
      await _load();
    } on OpsApiException catch (e) {
      if (!mounted) return;
      _toast('$op失败：${e.message}', error: true);
      _log(op, false, e.message, started);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 批量删除：保留二次确认（文案写明不可恢复），串行执行、失败不打断整批。
  Future<void> _deleteSelected() async {
    final targets = _entries
        .where((e) => _selected.contains(e.path))
        .toList(growable: false);
    if (targets.isEmpty) return;
    final hasDirectory = targets.any((e) => e.isDirectory);
    final ok = await _confirm(
      title: '删除 ${targets.length} 项',
      message: hasDirectory
          ? '选中的 ${targets.length} 项（目录内所有内容将一并删除）将被删除，'
              '且无法恢复。'
          : '选中的 ${targets.length} 项将被删除，且无法恢复。',
    );
    if (ok != true) return;
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _progressText = '';
    });

    final started = DateTime.now();
    final cancel = TransferCancelToken();
    final result = await runOpsSerialQueue(
      total: targets.length,
      cancel: cancel,
      onStart: (i) {
        if (!mounted) return;
        setState(() => _progressText = '删除中 第 ${i + 1}/${targets.length} 项');
      },
      task: (i) => _service.delete(targets[i].path),
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _progressText = '';
      _exitSelectingLocked();
    });
    _log('批量删除', result.allSucceeded, result.summary('删除'), started);
    _toast(result.summary('删除'), error: !result.allSucceeded);
    await _load(silent: true);
  }

  // ── A8：下载与下载缓存 ────────────────────────────────────────

  Future<void> _download(RemoteStorageEntry entry) async {
    await _runTask(
      () async {
        // 下载前清掉临时目录里的同名旧文件（A8：避免半截旧文件被当成新下载）。
        final dest = await serverOpsDownloadCache.prepare(entry.name);
        await _service.download(
          entry.path,
          dest,
          onProgress: (received, total) {
            if (!mounted) return;
            final pct = total <= 0 ? 0 : received * 100 ~/ total;
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
      op: '下载',
    );
  }

  /// 清空下载缓存（只删本机下载的临时文件；与 host 页清"快照与历史"是两码事）。
  Future<void> _clearDownloadCache() async {
    final ok = await _confirm(
      title: '清空下载缓存',
      message: '将删除本机临时目录里所有已下载的文件；'
          '不影响远端文件，也不影响快照与历史。',
      confirm: '清空',
    );
    if (ok != true) return;
    if (!mounted) return;
    try {
      final bytes = await serverOpsDownloadCache.clear();
      if (!mounted) return;
      _toast(bytes > 0 ? '已清空下载缓存，释放 ${_prettySize(bytes)}' : '下载缓存本来就是空的');
    } catch (e) {
      if (!mounted) return;
      _toast(serverOpsErrorMessage(e), error: true);
    }
  }

  Future<void> _rename(RemoteStorageEntry entry) async {
    final name = await _promptText(
      title: '重命名',
      hint: '新名字',
      initial: entry.name,
      confirm: '重命名',
    );
    if (name == null || name == entry.name) return;
    final target = ServerOpsFilesService.joinPath(
      ServerOpsFilesService.parentOf(entry.path),
      name,
    );
    await _runTask(
      () => _service.rename(entry.path, target),
      success: '已重命名为 $name',
      op: '重命名',
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
      op: '删除',
    );
  }

  /// 点文件：**按类型**决定怎么看。
  ///
  /// 以前一律走文本预览，图片/压缩包被当文本解码成一屏乱码方块（真机上打开
  /// 截图就是这样）。二进制文件没有"文本预览"这回事，必须按 remoteEntryKind 分流：
  /// 图片 → 相册式预览；文本 → 文本预览；其余 → 交给本机应用。
  Future<void> _open(RemoteStorageEntry entry) async {
    switch (remoteEntryKind(entry)) {
      case RemoteEntryKind.folder:
        return;
      case RemoteEntryKind.image:
        await _openImage(entry);
      case RemoteEntryKind.text:
        await showDialog<void>(
          context: context,
          builder: (_) => _TextPreviewDialog(
            service: _service,
            entry: entry,
            onSaved: () async {
              // 保存/恢复之后刷新列表（大小与时间会变）
              await _load(silent: true);
            },
          ),
        );
      case RemoteEntryKind.video:
      case RemoteEntryKind.audio:
      case RemoteEntryKind.other:
        await _openExternal(entry);
    }
  }

  /// 图片：复用远端存储插件的相册式预览（同目录图片左右翻 + 缩放）。
  ///
  /// 只把同目录的**图片**传进去：传整份列表会让"下一张"翻到 pdf 上。
  Future<void> _openImage(RemoteStorageEntry entry) async {
    final images = _entries
        .where((e) => remoteEntryKind(e) == RemoteEntryKind.image)
        .toList(growable: false);
    if (images.isEmpty) return;
    final index = images.indexWhere((e) => e.path == entry.path);
    await serverOpsImagePreviewOpener(
      context,
      _service.account,
      images,
      index < 0 ? 0 : index,
    );
  }

  /// 视频/音频/其它二进制：不当文本看，交给本机应用（先下到临时目录）。
  Future<void> _openExternal(RemoteStorageEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(entry.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: const Text(
          '这是二进制文件，用文本方式打开只会看到乱码。\n'
          '可以下载后用本机应用打开（会先存到临时目录）。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('用其他应用打开'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _download(entry);
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

  Future<bool?> _confirm({
    required String title,
    required String message,
    String confirm = '删除',
  }) {
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
            child: Text(confirm),
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
        if (_selecting)
          _SelectionBar(
            count: _selected.length,
            total: _visibleEntries.length,
            onExit: _exitSelecting,
            onSelectAll: _selectAllVisible,
            onDelete: _selected.isEmpty ? null : _deleteSelected,
          )
        else
          _SortFilterBar(
            mode: _sortMode,
            descending: _sortDescending,
            onMode: (mode) => setState(() {
              _sortMode = mode;
              _renderLimit = _initialRows;
            }),
            onToggleDirection: () => setState(() {
              _sortDescending = !_sortDescending;
              _renderLimit = _initialRows;
            }),
            onFilter: (value) => setState(() {
              _filter = value;
              _renderLimit = _initialRows;
            }),
          ),
        if (_error != null)
          _ErrorBanner(message: _error!, onRetry: () => _load()),
        if (_loading && _entries.isNotEmpty)
          const LinearProgressIndicator(minHeight: 2, semanticsLabel: '正在列举'),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(),
            child: _loading && _entries.isEmpty
                ? _buildListing(theme)
                : _buildList(theme),
          ),
        ),
        if (_progressText.isNotEmpty) ...[
          LinearProgressIndicator(
            minHeight: 2,
            semanticsLabel: _progressText,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _progressText,
                    style: theme.textTheme.labelSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 只有批量/目录级操作才是可取消的（单文件操作太快，给取消没意义）。
                if (_cancelToken != null)
                  TextButton(
                    onPressed: _cancelCurrent,
                    child: const Text('取消'),
                  ),
              ],
            ),
          ),
        ],
        _ActionBar(
          busy: _busy,
          path: _path,
          onNewFolder: _newFolder,
          onUpload: _upload,
          onClearDownloads: _clearDownloadCache,
        ),
      ],
    );
  }

  /// D1：列举中的样子 —— 转圈 + 把"在做什么"说清楚 + 能停止等待。
  ///
  /// 为什么不是整页转圈了事：`/usr/lib64`（758 条）实测 54 秒。只转圈的话，用户
  /// 分不清"卡死"和"在干活"，也没有退出的办法。
  Widget _buildListing(ThemeData theme) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 56),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 14),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _slowList
                  ? '这个目录比较大，还在列举。\n'
                      '运维通道是逐项读取的：几百项的目录可能要几十秒。'
                  : '正在列举 ${_path.isEmpty ? '/' : _path}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ),
        if (_slowList) ...[
          const SizedBox(height: 6),
          Center(
            child: TextButton(
              onPressed: _cancelList,
              child: const Text('停止等待'),
            ),
          ),
          Center(
            child: Text(
              '停止后服务端那边可能还在跑完，只是结果不再刷到这个页面',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildList(ThemeData theme) {
    final visible = _visibleEntries;
    if (visible.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text(
                _error != null
                    ? '这里没列出内容'
                    : _filter.trim().isEmpty
                        ? '这个目录是空的'
                        : '没有名称匹配「${_filter.trim()}」的条目',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ),
        ],
      );
    }
    final shown =
        visible.length > _renderLimit ? visible.sublist(0, _renderLimit) : visible;
    final more = visible.length - shown.length;
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: shown.length + (more > 0 ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index >= shown.length) {
          // 大目录：先把前 N 条给出来，剩下的按需加载
          return ListTile(
            dense: true,
            leading: const Icon(Icons.expand_more_rounded, size: 18),
            title: Text('还有 $more 项，继续加载'),
            subtitle: Text(
              '这个目录共 ${visible.length} 项（一次只渲染 $_initialRows 项，'
              '大目录列举本身在服务端就要几十秒）',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => setState(() => _renderLimit += _moreRows),
          );
        }
        final entry = shown[index];
        return ListTile(
          dense: true,
          selected: _selecting && _selected.contains(entry.path),
          leading: _selecting
              ? Checkbox(
                  value: _selected.contains(entry.path),
                  onChanged: (_) => _toggleSelected(entry),
                )
              : Icon(
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
          onTap: _selecting
              ? () => _toggleSelected(entry)
              : (entry.isDirectory ? () => _enter(entry) : () => _open(entry)),
          onLongPress: _selecting ? null : () => _startSelecting(entry),
          trailing: _selecting
              ? null
              : PopupMenuButton<String>(
                  tooltip: '更多',
                  enabled: !_busy,
                  onSelected: (value) async {
                    switch (value) {
                      case 'download':
                        await _download(entry);
                      case 'copy':
                        await _copyTo(entry);
                      case 'move':
                        await _moveTo(entry);
                      case 'rename':
                        await _rename(entry);
                      case 'delete':
                        await _delete(entry);
                      case 'extract':
                        await _extract(entry);
                      case 'permissions':
                        await _editPermissions(entry);
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
                      value: 'copy',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.copy_all_rounded),
                        title: Text('复制到…'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'move',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.drive_file_move_outline),
                        title: Text('移动到…'),
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
                    if (!entry.isDirectory && _looksLikeArchive(entry.name))
                      const PopupMenuItem(
                        value: 'extract',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.unarchive_outlined),
                          title: Text('解压到当前目录'),
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'permissions',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.admin_panel_settings_outlined),
                        title: Text('权限 / 属主'),
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

/// A3：排序档位 + 方向 + 名称过滤。
class _SortFilterBar extends StatelessWidget {
  const _SortFilterBar({
    required this.mode,
    required this.descending,
    required this.onMode,
    required this.onToggleDirection,
    required this.onFilter,
  });

  final OpsSortMode mode;
  final bool descending;
  final ValueChanged<OpsSortMode> onMode;
  final VoidCallback onToggleDirection;
  final ValueChanged<String> onFilter;

  static String _label(OpsSortMode mode) {
    switch (mode) {
      case OpsSortMode.name:
        return '名称';
      case OpsSortMode.size:
        return '大小';
      case OpsSortMode.time:
        return '时间';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('ops-file-filter'),
              style: theme.textTheme.bodySmall,
              decoration: const InputDecoration(
                isDense: true,
                hintText: '按名称过滤',
                prefixIcon: Icon(Icons.search_rounded, size: 18),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 8,
                ),
              ),
              onChanged: onFilter,
            ),
          ),
          PopupMenuButton<OpsSortMode>(
            tooltip: '排序',
            onSelected: onMode,
            icon: const Icon(Icons.sort_rounded, size: 18),
            itemBuilder: (_) => [
              for (final option in OpsSortMode.values)
                CheckedPopupMenuItem<OpsSortMode>(
                  value: option,
                  checked: option == mode,
                  child: Text(_label(option)),
                ),
            ],
          ),
          IconButton(
            tooltip: descending ? '降序' : '升序',
            onPressed: onToggleDirection,
            icon: Icon(
              descending
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

/// A3：多选态顶栏（已选计数 / 全选 / 批量删除 / 退出）。
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.total,
    required this.onExit,
    required this.onSelectAll,
    required this.onDelete,
  });

  final int count;
  final int total;
  final VoidCallback onExit;
  final VoidCallback onSelectAll;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Row(
          children: [
            IconButton(
              tooltip: '退出多选',
              onPressed: onExit,
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
            Expanded(
              child: Text(
                '已选 $count 项',
                style: theme.textTheme.labelLarge,
              ),
            ),
            TextButton(
              onPressed: total > 0 && count < total ? onSelectAll : null,
              child: const Text('全选'),
            ),
            FilledButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              label: const Text('删除'),
            ),
          ],
        ),
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
    required this.onClearDownloads,
  });

  final bool busy;
  final String path;
  final VoidCallback onNewFolder;
  final VoidCallback onUpload;
  final VoidCallback onClearDownloads;

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
            IconButton(
              tooltip: '清空下载缓存',
              onPressed: busy ? null : onClearDownloads,
              icon: const Icon(Icons.cleaning_services_outlined, size: 18),
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

/// A4：目标目录选择器（只列子目录，能逐级进出；确认时返回当前目录）。
class _DirectoryPickerDialog extends StatefulWidget {
  const _DirectoryPickerDialog({
    required this.service,
    required this.title,
    required this.initialPath,
  });

  final ServerOpsFilesService service;
  final String title;
  final String initialPath;

  @override
  State<_DirectoryPickerDialog> createState() => _DirectoryPickerDialogState();
}

class _DirectoryPickerDialogState extends State<_DirectoryPickerDialog> {
  late String _path = widget.initialPath;
  List<RemoteStorageEntry> _dirs = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await widget.service.list(_path);
      if (!mounted) return;
      setState(() {
        _dirs = entries.where((e) => e.isDirectory).toList(growable: false);
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

  void _enter(RemoteStorageEntry dir) {
    setState(() {
      _path = dir.path;
      _dirs = const [];
    });
    _load();
  }

  void _up() {
    final parent = ServerOpsFilesService.parentOf(_path);
    if (parent == _path) return;
    setState(() {
      _path = parent;
      _dirs = const [];
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: double.maxFinite,
        height: 320,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '上一级',
                  onPressed: _path.isEmpty ? null : _up,
                  icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                ),
                Expanded(
                  child: Text(
                    _path.isEmpty ? '/' : '/$_path',
                    style: theme.textTheme.labelMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _dirs.isEmpty
                      ? Center(
                          child: Text(
                            '这里没有子目录，可直接选择此目录',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _dirs.length,
                          itemBuilder: (context, index) {
                            final dir = _dirs[index];
                            return ListTile(
                              dense: true,
                              leading: const Icon(
                                Icons.folder_rounded,
                                color: Color(0xFFF59E0B),
                                size: 18,
                              ),
                              title: Text(
                                dir.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _enter(dir),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _path),
          child: const Text('选择此目录'),
        ),
      ],
    );
  }
}

class _TextPreviewDialog extends StatefulWidget {
  const _TextPreviewDialog({
    required this.service,
    required this.entry,
    this.onSaved,
  });

  final ServerOpsFilesService service;
  final RemoteStorageEntry entry;

  /// 保存/恢复之后回调（让文件页刷新）。
  final Future<void> Function()? onSaved;

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
        // 编辑：能改就直接进去改（大小/编码/二进制的判断在编辑器里做，
        // 并由它把"为什么不能改"说清楚 —— 这里不重复一套规则）。
        TextButton(
          key: const ValueKey('ops-preview-edit'),
          onPressed: _error != null
              ? null
              : () async {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  await navigator.push(
                    MaterialPageRoute<void>(
                      builder: (_) => OpsFileEditorPage(
                        service: widget.service,
                        path: widget.entry.path,
                        name: widget.entry.name,
                        onSaved: widget.onSaved,
                      ),
                    ),
                  );
                },
          child: const Text('编辑'),
        ),
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

/// 「权限 / 属主」对话框的返回值。
class _PermResult {
  const _PermResult({
    required this.mode,
    required this.owner,
    required this.group,
    required this.recursive,
  });

  final String mode;
  final String owner;
  final String group;
  final bool recursive;
}

/// 「权限 / 属主」对话框：自己持有控制器，随自己的 State 一起释放。
class _PermissionsDialog extends StatefulWidget {
  const _PermissionsDialog({required this.name, required this.isDirectory});

  final String name;
  final bool isDirectory;

  @override
  State<_PermissionsDialog> createState() => _PermissionsDialogState();
}

class _PermissionsDialogState extends State<_PermissionsDialog> {
  late final TextEditingController _mode =
      TextEditingController(text: widget.isDirectory ? '755' : '644');
  final TextEditingController _owner = TextEditingController();
  final TextEditingController _group = TextEditingController();
  bool _recursive = false;

  @override
  void dispose() {
    _mode.dispose();
    _owner.dispose();
    _group.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('权限 / 属主：${widget.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _mode,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '权限（八进制，如 644 / 755）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _owner,
              decoration: const InputDecoration(
                labelText: '属主（留空即不改，如 www）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _group,
              decoration: const InputDecoration(
                labelText: '属组（留空即不改）',
                border: OutlineInputBorder(),
              ),
            ),
            if (widget.isDirectory)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _recursive,
                onChanged: (v) => setState(() => _recursive = v ?? false),
                title: const Text('连同里面的内容（递归）',
                    style: TextStyle(fontSize: 13)),
              ),
            const SizedBox(height: 6),
            Text(
              '服务端会拒绝受保护的路径（密钥/审计/它自己）。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _PermResult(
              mode: _mode.text.trim(),
              owner: _owner.text.trim(),
              group: _group.text.trim(),
              recursive: _recursive,
            ),
          ),
          child: const Text('应用'),
        ),
      ],
    );
  }
}
