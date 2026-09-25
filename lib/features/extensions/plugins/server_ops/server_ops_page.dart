// 服务器运维插件（box 内置插件）：一个入口，三个页签 + 多服务器切换（B1）。
//
//   服务器（默认）：各主机 CPU / 内存 / 磁盘 / 负载 / 网络 + 迷你折线；
//   文件：直连运维通道（整盘 WebDAV）的目录浏览 / 上传 / 下载 / 重命名 / 删除；
//   终端：webview 打开运维终端（Basic 认证在 onHttpAuthRequest 里应答）。
//
// 多服务器模型：AppBar 上有**当前机器切换器**（显示当前 label，可切到另一台），
// 文件页 / 终端页 / 诊断都按当前选中的那台工作；设置弹层是「服务器列表 + 每台一条
// 连接」，支持新增 / 编辑 / 删除（最后一台不许删）。选择与列表都持久化
// （见 ServerOpsSettings 的 servers / selectedServerId）。

import 'package:flutter/material.dart';

import 'package:box/features/extensions/plugins/server_ops/files_tab.dart';
import 'package:box/features/extensions/plugins/server_ops/host_tab.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_diagnostics.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_request_log.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_runtime.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';
import 'package:box/features/extensions/plugins/server_ops/system_tab.dart';
import 'package:box/features/extensions/plugins/server_ops/terminal_tab.dart';

class ServerOpsPage extends StatefulWidget {
  const ServerOpsPage({super.key});

  @override
  State<ServerOpsPage> createState() => _ServerOpsPageState();
}

class _ServerOpsPageState extends State<ServerOpsPage> {
  ServerOpsSettings? _settings;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await loadServerOpsSettings();
    if (!mounted) return;
    setState(() => _settings = settings);
  }

  /// 切换当前服务器：落盘（`serverOps.dav.selected`）+ 立即换页签用的那份设置。
  Future<void> _selectServer(String id) async {
    final current = _settings;
    if (current == null || id == current.effectiveSelectedServerId) return;
    late final ServerOpsSettings updated;
    try {
      updated = await current.save(selectedServerId: id);
    } catch (e) {
      // 落盘失败也得让用户能切：这次先用内存里的选择，下次进设置再存。
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('切换没存住（$e），本次仍按新选的机器工作')),
      );
      setState(() {
        _settings = ServerOpsSettings(
          servers: current.servers,
          selectedServerId: id,
          passwords: current.passwords,
        );
      });
      return;
    }
    if (!mounted) return;
    setState(() => _settings = updated);
  }

  Future<void> _openSettings() async {
    final current = _settings ?? const ServerOpsSettings();
    final updated = await showModalBottomSheet<ServerOpsSettings>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SettingsSheet(settings: current),
    );
    if (updated == null) return;
    if (!mounted) return;
    setState(() => _settings = updated);
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('服务器运维'),
          actions: [
            if (settings != null)
              _ServerSwitcher(
                settings: settings,
                onSelected: _selectServer,
              ),
            IconButton(
              tooltip: '设置',
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.dns_outlined), text: '服务器'),
              Tab(icon: Icon(Icons.folder_outlined), text: '文件'),
              Tab(icon: Icon(Icons.terminal_rounded), text: '终端'),
              Tab(icon: Icon(Icons.memory_outlined), text: '系统'),
            ],
          ),
        ),
        body: settings == null
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  ServerOpsHostTab(settings: settings),
                  ServerOpsFilesTab(settings: settings),
                  ServerOpsTerminalTab(
                    settings: settings,
                    onOpenSettings: _openSettings,
                  ),
                  ServerOpsSystemTab(settings: settings),
                ],
              ),
      ),
    );
  }
}

/// AppBar 上的当前机器切换器：显示当前 label，展开可切到另一台。
///
/// 放在 AppBar 而不是各页签里：切换是**整页**的事 —— 文件 / 终端 / 诊断三处都跟着换，
/// 摆在一个页签里会让人以为只切了那一个页签。
class _ServerSwitcher extends StatelessWidget {
  const _ServerSwitcher({required this.settings, required this.onSelected});

  final ServerOpsSettings settings;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = settings.currentServer;
    return PopupMenuButton<String>(
      key: const ValueKey('ops-server-switcher'),
      tooltip: '切换服务器',
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final server in settings.effectiveServers)
          PopupMenuItem<String>(
            value: server.id,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                server.id == current.id
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                size: 18,
              ),
              title: Text(server.label),
              subtitle: Text(
                server.effectiveBaseUrl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.dns_outlined, size: 16),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 108),
              child: Text(
                current.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge,
              ),
            ),
            const Icon(Icons.arrow_drop_down_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}

/// 设置弹层：服务器列表 + 每台一条连接（新增 / 编辑 / 删除 / 选为当前）。
///
/// 口令只在编辑对话框里输入，且**不进列表**：只在保存时按服务器写进本机加密存储。
class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.settings});

  final ServerOpsSettings settings;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late final List<ServerOpsServer> _draft = List<ServerOpsServer>.of(
    widget.settings.effectiveServers,
  );
  late String _selectedId = widget.settings.currentServer.id;

  /// 待写入加密存储的口令：id → 新口令（空串 = 清掉这一台）。没出现的保持原样。
  final Map<String, String> _pendingPasswords = <String, String>{};

  /// 待写入的只读 API 设备令牌：同一套规矩（空串 = 清掉这一台）。
  final Map<String, String> _pendingApiTokens = <String, String>{};

  bool _saving = false;
  String? _error;

  bool _passwordPresent(String id) {
    if (_pendingPasswords.containsKey(id)) {
      return _pendingPasswords[id]!.isNotEmpty;
    }
    return widget.settings.hasPasswordFor(id);
  }

  bool _apiTokenPresent(String id) {
    if (_pendingApiTokens.containsKey(id)) {
      return _pendingApiTokens[id]!.isNotEmpty;
    }
    return widget.settings.hasApiTokenFor(id);
  }

  /// 除 [selfId] 之外、已知口令的机器：label → 口令（口令为空的机器不进表）。
  Map<String, String> _otherPasswords(String selfId) => <String, String>{
        for (final s in _draft)
          if (s.id != selfId && _storedPassword(s.id).isNotEmpty)
            s.label: _storedPassword(s.id),
      };

  String _storedPassword(String id) {
    if (_pendingPasswords.containsKey(id)) return _pendingPasswords[id]!;
    return widget.settings.passwordFor(id);
  }

  String _storedApiToken(String id) {
    if (_pendingApiTokens.containsKey(id)) return _pendingApiTokens[id]!;
    return widget.settings.apiTokenFor(id);
  }

  Future<void> _edit(int index, {String? storedPassword}) async {
    final server = _draft[index];
    final result = await showDialog<_ServerEditResult>(
      context: context,
      builder: (_) => _ServerEditDialog(
        server: server,
        storedPassword: storedPassword ?? _storedPassword(server.id),
        storedApiToken: _storedApiToken(server.id),
        otherPasswords: _otherPasswords(server.id),
      ),
    );
    if (result == null) return;
    if (!mounted) return;
    setState(() {
      _draft[index] = result.server;
      if (result.newPassword != null) {
        _pendingPasswords[result.server.id] = result.newPassword!;
      }
      if (result.newApiToken != null) {
        _pendingApiTokens[result.server.id] = result.newApiToken!;
      }
    });
  }

  Future<void> _add() async {
    final id = ServerOpsSettings.nextServerId(_draft.map((s) => s.id));
    final result = await showDialog<_ServerEditResult>(
      context: context,
      builder: (_) => _ServerEditDialog(
        server: ServerOpsServer(id: id, label: '新服务器', baseUrl: ''),
        storedPassword: '',
        storedApiToken: '',
        otherPasswords: _otherPasswords(id),
      ),
    );
    if (result == null) return;
    if (!mounted) return;
    setState(() {
      _draft.add(result.server);
      if (result.newPassword != null && result.newPassword!.isNotEmpty) {
        _pendingPasswords[result.server.id] = result.newPassword!;
      }
      if (result.newApiToken != null && result.newApiToken!.isNotEmpty) {
        _pendingApiTokens[result.server.id] = result.newApiToken!;
      }
    });
  }

  Future<void> _delete(ServerOpsServer server) async {
    // 一台都不剩就没得连了：删到最后一台必须拦住。
    if (_draft.length <= 1) {
      _toast('最后一台服务器不能删');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「${server.label}」'),
        content: const Text(
          '只会从本机设置里移掉这一台；它保存的口令也会一并清掉。\n'
          '服务端上的东西不受影响。',
        ),
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
    if (ok != true) return;
    if (!mounted) return;
    setState(() {
      _draft.removeWhere((s) => s.id == server.id);
      _pendingPasswords[server.id] = '';
      _pendingApiTokens[server.id] = '';
      if (_selectedId == server.id) _selectedId = _draft.first.id;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await widget.settings.save(
        servers: _draft,
        selectedServerId: _selectedId,
        passwords: _pendingPasswords.isEmpty ? null : _pendingPasswords,
        apiTokens: _pendingApiTokens.isEmpty ? null : _pendingApiTokens,
      );
      if (!mounted) return;
      Navigator.pop(context, updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '保存失败：$e';
      });
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(text)),
    );
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
            Text('运维通道设置', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '每台服务器一条连接。地址与用户名可留空用构建默认值；'
              '口令只存本机加密存储，安装包里不带。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '注意：这个口令等同服务器 root（整盘读写 + root shell）。'
              '服务端一旦轮换口令，旧安装包会立即失效（需要紧跟一次发版）。',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < _draft.length; i++)
              _ServerRow(
                server: _draft[i],
                selected: _draft[i].id == _selectedId,
                passwordPresent: _passwordPresent(_draft[i].id),
                apiTokenPresent: _apiTokenPresent(_draft[i].id),
                onTap: () => _edit(i),
                onSelect: () => setState(() => _selectedId = _draft[i].id),
                onDelete: () => _delete(_draft[i]),
              ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: _saving ? null : _add,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('新增服务器'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
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
      ),
    );
  }
}

/// 设置列表里的一台服务器。
class _ServerRow extends StatelessWidget {
  const _ServerRow({
    required this.server,
    required this.selected,
    required this.passwordPresent,
    required this.apiTokenPresent,
    required this.onTap,
    required this.onSelect,
    required this.onDelete,
  });

  final ServerOpsServer server;
  final bool selected;
  final bool passwordPresent;
  final bool apiTokenPresent;
  final VoidCallback onTap;
  final VoidCallback onSelect;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? Icons.check_circle_rounded : Icons.dns_outlined,
        size: 20,
        color: selected ? theme.colorScheme.primary : null,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              server.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (selected)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                '当前',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
      subtitle: Text(
        '${server.effectiveBaseUrl}\n'
        '口令：${passwordPresent ? '已在本机加密保存' : '还没配置'}'
        ' · 系统页：${apiTokenPresent ? '已配令牌' : '没配令牌'}',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
      isThreeLine: true,
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '设为当前',
            visualDensity: VisualDensity.compact,
            onPressed: onSelect,
            icon: const Icon(Icons.radio_button_unchecked, size: 18),
          ),
          IconButton(
            tooltip: '删除',
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

/// 编辑一台服务器后的结果。
class _ServerEditResult {
  const _ServerEditResult({
    required this.server,
    this.newPassword,
    this.newApiToken,
  });

  final ServerOpsServer server;

  /// null = 不改口令；空串 = 清掉已保存口令；其它 = 新口令。
  final String? newPassword;

  /// 只读 API 设备令牌（null = 不改；空串 = 清掉）。
  final String? newApiToken;
}

/// 编辑单台服务器（label / 地址 / 用户名 / 终端地址 / 口令）+ 三项目标机体检。
class _ServerEditDialog extends StatefulWidget {
  const _ServerEditDialog({
    required this.server,
    required this.storedPassword,
    this.storedApiToken = '',
    this.otherPasswords = const <String, String>{},
  });

  final ServerOpsServer server;

  /// 这台机器当前保存的口令（空 = 没配）。只用来判"留空即不改"与体检。
  final String storedPassword;

  /// 这台机器当前保存的设备令牌（空 = 没配）。与口令同理，只判"留空即不改"。
  final String storedApiToken;

  /// 其它机器已知口令：label → 口令。**只在 401 时用来提示"这个口令是别台的"**，
  /// 不参与任何比较以外的逻辑，也不显示口令本身。
  final Map<String, String> otherPasswords;

  @override
  State<_ServerEditDialog> createState() => _ServerEditDialogState();
}

class _ServerEditDialogState extends State<_ServerEditDialog> {
  late final TextEditingController _label =
      TextEditingController(text: widget.server.label);
  late final TextEditingController _baseUrl =
      TextEditingController(text: widget.server.effectiveBaseUrl);
  late final TextEditingController _user =
      TextEditingController(text: widget.server.effectiveUser);
  late final TextEditingController _terminalUrl =
      TextEditingController(text: widget.server.effectiveTerminalUrl);
  final TextEditingController _password = TextEditingController();
  late final TextEditingController _apiUrl =
      TextEditingController(text: widget.server.effectiveApiUrl);
  final TextEditingController _apiToken = TextEditingController();

  /// 标记"清掉这台上已保存的口令"。
  bool _clearPassword = false;

  /// 标记"清掉这台上已保存的设备令牌"。
  bool _clearApiToken = false;
  bool _testing = false;
  String? _error;

  /// 体检结果（为空表示还没测过）。
  List<OpsProbeResult> _probeResults = const [];

  bool get _hasStoredPassword => widget.storedPassword.isNotEmpty;
  bool get _hasStoredApiToken => widget.storedApiToken.isNotEmpty;

  @override
  void dispose() {
    _label.dispose();
    _baseUrl.dispose();
    _user.dispose();
    _terminalUrl.dispose();
    _password.dispose();
    _apiUrl.dispose();
    _apiToken.dispose();
    super.dispose();
  }

  /// 输入框里的当前值折成一台服务器（体检与保存都用它，口径一致）。
  ServerOpsServer get _draftServer => widget.server.copyWith(
        label: _label.text,
        baseUrl: _baseUrl.text,
        user: _user.text,
        terminalUrl: _terminalUrl.text,
        apiUrl: _apiUrl.text,
      );

  /// 体检要用的设备令牌：输入框填了就用新的，否则用已保存的那份。
  String get _probeApiToken {
    if (_clearApiToken) return '';
    if (_apiToken.text.isNotEmpty) return _apiToken.text;
    return widget.storedApiToken;
  }

  /// 体检要用的口令：输入框填了就用新的，否则用已保存的那份。
  String get _probePassword {
    if (_clearPassword) return '';
    if (_password.text.isNotEmpty) return _password.text;
    return widget.storedPassword;
  }

  void _submit() {
    final newPassword = _clearPassword
        ? ''
        : (_password.text.isEmpty ? null : _password.text);
    final newApiToken = _clearApiToken
        ? ''
        : (_apiToken.text.isEmpty ? null : _apiToken.text);
    Navigator.pop(
      context,
      _ServerEditResult(
        server: _draftServer,
        newPassword: newPassword,
        newApiToken: newApiToken,
      ),
    );
  }

  /// 跑三项体检。用的是**输入框里的当前值**（口令留空则用已保存的那份），
  /// 所以可以先测通再保存 —— 否则"改了地址就得先保存才能测"很容易把好配置盖掉。
  Future<void> _runProbes() async {
    setState(() {
      _testing = true;
      _probeResults = const [];
      _error = null;
    });
    final server = _draftServer;
    final password = _probePassword;
    // 体检也必须打这台机器的地址：临时折一份"只有它"的设置交给同一个接缝。
    final probeSettings = ServerOpsSettings(
      servers: [server],
      selectedServerId: server.id,
      passwords: {server.id: password},
    );
    late final List<OpsProbeResult> results;
    try {
      results = await runOpsProbesForServer(
        server: server,
        password: password,
        apiToken: _probeApiToken,
        files: serverOpsFilesService(probeSettings),
        hosts: serverOpsHostService,
        terminalProbe: serverOpsTerminalProbe,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _error = '体检没能跑完：$e';
      });
      return;
    }
    if (!mounted) return;
    final finalResults = _annotateAuthFailures(results);
    // A9：体检是"人主动跑的一次真实请求"，最该留在日志里 —— 截图时它就在面板上。
    //
    // 先记录再 setState：记录在 setState 之后的话，这一帧不会带上新日志，
    // 面板要等下一次重建才出现刚跑的结果（真机上体验就是"点了没反应"）。
    // 详情的形状是 `[标签] 人话结论`：与体检行自己的 `标签：结论` 区分开，
    // 免得同一句话在面板上出现两遍。
    for (final r in finalResults) {
      serverOpsRequestLog.record(
        OpsRequestRecord(
          entry: '体检',
          serverId: widget.server.id,
          serverLabel: widget.server.label,
          ok: r.ok,
          detail: '[${r.label}] ${r.detail}',
          duration: r.duration ?? Duration.zero,
          at: DateTime.now(),
        ),
      );
    }
    setState(() {
      _testing = false;
      _probeResults = finalResults;
    });
  }

  /// 体检里凡是 401，都顺手对照一下"这个口令是不是另一台机器的"。
  ///
  /// 多服务器最容易犯的错就是把 A 台的口令填到 B 台的地址上 —— 表现是文件与终端一片
  /// 401，屏幕上看不出是"口令打错了"还是"填错了机器"（真机反馈过）。这里拿会话里
  /// 已知的其它机器口令比一遍，命中就直接点出来；**只提示，不改用户填的东西**。
  List<OpsProbeResult> _annotateAuthFailures(List<OpsProbeResult> results) {
    final typed = _probePassword;
    if (typed.isEmpty) return results;
    final others = widget.otherPasswords.entries
        .where((e) => e.value == typed)
        .map((e) => e.key)
        .toList();
    if (others.isEmpty) return results;
    return [
      for (final r in results)
        if (!r.ok && r.detail.contains('401'))
          OpsProbeResult(
            label: r.label,
            ok: false,
            detail: '${r.detail}｜注意：这个口令是「${others.join('、')}」那台的',
          )
        else
          r,
    ];
  }

  /// 一条体检结果：图标 + 名称 + 结论。结论必须带状态码/原因，不能只说"失败"。
  /// A9：最近请求（只记元数据，不记口令 —— 见 OpsRequestRecord 的约定）。
  ///
  /// 为什么放这儿：真机出问题时用户会截这一屏，以前截图里只有一句报错，
  /// 现在自带"哪台机器 / 哪个入口 / 成不成 / 花了多久"。
  List<Widget> _recentRequests(ThemeData theme) {
    final items = serverOpsRequestLog.items;
    if (items.isEmpty) return const [];
    const shown = 8;
    final visible = items.take(shown).toList(growable: false);
    return [
      const SizedBox(height: 10),
      Row(
        children: [
          Text(
            '最近请求（共 ${items.length} 条，只记元数据）',
            style: theme.textTheme.labelMedium,
          ),
        ],
      ),
      const SizedBox(height: 4),
      for (final r in visible)
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            '${r.at.hour.toString().padLeft(2, '0')}:'
            '${r.at.minute.toString().padLeft(2, '0')}:'
            '${r.at.second.toString().padLeft(2, '0')} · '
            '${r.entry} · ${r.serverLabel} · ${r.ok ? 'OK' : '失败'} · '
            '${r.duration.inMilliseconds} ms · ${r.detail}',
            key: ValueKey('ops-recent-${r.entry}-${r.at.microsecondsSinceEpoch}'),
            style: theme.textTheme.labelSmall?.copyWith(
              color: r.ok
                  ? theme.colorScheme.outline
                  : theme.colorScheme.error,
            ),
          ),
        ),
    ];
  }

  List<Widget> _probeRow(ThemeData theme, OpsProbeResult r) => [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                r.ok ? Icons.check_circle_outline : Icons.error_outline,
                size: 16,
                color: r.ok ? Colors.green : theme.colorScheme.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${r.label}：${r.detail}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final passwordPresent = _clearPassword ? false : _hasStoredPassword;
    return AlertDialog(
      title: const Text('服务器连接'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _label,
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '阿里云 · 主服务端',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _baseUrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'WebDAV 根地址',
                  hintText: ServerOpsSettings.defaultBaseUrl,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _user,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _password,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: '口令',
                  hintText: passwordPresent
                      ? '留空即不改'
                      : '首次使用请填服务端运维通道口令',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _clearPassword
                          ? '保存后会清掉这台机器已保存的口令'
                          : passwordPresent
                              ? '口令已在本机加密保存（不随安装包分发）'
                              : '还没配置口令',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                  if (passwordPresent && !_clearPassword)
                    TextButton(
                      onPressed: _testing
                          ? null
                          : () => setState(() => _clearPassword = true),
                      child: const Text('清除已保存口令'),
                    )
                  else if (_clearPassword)
                    TextButton(
                      onPressed: () => setState(() => _clearPassword = false),
                      child: const Text('撤销清除'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _terminalUrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: '终端地址',
                  hintText: ServerOpsSettings.defaultTerminalUrl,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _apiUrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: '只读接口地址（C2）',
                  hintText: 'https://box.hpa888.top/opsapi175',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _apiToken,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: '设备令牌（只读接口用）',
                  hintText: _clearApiToken
                      ? '已标记清除，保存后失效'
                      : (_hasStoredApiToken ? '留空即不改' : '与服务端口令不是一回事'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Checkbox(
                    value: _clearApiToken,
                    onChanged: (v) => setState(() => _clearApiToken = v ?? false),
                  ),
                  const Expanded(
                    child: Text('清掉这台上已保存的令牌', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _testing ? null : _runProbes,
                    icon: _testing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check, size: 16),
                    label: const Text('测试连接'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '分别测：文件通道 / 终端 / 主机快照 / 只读接口',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ),
              for (final r in _probeResults) ..._probeRow(theme, r),
              ..._recentRequests(theme),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('确定')),
      ],
    );
  }
}
