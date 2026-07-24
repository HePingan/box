import 'package:flutter/material.dart';

import 'package:box/features/account/data/account_store.dart';
import 'package:box/features/account/domain/account_models.dart';
import 'package:box/features/admin/domain/admin_resource.dart';
import 'package:box/features/admin/domain/admin_resource_provider.dart';
import 'package:box/features/policy/plugin_policy.dart';

/// 管理后台「插件策略」Tab：全局/分插件/用户级远程禁用。
class PluginPolicyResourceProvider
    implements ResourceProvider<PluginPolicyPlaceholder> {
  @override
  AdminResourceType get resourceType => AdminResourceType.pluginPolicy;

  @override
  Future<List<PluginPolicyPlaceholder>> fetchAll(
    String? serverUrl,
    String? token,
  ) async =>
      const [];

  @override
  Future<PluginPolicyPlaceholder> create(
    String? serverUrl,
    String? token,
    Map<String, dynamic> data,
  ) async =>
      const PluginPolicyPlaceholder();

  @override
  Future<PluginPolicyPlaceholder> update(
    String? serverUrl,
    String? token,
    String id,
    Map<String, dynamic> data,
  ) async =>
      const PluginPolicyPlaceholder();

  @override
  Future<void> delete(String? serverUrl, String? token, String id) async {}

  @override
  Widget buildListPage({
    required BuildContext context,
    String? serverUrl,
    String? token,
  }) {
    return PluginPolicyAdminTab(serverUrl: serverUrl, token: token);
  }
}

class PluginPolicyPlaceholder extends ResourceData {
  const PluginPolicyPlaceholder();
  @override
  Map<String, dynamic> toJson() => const {};
}

class PluginPolicyAdminTab extends StatefulWidget {
  const PluginPolicyAdminTab({super.key, this.serverUrl, this.token});

  final String? serverUrl;
  final String? token;

  @override
  State<PluginPolicyAdminTab> createState() => _PluginPolicyAdminTabState();
}

class _PluginPolicyAdminTabState extends State<PluginPolicyAdminTab> {
  final _client = PluginPolicyAdminClient();
  final _userIdCtrl = TextEditingController();
  final _userMsgCtrl = TextEditingController();
  final _globalMsgCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic> _raw = const {};

  bool _pluginsAllowed = true;
  bool _forceLogout = false;
  int _ttlSec = 300;
  final Map<String, bool> _pluginAllowed = {
    PluginIds.quizAnswer: true,
    PluginIds.quizEntry: true,
    PluginIds.quizBankView: true,
  };
  final Map<String, String> _pluginMessage = {
    PluginIds.quizAnswer: '',
    PluginIds.quizEntry: '',
    PluginIds.quizBankView: '',
  };
  final Map<String, Map<String, bool>> _features = {
    PluginIds.quizAnswer: {
      PluginFeature.overlay: true,
      PluginFeature.probe: true,
      PluginFeature.ocr: true,
      PluginFeature.search: true,
    },
    PluginIds.quizEntry: {
      PluginFeature.entry: true,
      PluginFeature.probe: true,
      PluginFeature.ocr: true,
    },
    PluginIds.quizBankView: {
      PluginFeature.view: true,
      PluginFeature.cloudPush: true,
      PluginFeature.cloudPull: true,
    },
  };

  final Set<String> _userDenied = {};
  bool _userPluginsAllowed = true;

  static const _labels = {
    PluginIds.quizAnswer: '答题助手',
    PluginIds.quizEntry: '录入题目',
    PluginIds.quizBankView: '题库查看',
  };

  static const _featureLabels = {
    PluginFeature.overlay: '悬浮窗',
    PluginFeature.probe: '试捕',
    PluginFeature.ocr: 'OCR',
    PluginFeature.search: '搜题',
    PluginFeature.entry: '录入',
    PluginFeature.view: '查看',
    PluginFeature.cloudPush: '推送云端',
    PluginFeature.cloudPull: '拉取云端',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _userIdCtrl.dispose();
    _userMsgCtrl.dispose();
    _globalMsgCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = globalSessionNotifier.value;
      final serverUrl = widget.serverUrl ?? session?.serverUrl;
      final token = widget.token ?? session?.token;
      if (serverUrl == null ||
          serverUrl.isEmpty ||
          token == null ||
          token.isEmpty) {
        throw const BoxAccountException('请先以管理员账号登录');
      }
      final raw = await _client.fetchAdmin(serverUrl: serverUrl, token: token);
      _applyRaw(raw);
      if (mounted) {
        setState(() {
          _raw = raw;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _applyRaw(Map<String, dynamic> raw) {
    _pluginsAllowed = raw['pluginsAllowed'] != false;
    _forceLogout = raw['forceLogout'] == true;
    _ttlSec = int.tryParse(raw['ttlSec']?.toString() ?? '') ?? 300;
    _globalMsgCtrl.text = raw['globalMessage']?.toString() ?? '';
    final plugins = raw['plugins'];
    if (plugins is Map) {
      plugins.forEach((key, value) {
        final id = key.toString();
        if (value is! Map) return;
        _pluginAllowed[id] = value['allowed'] != false;
        _pluginMessage[id] = value['message']?.toString() ?? '';
        final features = value['features'];
        if (features is Map) {
          final map = _features.putIfAbsent(id, () => <String, bool>{});
          features.forEach((fk, fv) {
            map[fk.toString()] = fv == true;
          });
        }
      });
    }
  }

  Future<void> _saveGlobal() async {
    setState(() => _saving = true);
    try {
      final session = globalSessionNotifier.value;
      final serverUrl = widget.serverUrl ?? session?.serverUrl ?? '';
      final token = widget.token ?? session?.token ?? '';
      final body = {
        'pluginsAllowed': _pluginsAllowed,
        'globalMessage': _globalMsgCtrl.text.trim(),
        'ttlSec': _ttlSec,
        'forceLogout': _forceLogout,
        'plugins': {
          for (final id in _pluginAllowed.keys)
            id: {
              'allowed': _pluginAllowed[id] == true,
              'message': _pluginMessage[id] ?? '',
              'features': _features[id] ?? {},
            },
        },
      };
      final raw = await _client.putGlobal(
        serverUrl: serverUrl,
        token: token,
        body: body,
      );
      _applyRaw(raw);
      await PluginPolicyStore.instance.refresh(force: true);
      if (mounted) {
        setState(() {
          _raw = raw;
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已保存策略 v${raw['version'] ?? ''}')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
    }
  }

  Future<void> _saveUser() async {
    final userId = _userIdCtrl.text.trim();
    if (userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写用户 ID')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final session = globalSessionNotifier.value;
      final serverUrl = widget.serverUrl ?? session?.serverUrl ?? '';
      final token = widget.token ?? session?.token ?? '';
      await _client.putUserPlugins(
        serverUrl: serverUrl,
        token: token,
        userId: userId,
        body: {
          'pluginsAllowed': _userPluginsAllowed,
          'deniedPluginIds': _userDenied.toList(),
          'message': _userMsgCtrl.text.trim(),
        },
      );
      await PluginPolicyStore.instance.refresh(force: true);
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('用户策略已更新')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('用户策略失败：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '全局策略  ·  v${_raw['version'] ?? '-'}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('允许使用插件'),
                  subtitle: const Text('关闭后全员插件高风险能力不可用'),
                  value: _pluginsAllowed,
                  onChanged: (v) => setState(() => _pluginsAllowed = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('强制重新登录'),
                  value: _forceLogout,
                  onChanged: (v) => setState(() => _forceLogout = v),
                ),
                TextField(
                  controller: _globalMsgCtrl,
                  decoration: const InputDecoration(
                    labelText: '全局提示文案',
                    hintText: '管理员已禁止使用插件',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('缓存 TTL(秒)'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Slider(
                        value: _ttlSec.toDouble().clamp(30, 3600),
                        min: 30,
                        max: 3600,
                        divisions: 119,
                        label: '$_ttlSec',
                        onChanged: (v) => setState(() => _ttlSec = v.round()),
                      ),
                    ),
                    Text('$_ttlSec'),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        ..._pluginAllowed.keys.map(_buildPluginCard),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '用户级禁用',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _userIdCtrl,
                  decoration: const InputDecoration(
                    labelText: '用户 ID（如 u_xxx）',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('该用户允许使用插件'),
                  value: _userPluginsAllowed,
                  onChanged: (v) => setState(() => _userPluginsAllowed = v),
                ),
                Wrap(
                  spacing: 8,
                  children: _labels.entries.map((e) {
                    final selected = _userDenied.contains(e.key);
                    return FilterChip(
                      label: Text(e.value),
                      selected: selected,
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            _userDenied.add(e.key);
                          } else {
                            _userDenied.remove(e.key);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _userMsgCtrl,
                  decoration: const InputDecoration(
                    labelText: '用户提示',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: _saving ? null : _saveUser,
                    child: const Text('保存用户策略'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _saving ? null : _saveGlobal,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_rounded),
          label: Text(_saving ? '保存中…' : '保存全局/插件策略'),
        ),
        const SizedBox(height: 8),
        Text(
          '远程禁止 > 本地开关。投稿/拉取 API 服务端会二次校验。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.black54,
              ),
        ),
      ],
    );
  }

  Widget _buildPluginCard(String id) {
    final title = _labels[id] ?? id;
    final allowed = _pluginAllowed[id] == true;
    final features = _features[id] ?? <String, bool>{};
    final msgCtrl = TextEditingController(text: _pluginMessage[id] ?? '');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(title),
              subtitle: Text(id, style: const TextStyle(fontSize: 11)),
              value: allowed,
              onChanged: (v) => setState(() => _pluginAllowed[id] = v),
            ),
            TextField(
              controller: msgCtrl,
              decoration: const InputDecoration(
                labelText: '禁用提示',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => _pluginMessage[id] = v,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: features.keys.map((fk) {
                final on = features[fk] == true;
                return FilterChip(
                  label: Text(_featureLabels[fk] ?? fk),
                  selected: on,
                  onSelected: allowed
                      ? (v) => setState(() => features[fk] = v)
                      : null,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
