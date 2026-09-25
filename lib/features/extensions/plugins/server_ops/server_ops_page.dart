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
import 'package:box/features/extensions/plugins/server_ops/server_ops_diagnostics.dart';
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
  bool _testing = false;
  String? _error;

  /// 体检结果（为空表示还没测过）。
  List<OpsProbeResult> _probeResults = const [];

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

  /// 跑三项体检。用的是**输入框里的当前值**（口令留空则用已生效的那份），
  /// 所以可以先测通再保存 —— 否则"改了地址就得先保存才能测"很容易把好配置盖掉。
  Future<void> _runProbes() async {
    setState(() {
      _testing = true;
      _probeResults = const [];
      _error = null;
    });
    final probeSettings = ServerOpsSettings(
      baseUrl: _baseUrl.text,
      user: _user.text,
      password: _password.text.isEmpty ? widget.settings.password : _password.text,
      terminalUrl: _terminalUrl.text,
    );
    late final List<OpsProbeResult> results;
    try {
      results = await runOpsProbes(
        files: serverOpsFilesService(probeSettings),
        hosts: serverOpsHostService,
        terminalUrl: probeSettings.effectiveTerminalUrl,
        user: probeSettings.effectiveUser,
        password: probeSettings.effectivePassword,
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
    setState(() {
      _testing = false;
      _probeResults = results;
    });
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

  /// 一条体检结果：图标 + 名称 + 结论。结论必须带状态码/原因，不能只说"失败"。
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
    final hasPassword = widget.settings.hasPassword;
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
              '地址与用户名可留空用构建默认值；口令只存本机加密存储，安装包里不带。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '注意：这个口令等同服务器 root（整盘读写 + root shell）。'
              '带在安装包里的口令能被反编译取出，所以别把安装包外传；'
              '服务端一旦轮换口令，旧安装包会立即失效（需要紧跟一次发版）。',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.error,
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
                hintText: hasPassword ? '留空即不改' : '首次使用请填服务端运维通道口令',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    hasPassword ? '口令已在本机加密保存（不随安装包分发）' : '还没配置口令',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                if (hasPassword)
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
                    '分别测文件通道 / 终端 / 主机快照',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
            for (final r in _probeResults) ..._probeRow(theme, r),
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
