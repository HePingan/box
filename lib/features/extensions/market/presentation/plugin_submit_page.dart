import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:box/features/extensions/market/data/plugin_market_api.dart';

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
  bool _submitting = false;
  String? _error;
  List<PluginSubmissionDto> _mine = const [];
  bool _loadingMine = true;

  String? _zipName;
  List<int>? _zipBytes;

  static const _actions = <String, String>{
    'toast': '弹出提示',
    'openDailyNews': '打开今日热闻',
    'openNovelList': '打开小说列表',
    'openVideoList': '打开视频列表',
    'openImageGenerator': '打开 AI 生图',
    'navigate': '路由跳转(payload=route)',
  };

  static const _areas = <String, String>{
    'recommend': '推荐',
    'novel': '小说',
    'video': '视频',
    'music': '音乐',
    'comic': '漫画',
  };

  @override
  void initState() {
    super.initState();
    _reloadMine();
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
    final pick = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (pick == null || pick.files.isEmpty) return;
    final f = pick.files.first;
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
            'permissions': 'none',
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
          'permissions': const ['none'],
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

  String _err(Object e) {
    if (e is PluginMarketApiException) return e.friendlyMessage;
    return e.toString();
  }

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
                  color: Colors.black54,
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
          TextField(
            controller: _payloadCtrl,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'payload（toast 文案 / navigate 路由码）',
              border: OutlineInputBorder(),
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
            const Text('暂无投稿', style: TextStyle(color: Colors.black54))
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
                  color: Colors.black45,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
          ),
        ],
      ),
    );
  }
}
