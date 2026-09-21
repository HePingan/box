// 远程存储：账户首页（账户卡片、编辑面板、测试连接、传输入口）。
//
// 设计文档：docs/remote_storage_plugin_plan.md（拍板于 2026-09-20）。
// 拍板 1：命名「远程存储」；拍板 2：P0 仅上传（浏览/下载/预览/播放）；
// 拍板 5：私网 http 默认放行（卡片仅提示徽标，不拦截）。

import 'package:flutter/material.dart';

import '../application/remote_storage_service.dart';
import '../application/transfer_queue.dart';
import '../domain/remote_storage_models.dart';
import '../domain/webdav_client.dart';
import 'remote_storage_browser_page.dart';

class RemoteStoragePage extends StatefulWidget {
  const RemoteStoragePage({super.key});

  @override
  State<RemoteStoragePage> createState() => _RemoteStoragePageState();
}

class _RemoteStoragePageState extends State<RemoteStoragePage> {
  bool _loading = true;
  String _error = '';
  List<RemoteStorageAccount> _accounts = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final accounts = await remoteStorageService().loadAccounts();
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '账户读取失败：$e';
        _loading = false;
      });
    }
  }

  Future<void> _openEditor({RemoteStorageAccount? account}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => RemoteStorageAccountEditorSheet(account: account),
    );
    if (saved == true) {
      await _load();
    }
  }

  Future<void> _testConnection(RemoteStorageAccount account) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ProbeDialog(account: account),
    );
  }

  Future<void> _confirmDelete(RemoteStorageAccount account) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账户'),
        content: Text(
          '将删除「${account.label.isEmpty ? account.displayHost : account.label}」'
          '的配置与已保存密码。远端文件不受影响。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await remoteStorageService().deleteAccount(account.id);
    await _load();
  }

  void _openBrowser(RemoteStorageAccount account) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RemoteStorageBrowserPage(account: account),
      ),
    );
  }

  Future<void> _showTransfers() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const TransferQueueSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('远程存储'),
        actions: [
          IconButton(
            tooltip: '传输任务',
            onPressed: _showTransfers,
            icon: AnimatedBuilder(
              animation: transferQueue(),
              builder: (_, _) {
                final active = transferQueue().activeCount;
                return active > 0
                    ? Badge(
                        label: Text('$active'),
                        child: const Icon(Icons.swap_vert_rounded),
                      )
                    : const Icon(Icons.swap_vert_rounded);
              },
            ),
          ),
          IconButton(
            tooltip: '添加账户',
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return _ErrorView(message: _error, onRetry: _load);
    }
    if (_accounts.isEmpty) {
      return _EmptyView(onAdd: () => _openEditor());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          for (final account in _accounts) _buildAccountCard(account),
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton.icon(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('添加账户'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(RemoteStorageAccount account) {
    final theme = Theme.of(context);
    final title = account.label.isEmpty ? account.displayHost : account.label;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openBrowser(account),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  Icons.cloud_outlined,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      account.displayHost,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (account.isInsecure)
                          _MiniTag(
                            text: account.isHttp
                                ? '不安全连接（http）'
                                : '自签名证书',
                            warn: true,
                          ),
                        if (account.isHttp && account.httpEffectiveAllowed)
                          const _MiniTag(text: '局域网明文已放行'),
                        if (account.showSystemFolders)
                          const _MiniTag(text: '显示系统目录'),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '账户操作',
                onSelected: (value) {
                  switch (value) {
                    case 'browse':
                      _openBrowser(account);
                    case 'test':
                      _testConnection(account);
                    case 'edit':
                      _openEditor(account: account);
                    case 'delete':
                      _confirmDelete(account);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'browse', child: Text('浏览文件')),
                  PopupMenuItem(value: 'test', child: Text('测试连接')),
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.text, this.warn = false});

  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = warn
        ? theme.colorScheme.errorContainer.withValues(alpha: 0.55)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7);
    final fg = warn
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: theme.textTheme.labelSmall?.copyWith(color: fg)),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('还没有连接任何存储', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '支持坚果云、群晖 NAS、Nextcloud、自建 WebDAV。\n'
              '仅使用你自己的账户，凭据加密保存在本机。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('添加账户'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
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

/// 连接测试对话框：打开即测，展示诊断明细（拍板：测试连接输出诊断）。
class _ProbeDialog extends StatefulWidget {
  const _ProbeDialog({required this.account});

  final RemoteStorageAccount account;

  @override
  State<_ProbeDialog> createState() => _ProbeDialogState();
}

class _ProbeDialogState extends State<_ProbeDialog> {
  WebdavProbeResult? _result;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final result = await remoteStorageService().testConnection(widget.account);
    if (!mounted) return;
    setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    return AlertDialog(
      title: const Text('连接测试'),
      content: result == null
          ? const SizedBox(
              height: 72,
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  result.ok ? Icons.check_circle_outline : Icons.error_outline,
                  color: result.ok
                      ? Colors.green
                      : theme.colorScheme.error,
                ),
                const SizedBox(height: 8),
                Text(
                  result.ok
                      ? '连接成功，根目录可读（${result.rootEntryCount} 项）'
                      : '连接失败',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                _probeRow('OPTIONS 状态', '${result.optionsStatus ?? '未响应'}'),
                _probeRow('DAV 头', result.davHeader?.trim().isNotEmpty == true
                    ? result.davHeader!.trim()
                    : '未提供'),
                if (result.allowHeader?.trim().isNotEmpty == true)
                  _probeRow('Allow', result.allowHeader!.trim()),
                if (result.errorMessage?.trim().isNotEmpty == true)
                  _probeRow('错误', result.errorMessage!.trim()),
              ],
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _probeRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text('$label：$value', style: const TextStyle(fontSize: 12)),
    );
  }
}

/// 账户编辑面板（新增/编辑共用）。保存成功后 pop(true)。
class RemoteStorageAccountEditorSheet extends StatefulWidget {
  const RemoteStorageAccountEditorSheet({super.key, this.account});

  final RemoteStorageAccount? account;

  @override
  State<RemoteStorageAccountEditorSheet> createState() =>
      _RemoteStorageAccountEditorSheetState();
}

class _RemoteStorageAccountEditorSheetState
    extends State<RemoteStorageAccountEditorSheet> {
  late final TextEditingController _label;
  late final TextEditingController _baseUrl;
  late final TextEditingController _username;
  late final TextEditingController _password;

  late RemoteTlsMode _tlsMode;
  late bool _allowBadCert;
  late bool _showSystemFolders;

  String _error = '';
  bool _saving = false;

  bool get _isEdit => widget.account != null;

  @override
  void initState() {
    super.initState();
    final account = widget.account;
    _label = TextEditingController(text: account?.label ?? '');
    _baseUrl = TextEditingController(text: account?.baseUrl ?? '');
    _username = TextEditingController(text: account?.username ?? '');
    _password = TextEditingController(text: account?.password ?? '');
    _tlsMode = account?.tlsMode ?? RemoteTlsMode.auto;
    _allowBadCert = account?.allowBadCert ?? false;
    _showSystemFolders = account?.showSystemFolders ?? false;
  }

  @override
  void dispose() {
    _label.dispose();
    _baseUrl.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  RemoteStorageAccount _draft() {
    return RemoteStorageAccount(
      id: widget.account?.id ?? RemoteStorageAccount.newId(),
      label: _label.text.trim(),
      baseUrl: _baseUrl.text.trim(),
      username: _username.text,
      password: _password.text,
      tlsMode: _tlsMode,
      allowBadCert: _allowBadCert,
      showSystemFolders: _showSystemFolders,
      createdAt: widget.account?.createdAt ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _test() async {
    final err = RemoteStorageAccount.validateBaseUrl(_baseUrl.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() => _error = '');
    await showDialog<void>(
      context: context,
      builder: (_) => _ProbeDialog(account: _draft()),
    );
  }

  Future<void> _save() async {
    final err = RemoteStorageAccount.validateBaseUrl(_baseUrl.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    if (_username.text.trim().isEmpty) {
      setState(() => _error = '请输入用户名');
      return;
    }
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await remoteStorageService().saveAccount(_draft());
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '保存失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEdit ? '编辑账户' : '添加账户',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _baseUrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: 'https://dav.jianguoyun.com/dav/ 或 http://192.168.1.2:5005/',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _label,
              decoration: const InputDecoration(
                labelText: '名称（可选）',
                hintText: '我的坚果云',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _username,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: '用户名',
                hintText: '坚果云请填注册邮箱',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _password,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: '密码 / 应用密码',
                hintText: '坚果云需在网页端生成「应用密码」',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<RemoteTlsMode>(
              initialValue: _tlsMode,
              decoration: const InputDecoration(
                labelText: '明文连接策略',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final mode in RemoteTlsMode.values)
                  DropdownMenuItem(value: mode, child: Text(mode.label)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _tlsMode = value);
              },
            ),
            const SizedBox(height: 6),
            Text(
              '私网（192.168.x / .local / 回环）默认允许 http 与自签证书；'
              '公网地址建议保持 https。',
              style: theme.textTheme.bodySmall,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('允许自签名证书'),
              subtitle: const Text('仅对当前账户填写的主机放行'),
              value: _allowBadCert,
              onChanged: (v) => setState(() => _allowBadCert = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('显示系统目录'),
              subtitle: const Text('如群晖 @eaDir、#recycle'),
              value: _showSystemFolders,
              onChanged: (v) => setState(() => _showSystemFolders = v),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                _error,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _test,
                    icon: const Icon(Icons.wifi_tethering_rounded, size: 16),
                    label: const Text('测试连接'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined, size: 16),
                    label: const Text('保存'),
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

/// 传输任务列表（底部面板）。共享运行时队列实例。
class TransferQueueSheet extends StatelessWidget {
  const TransferQueueSheet({super.key});

  static String _statusLabel(TransferStatus status) {
    switch (status) {
      case TransferStatus.queued:
        return '排队中';
      case TransferStatus.running:
        return '传输中';
      case TransferStatus.done:
        return '已完成';
      case TransferStatus.failed:
        return '失败';
      case TransferStatus.canceled:
        return '已取消';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: transferQueue(),
      builder: (context, _) {
        final queue = transferQueue();
        final tasks = queue.tasks;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('传输任务', style: theme.textTheme.titleLarge),
                  ),
                  if (tasks.any((t) => !t.isActive))
                    TextButton(
                      onPressed: queue.clearFinished,
                      child: const Text('清空已完成'),
                    ),
                ],
              ),
              if (tasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: Text('暂无传输任务')),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: tasks.length,
                    itemBuilder: (_, i) => _buildTask(theme, tasks[i]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTask(ThemeData theme, TransferTask task) {
    final total = task.totalBytes;
    final info = task.status == TransferStatus.done
        ? formatRemoteBytes(task.receivedBytes)
        : total > 0
            ? '${formatRemoteBytes(task.receivedBytes)} / '
                '${formatRemoteBytes(total)}'
            : formatRemoteBytes(task.receivedBytes);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                task.kind == TransferKind.download
                    ? Icons.download_rounded
                    : Icons.upload_rounded,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (task.isActive)
                TextButton(
                  onPressed: task.requestCancel,
                  child: const Text('取消'),
                )
              else
                Text(
                  _statusLabel(task.status),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: task.status == TransferStatus.failed
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            task.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall,
          ),
          if (task.isActive) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: total > 0 ? task.progress : null,
              minHeight: 3,
            ),
            if (info.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(info, style: theme.textTheme.labelSmall),
              ),
          ],
          if (task.status == TransferStatus.failed &&
              task.errorMessage?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                task.errorMessage!,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
