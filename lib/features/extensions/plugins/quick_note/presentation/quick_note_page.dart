// 快速便签：把「随手记」直接写进远程存储（WebDAV）。
//
// 为什么存在远程存储而不是本地 SQLite：便签的价值是「换机/换端还在」。写进
// 远程存储的 box-notes/ 目录后，用户在远程存储浏览器里能看见、能备份、能批量
// 导出，卸载 App 也不丢；本地库则要自己做导出/迁移。
//
// 形状与 net_diag / remote_storage 插件一致：存储实现可注入（widget 测试不碰
// 网络），失败**写出原因**，不表现成「一直在转圈」。
library;

import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_back_button.dart';

import '../../remote_storage/domain/remote_storage_models.dart';
import '../../remote_storage/presentation/remote_storage_page.dart';
import '../data/quick_note_store.dart';
import '../domain/quick_note.dart';

/// 页面用的存储实例（测试可替换）。
QuickNoteStore _runtimeStore = WebdavQuickNoteStore();

/// 测试接缝；不传参恢复默认（真 WebDAV）。
void debugSetQuickNoteRuntime({QuickNoteStore? store}) {
  _runtimeStore = store ?? WebdavQuickNoteStore();
}

/// 当前生效的存储（供测试确认页面用的是注入那个）。
QuickNoteStore get debugQuickNoteStore => _runtimeStore;

class QuickNotePage extends StatefulWidget {
  const QuickNotePage({super.key});

  @override
  State<QuickNotePage> createState() => _QuickNotePageState();
}

class _QuickNotePageState extends State<QuickNotePage> {
  List<RemoteStorageAccount> _accounts = const [];
  RemoteStorageAccount? _account;
  List<QuickNote> _notes = const [];
  bool _loading = true;
  bool _busy = false;
  String _error = '';

  QuickNoteStore get _store => _runtimeStore;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final accounts = await _store.accounts();
      if (!mounted) return;
      if (accounts.isEmpty) {
        setState(() {
          _accounts = const [];
          _account = null;
          _notes = const [];
          _loading = false;
        });
        return;
      }
      final lastId = await _store.lastAccountId();
      final picked = accounts.firstWhere(
        (a) => a.id == lastId,
        orElse: () => accounts.first,
      );
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _account = picked;
      });
      await _loadNotes();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '账户读取失败：$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadNotes() async {
    final account = _account;
    if (account == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final notes = await _store.list(account);
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // 失败要写出原因，别停在加载态。
        _error = '便签读取失败：${_describe(e)}';
        _loading = false;
      });
    }
  }

  Future<void> _switchAccount(RemoteStorageAccount account) async {
    setState(() => _account = account);
    await _store.rememberAccount(account.id);
    await _loadNotes();
  }

  Future<void> _openEditor({QuickNote? note}) async {
    final account = _account;
    if (account == null) return;

    var initial = '';
    if (note != null) {
      setState(() => _busy = true);
      try {
        initial = await _store.read(account, note);
      } catch (e) {
        if (!mounted) return;
        setState(() => _busy = false);
        _snack('读取失败：${_describe(e)}');
        return;
      }
      if (!mounted) return;
      setState(() => _busy = false);
    }

    if (!mounted) return;
    final body = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _NoteEditorSheet(
        initialBody: initial,
        isNew: note == null,
      ),
    );
    if (body == null) return; // 取消
    await _save(note: note, body: body);
  }

  Future<void> _save({QuickNote? note, required String body}) async {
    final account = _account;
    if (account == null) return;
    final fileName = note?.name ??
        buildQuickNoteFileName(
          title: quickNoteTitleFromBody(body),
          existing: _notes.map((n) => n.name).toSet(),
        );
    setState(() => _busy = true);
    try {
      await _store.save(account, fileName: fileName, body: body);
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(note == null ? '已保存到远程存储' : '已更新');
      await _loadNotes();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      // 上传失败时正文还在用户的输入框之外——这里只能明确告诉没存上，
      // 不能假装成功（便签丢内容的代价比多一次重试大得多）。
      _snack('保存失败：${_describe(e)}');
    }
  }

  Future<void> _confirmDelete(QuickNote note) async {
    final account = _account;
    if (account == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除便签'),
        content: Text('将删除「${note.title}」，远程存储里的文件也会一并删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTokens.rose),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _store.delete(account, note);
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('已删除');
      await _loadNotes();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('删除失败：${_describe(e)}');
    }
  }

  String _describe(Object e) {
    final text = e.toString();
    return text.length > 160 ? '${text.substring(0, 160)}…' : text;
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.background,
      floatingActionButton: _account == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('新建便签'),
            ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  AppBackButton(onPressed: () => Navigator.maybePop(context)),
                  const SizedBox(width: 8),
                  const Text(
                    '快速便签',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (_loading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_error.isNotEmpty) {
      return _ErrorBlock(message: _error, onRetry: _boot);
    }
    if (_accounts.isEmpty) {
      return _NoAccountBlock(onAdd: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RemoteStoragePage()),
        );
        await _boot();
      });
    }
    return RefreshIndicator(
      onRefresh: _loadNotes,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _headerCard(),
          const SizedBox(height: 12),
          if (_loading && _notes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_notes.isEmpty)
            _EmptyNotesBlock(onCreate: () => _openEditor())
          else
            for (final note in _notes) ...[
              _NoteCard(
                note: note,
                busy: _busy,
                onTap: () => _openEditor(note: note),
                onDelete: () => _confirmDelete(note),
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  Widget _headerCard() {
    final account = _account;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTokens.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_accounts.length > 1)
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: account?.id,
                items: [
                  for (final a in _accounts)
                    DropdownMenuItem(
                      value: a.id,
                      child: Text(
                        a.label.isEmpty ? a.displayHost : a.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) {
                  if (id == null) return;
                  final picked = _accounts.firstWhere((a) => a.id == id);
                  _switchAccount(picked);
                },
              ),
            )
          else
            Text(
              account == null
                  ? ''
                  : (account.label.isEmpty ? account.displayHost : account.label),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          const SizedBox(height: 4),
          Text(
            '便签存在远程存储的 $kQuickNoteDir/ 目录，换手机也在；'
            '共 ${_notes.length} 条',
            style: TextStyle(fontSize: 12, color: AppTokens.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.busy,
    required this.onTap,
    required this.onDelete,
  });

  final QuickNote note;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final when = note.modifiedAt;
    final timeText = when == null
        ? note.name
        : '${when.month.toString().padLeft(2, '0')}-'
            '${when.day.toString().padLeft(2, '0')} '
            '${when.hour.toString().padLeft(2, '0')}:'
            '${when.minute.toString().padLeft(2, '0')}';
    return Material(
      color: AppTokens.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: busy ? null : onTap,
        onLongPress: busy ? null : onDelete,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTokens.cardBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.sticky_note_2_outlined, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$timeText · ${formatQuickNoteSize(note.size)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '删除',
                onPressed: busy ? null : onDelete,
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: AppTokens.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteEditorSheet extends StatefulWidget {
  const _NoteEditorSheet({required this.initialBody, required this.isNew});

  final String initialBody;
  final bool isNew;

  @override
  State<_NoteEditorSheet> createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends State<_NoteEditorSheet> {
  late final TextEditingController _controller;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialBody);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final body = _controller.text;
    if (body.trim().isEmpty) {
      setState(() => _error = '空便签不保存（写点什么再存）');
      return;
    }
    Navigator.pop(context, body);
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isNew ? '新建便签' : '编辑便签',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              widget.isNew
                  ? '第一行会写进文件名，方便在远程存储里认出来'
                  : '文件名不变（文件名就是存储路径，改名等于另存一份）',
              style: TextStyle(fontSize: 12, color: AppTokens.textSecondary),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320, minHeight: 140),
              child: TextField(
                controller: _controller,
                autofocus: true,
                maxLines: null,
                minLines: 6,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '写点什么…',
                ),
              ),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _error,
                style: const TextStyle(color: AppTokens.rose, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _submit,
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyNotesBlock extends StatelessWidget {
  const _EmptyNotesBlock({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.edit_note_outlined, size: 40, color: AppTokens.textTertiary),
          const SizedBox(height: 10),
          Text(
            '还没有便签',
            style: TextStyle(color: AppTokens.textSecondary),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onCreate, child: const Text('写第一条')),
        ],
      ),
    );
  }
}

class _NoAccountBlock extends StatelessWidget {
  const _NoAccountBlock({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_outlined, size: 44, color: AppTokens.textTertiary),
            const SizedBox(height: 12),
            const Text(
              '便签保存在远程存储里，先添加一个账户',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              '支持 WebDAV（群晖 / Nextcloud / 坚果云等）',
              style: TextStyle(fontSize: 12, color: AppTokens.textSecondary),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onAdd, child: const Text('去添加账户')),
          ],
        ),
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 40, color: AppTokens.rose),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
