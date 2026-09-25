// 服务器运维插件（box 内置插件）：一个入口，三个页签。
//
//   服务器（默认）：各主机 CPU / 内存 / 磁盘 / 负载 / 网络 + 迷你折线；
//   文件：直连运维通道（整盘 WebDAV）的目录浏览 / 上传 / 下载 / 重命名 / 删除；
//   终端：webview 打开运维终端（Basic 认证在 onHttpAuthRequest 里应答）。
//
// 设置（地址 / 用户名 / 口令 / 终端地址）都在这里：三个页签共用同一份，
// 改完后页签重建（见各页签的 didUpdateWidget）——否则用户填了口令还得退出重进。

import 'package:flutter/material.dart';

import 'package:box/features/extensions/plugins/server_ops/files_tab.dart';
import 'package:box/features/extensions/plugins/server_ops/host_tab.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_runtime.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';
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
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('服务器运维'),
          actions: [
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
            ],
          ),
        ),
        body: settings == null
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  const ServerOpsHostTab(),
                  ServerOpsFilesTab(settings: settings),
                  ServerOpsTerminalTab(
                    settings: settings,
                    onOpenSettings: _openSettings,
                  ),
                ],
              ),
      ),
    );
  }
}

/// 连接设置。口令**默认留空**：留空 = 不改，构建注入过的就不用管这一项。
class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.settings});

  final ServerOpsSettings settings;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late final TextEditingController _baseUrl =
      TextEditingController(text: widget.settings.effectiveBaseUrl);
  late final TextEditingController _user =
      TextEditingController(text: widget.settings.effectiveUser);
  late final TextEditingController _terminalUrl =
      TextEditingController(text: widget.settings.effectiveTerminalUrl);
  final TextEditingController _password = TextEditingController();

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _baseUrl.dispose();
    _user.dispose();
    _terminalUrl.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final updated = ServerOpsSettings(
      baseUrl: _baseUrl.text,
      user: _user.text,
      // 口令留空 = 不改（避免"打开设置按保存"把已注入的口令清掉）。
      password: _password.text.isEmpty ? widget.settings.password : _password.text,
      terminalUrl: _terminalUrl.text,
    );
    try {
      await updated.save(
        baseUrl: _baseUrl.text,
        user: _user.text,
        password: _password.text.isEmpty ? null : _password.text,
        terminalUrl: _terminalUrl.text,
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

  Future<void> _clearPassword() async {
    await widget.settings.save(password: '');
    if (!mounted) return;
    Navigator.pop(context, widget.settings.password == null
        ? const ServerOpsSettings()
        : ServerOpsSettings(
            baseUrl: widget.settings.baseUrl,
            user: widget.settings.user,
            terminalUrl: widget.settings.terminalUrl,
          ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fromBuild = widget.settings.passwordFromBuild;
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
              '口令等运行期秘密优先由构建注入（OPS_DAV_*）；这里填过的会覆盖注入值。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _baseUrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'WebDAV 根地址',
                hintText: 'https://box.hpa888.top/dav',
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
                hintText: fromBuild ? '已由构建注入，留空即不改' : '留空即不改',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    fromBuild ? '当前口令来自构建注入' : '当前口令来自设置',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                if (!fromBuild)
                  TextButton(
                    onPressed: _saving ? null : _clearPassword,
                    child: const Text('清除已保存口令'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _terminalUrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '终端地址',
                hintText: 'https://box.hpa888.top/term/',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ],
            const SizedBox(height: 14),
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
