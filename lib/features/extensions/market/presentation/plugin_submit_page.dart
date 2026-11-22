import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:box/features/extensions/core/builtin_plugin_pages.dart';
import 'package:box/features/extensions/core/home_plugin_core.dart';
import 'package:box/features/extensions/market/data/plugin_market_api.dart';
import 'package:box/features/extensions/market/domain/plugin_market_manifest.dart';
import '../../../../design_system/app_tokens.dart';

/// 用户投稿配置型插件（表单 / zip）。
class PluginSubmitPage extends StatefulWidget {
  const PluginSubmitPage({super.key});

  @override
  State<PluginSubmitPage> createState() => _PluginSubmitPageState();
}

class _PluginSubmitPageState extends State<PluginSubmitPage> {
  final _api = PluginMarketApi();
  final _titleCtrl = TextEditingController();
  final _subtitleCtrl = TextEditingController();
  final _slugCtrl = TextEditingController();
  final _versionCtrl = TextEditingController(text: '1.0.0');
  final _payloadCtrl = TextEditingController();
  final _changelogCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController(text: '用户投稿');

  String _actionCode = 'toast';
  String _areaCode = 'recommend';

  /// navigate 动作要打开的路由码。
  ///
  /// 路由码是 App 内部实现细节（`daily_news` / `openMusic` / `server_ops`…），
  /// 以前只让作者在自由文本框里手填 —— 填错后端不校验、点下去 App 静默 return，
  /// 等于「能提交、能过审、装了没反应」。现在改成下拉，选项直接从路由注册表取。
  String _navigateRouteCode = '';
  List<String>? _routeCodes;

  /// 声明权限（多选）。空集合 = 不申请任何权限，提交时统一发 `none`。
  final Set<String> _permissions = <String>{};
  bool _submitting = false;
  String? _error;
  List<PluginSubmissionDto> _mine = const [];
  bool _loadingMine = true;

  String? _zipName;
  List<int>? _zipBytes;

  // 动作/分区下拉项统一由插件域枚举（单一事实源）派生，不再硬编码副本。
  // 此前副本已真实漂移：video 在投稿页显示「视频」而其余页显示「影视」。
  static final Map<String, String> _actions = {
    for (final a in HomePluginActionType.displayOrder) a.name: a.label,
  };

  static final Map<String, String> _areas = {
    for (final a in HomePluginArea.displayOrder) a.name: a.label,
  };

  @override
  void initState() {
    super.initState();
    _reloadMine();
  }

  /// 填一份能直接提交通过的示例。
  ///
  /// 投稿页原先只有一堆空字段和一个「payload 填什么」的说明——第一次投稿的人
  /// 既不知道该填什么动作、也不知道 payload 长什么样，于是要么放弃、要么
  /// 提交一个必然 400 的配置。示例选 `navigate → openMusic`：不依赖任何外部
  /// URL，装上点开就是音乐页，能立刻验证整条链路。
  void _fillExample() {
    setState(() {
      // 按当前选中的动作给对应示例：给「打开网址」填一段音乐示例只会让人困惑。
      switch (_actionCode) {
        case 'openUrl':
          _titleCtrl.text = '打开我的站点（示例）';
          _subtitleCtrl.text = '在浏览器里打开一个网址';
          _slugCtrl.text = 'my-site';
          _areaCode = 'recommend';
          _payloadCtrl.text = jsonEncode({'url': 'https://box.hpa888.top'});
          _tagsCtrl.text = '示例,网址';
          break;
        case 'httpProbe':
          _titleCtrl.text = '我的服务器（示例）';
          _subtitleCtrl.text = '点一下看能不能连上';
          _slugCtrl.text = 'my-server';
          _areaCode = 'recommend';
          _payloadCtrl.text = jsonEncode({
            'url': 'https://box.hpa888.top/updates/box/android/release/version.json',
            'label': '我的服务器',
          });
          _tagsCtrl.text = '示例,监控';
          break;
        default:
          _titleCtrl.text = '音乐入口（示例）';
          _subtitleCtrl.text = '点开直达音乐播放页';
          _slugCtrl.text = 'music-entry';
          _areaCode = 'music';
          _navigateRouteCode = 'openMusic';
          _payloadCtrl.text = jsonEncode({'route': 'openMusic'});
          _tagsCtrl.text = '示例,音乐';
      }
      _permissions
        ..clear()
        ..add('none');
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _slugCtrl.dispose();
    _versionCtrl.dispose();
    _payloadCtrl.dispose();
    _changelogCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  Future<void> _reloadMine() async {
    setState(() {
      _loadingMine = true;
      _error = null;
    });
    try {
      final list = await _api.listMine();
      if (!mounted) return;
      setState(() {
        _mine = list;
        _loadingMine = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingMine = false;
      });
    }
  }

  Future<void> _pickZip() async {
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (f == null) return;
    Uint8List bytes;
    try {
      bytes = await f.readAsBytes();
    } catch (_) {
      bytes = Uint8List(0);
    }
    if (bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法读取 zip 文件')),
      );
      return;
    }
    if (bytes.length > 5 * 1024 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('zip 不能超过 5MB')),
      );
      return;
    }
    setState(() {
      _zipName = f.name;
      _zipBytes = bytes;
    });
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final tags = _tagsCtrl.text
          .split(RegExp(r'[,，\s]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final PluginSubmissionDto dto;
      if (_zipBytes != null) {
        dto = await _api.submitZip(
          zipBytes: _zipBytes!,
          fileName: _zipName ?? 'plugin.zip',
          fields: {
            if (_titleCtrl.text.trim().isNotEmpty) 'title': _titleCtrl.text.trim(),
            if (_subtitleCtrl.text.trim().isNotEmpty)
              'subtitle': _subtitleCtrl.text.trim(),
            if (_slugCtrl.text.trim().isNotEmpty) 'slug': _slugCtrl.text.trim(),
            'version': _versionCtrl.text.trim().isEmpty
                ? '1.0.0'
                : _versionCtrl.text.trim(),
            'actionCode': _actionCode,
            'areaCode': _areaCode,
            if (_payloadCtrl.text.trim().isNotEmpty)
              'payload': _payloadCtrl.text.trim(),
            if (_changelogCtrl.text.trim().isNotEmpty)
              'changelog': _changelogCtrl.text.trim(),
            'tags': tags.join(','),
            'permissions': _permissions.isEmpty ? 'none' : _permissions.join(','),
          },
        );
      } else {
        final title = _titleCtrl.text.trim();
        if (title.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请填写插件标题，或选择 zip 包')),
          );
          return;
        }
        dto = await _api.submit({
          'title': title,
          'subtitle': _subtitleCtrl.text.trim(),
          'slug': _slugCtrl.text.trim(),
          'version': _versionCtrl.text.trim().isEmpty
              ? '1.0.0'
              : _versionCtrl.text.trim(),
          'actionCode': _actionCode,
          'areaCode': _areaCode,
          'payload': _payloadCtrl.text.trim(),
          'changelog': _changelogCtrl.text.trim(),
          'tags': tags,
          'permissions':
              _permissions.isEmpty ? const ['none'] : _permissions.toList(),
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已提交审核：${dto.pluginId}'
            '${dto.hasPackage ? ' · zip ${(dto.packageSize / 1024).toStringAsFixed(1)}KB' : ''}'
            '（每日限额 5 次，待审上限 20）',
          ),
        ),
      );
      _titleCtrl.clear();
      _subtitleCtrl.clear();
      _slugCtrl.clear();
      _payloadCtrl.clear();
      _changelogCtrl.clear();
      setState(() {
        _zipBytes = null;
        _zipName = null;
      });
      await _reloadMine();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_err(e))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 委托单一事实源（含超时/断网的可读提示），不再自建弱化副本。
  String _err(Object e) => pluginMarketFriendlyError(e);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('投稿插件'),
        actions: [
          IconButton(
            onPressed: _loadingMine ? null : _reloadMine,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            '支持两种投稿：\n'
            '1) 表单配置型插件\n'
            '2) zip 包（内含 plugin.json，可选 payload.json）\n'
            '规则：每日最多 5 次；待审 ≤20；拒绝 ≥8 禁投；zip ≤5MB。\n'
            '审核通过后进入插件商店，其他人可下载安装。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTokens.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _submitting ? null : _pickZip,
            icon: const Icon(Icons.folder_zip_outlined),
            label: Text(
              _zipName == null
                  ? '选择 zip 包（可选）'
                  : '已选：$_zipName (${((_zipBytes?.length ?? 0) / 1024).toStringAsFixed(1)}KB)',
            ),
          ),
          if (_zipName != null) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: _submitting
                  ? null
                  : () => setState(() {
                        _zipName = null;
                        _zipBytes = null;
                      }),
              child: const Text('清除 zip，改用表单'),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _titleCtrl,
            decoration: InputDecoration(
              labelText: _zipBytes == null ? '标题 *' : '标题（可覆盖 plugin.json）',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _subtitleCtrl,
            decoration: const InputDecoration(
              labelText: '简介',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _slugCtrl,
            decoration: const InputDecoration(
              labelText: '短 ID（可选，自动加 user.前缀）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _versionCtrl,
            decoration: const InputDecoration(
              labelText: '版本号（更新同 ID 时递增，如 1.0.1）',
              border: OutlineInputBorder(),
              helperText: '同 pluginId 再次投稿并通过后会覆盖商店版本',
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _actionCode,
                  decoration: const InputDecoration(
                    labelText: '动作',
                    border: OutlineInputBorder(),
                  ),
                  items: _actions.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _actionCode = v);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _areaCode,
                  decoration: const InputDecoration(
                    labelText: '分区',
                    border: OutlineInputBorder(),
                  ),
                  items: _areas.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _areaCode = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_actionCode == 'navigate')
            DropdownButtonFormField<String>(
              key: ValueKey('nav-route-$_navigateRouteCode'),
              initialValue: _navigateRouteCode.isEmpty ? null : _navigateRouteCode,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'payload（要打开的页面）',
                helperText: '只能选 App 内置页面。提交时写成 {"route":"…"}，'
                    '指向不存在的页面会被服务端拒绝。',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final code in (_routeCodes ??= HomePluginRouteRegistry
                    .registeredCodes()))
                  DropdownMenuItem(
                    value: code,
                    child: Text(
                      // 裸 code 对作者没有意义：中文页面名 + code，一眼能选对。
                      '${kHomePluginRouteLabels[code] ?? code}（$code）',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _navigateRouteCode = v);
                // 单一写入口：payload 文本由路由码派生，作者不用手拼 JSON。
                _payloadCtrl.text = jsonEncode({'route': v});
              },
            )
          else
            TextField(
              controller: _payloadCtrl,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: switch (_actionCode) {
                  'openUrl' => '要打开的网址（必须 https）',
                  'httpProbe' => '网址与名称（JSON）',
                  _ => 'payload（toast 文案 / openMusic 音频地址）',
                },
                helperText: switch (_actionCode) {
                  'openUrl' =>
                    '打开前会弹确认框显示域名；只接受 https，http 与 intent:/tel: 一律拒绝。',
                  'httpProbe' =>
                    '写成 {"url":"https://…","label":"我的服务器"}。'
                        '点击时检查状态码与耗时，不下载内容。',
                  _ =>
                    'openMusic 支持纯 URL，或 '
                        '{"url":"https://…","title":"名称","autoplay":true,"loop":true}',
                },
                border: const OutlineInputBorder(),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _fillExample,
              icon: const Icon(Icons.auto_fix_high, size: 16),
              label: const Text('填入一个可用的示例'),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _tagsCtrl,
            decoration: const InputDecoration(
              labelText: '标签（逗号分隔）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          // 权限声明（如实披露）：不选 = 不申请任何权限。
          // 之前这里写死 'none'，所有投稿都是「无权限」——连网络插件也一样。
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTokens.surfaceMuted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '声明权限（不选 = 不申请）',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppTokens.textSecondary,
                        ),
                      ),
                    ),
                    if (_permissions.isNotEmpty)
                      Text(
                        '最高 ${highestPermissionRiskOf(_permissions).label}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppTokens.textTertiary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final permission in PluginPermission.values)
                      if (permission != PluginPermission.none)
                        FilterChip(
                          label: Text(
                            permission.risk == PluginPermissionRisk.high
                                ? '${permission.label} · 高'
                                : permission.label,
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: _permissions.contains(permission.name),
                          onSelected: (on) => setState(() {
                            if (on) {
                              _permissions.add(permission.name);
                            } else {
                              _permissions.remove(permission.name);
                            }
                          }),
                        ),
                  ],
                ),
                if (_permissions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    _permissions
                        .map((code) => permissionDetailsOf([code]).firstOrNull)
                        .whereType<PluginPermissionDetail>()
                        .map((d) => '${d.label}：${d.description}')
                        .join('\n'),
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: AppTokens.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _changelogCtrl,
            decoration: const InputDecoration(
              labelText: '更新说明',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_rounded),
            label: Text(_zipBytes == null ? '提交表单投稿' : '提交 zip 投稿'),
          ),
          const SizedBox(height: 20),
          Text('我的投稿', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_loadingMine)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red))
          else if (_mine.isEmpty)
            Text('暂无投稿', style: TextStyle(color: AppTokens.textSecondary))
          else
            ..._mine.map((e) {
              return Card(
                child: ListTile(
                  title: Text(e.title),
                  subtitle: Text(
                    '${e.pluginId}\n'
                    '${e.statusLabel} · v${e.version}'
                    '${e.hasPackage ? ' · ZIP' : ''}'
                    '${e.reviewNote.isEmpty ? '' : '\n${e.reviewNote}'}',
                  ),
                  isThreeLine: true,
                  trailing: e.hasPackage
                      ? const Icon(Icons.folder_zip_outlined)
                      : null,
                ),
              );
            }),
          const SizedBox(height: 12),
          Text(
            'zip 示例结构：\n'
            '  my-plugin/\n'
            '    plugin.json   # 必填\n'
            '    payload.json  # 可选\n'
            'plugin.json 字段：id/title/actionCode/areaCode/version/payload/tags…',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTokens.textTertiary,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
          ),
        ],
      ),
    );
  }
}
