import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:box/features/account/data/account_store.dart';
import 'package:box/features/account/domain/account_models.dart';
import 'package:box/features/admin/domain/admin_resource.dart';
import 'package:box/features/admin/domain/admin_resource_provider.dart';
import 'package:box/features/extensions/market/data/plugin_market_api.dart';

class PluginMarketAdminResourceProvider
    implements ResourceProvider<PluginMarketAdminPlaceholder> {
  @override
  AdminResourceType get resourceType => AdminResourceType.pluginMarket;

  @override
  Future<List<PluginMarketAdminPlaceholder>> fetchAll(
    String? serverUrl,
    String? token,
  ) async =>
      const [];

  @override
  Future<PluginMarketAdminPlaceholder> create(
    String? serverUrl,
    String? token,
    Map<String, dynamic> data,
  ) async =>
      const PluginMarketAdminPlaceholder();

  @override
  Future<PluginMarketAdminPlaceholder> update(
    String? serverUrl,
    String? token,
    String id,
    Map<String, dynamic> data,
  ) async =>
      const PluginMarketAdminPlaceholder();

  @override
  Future<void> delete(String? serverUrl, String? token, String id) async {}

  @override
  Widget buildListPage({
    required BuildContext context,
    String? serverUrl,
    String? token,
  }) {
    return const PluginMarketAdminTab();
  }
}

class PluginMarketAdminPlaceholder extends ResourceData {
  const PluginMarketAdminPlaceholder();
  @override
  Map<String, dynamic> toJson() => const {};
}

class PluginMarketAdminTab extends StatefulWidget {
  const PluginMarketAdminTab({super.key});

  @override
  State<PluginMarketAdminTab> createState() => _PluginMarketAdminTabState();
}

class _PluginMarketAdminTabState extends State<PluginMarketAdminTab> {
  final _api = PluginMarketApi();
  bool _loading = true;
  String? _error;
  AdminPluginQueue? _queue;
  String _filter = 'pending_review';
  List<Map<String, dynamic>> _reports = const [];
  // A1 批量审核：多选状态
  bool _selectMode = false;
  final Set<String> _selectedIds = {};
  bool _bulkRunning = false;

  static const _rejectTemplates = [
    '文案违规',
    '动作不合法',
    '疑似冒充官方',
    '功能无意义',
    '权限超申',
    'zip 包可疑',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = globalSessionNotifier.value;
      if (session == null || session.token.trim().isEmpty) {
        throw const BoxAccountException('请先以管理员账号登录');
      }
      final status = switch (_filter) {
        'pending_review' => 'pending_review',
        'all' => null,
        _ => null,
      };
      final queue = await _api.adminList(status: status);
      List<Map<String, dynamic>> reports = const [];
      if (_filter == 'reports') {
        reports = await _api.adminListReports(status: 'open');
      }
      if (!mounted) return;
      setState(() {
        _queue = queue;
        _reports = reports;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _preview(PluginSubmissionDto item) async {
    try {
      final data = await _api.adminPreview(item.id);
      final iconBase64 = data['iconBase64']?.toString();
      if (!mounted) return;
      final compat = data['compatibility'] is Map
          ? Map<String, dynamic>.from(data['compatibility'] as Map)
          : <String, dynamic>{};
      final checklist = data['checklist'] is Map
          ? Map<String, dynamic>.from(data['checklist'] as Map)
          : <String, dynamic>{};
      final files = (data['files'] is List)
          ? (data['files'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      final pluginJson = data['pluginJson'];
      final packageError = data['packageError']?.toString();

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.75,
            maxChildSize: 0.95,
            minChildSize: 0.4,
            builder: (_, controller) {
              return ListView(
                controller: controller,
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (iconBase64 != null && iconBase64.isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(
                            base64Decode(iconBase64),
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) => const SizedBox(
                              width: 44,
                              height: 44,
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          '预览 · ${item.title}',
                          style: Theme.of(ctx).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${item.pluginId}\n动作 ${item.actionCode} · 分区 ${item.areaCode} · v${item.version}'
                    '${item.hasPackage ? ' · ZIP ${item.packageSize}B' : ''}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  Text('兼容检查', style: Theme.of(ctx).textTheme.titleSmall),
                  ...checklist.entries.map(
                    (e) => ListTile(
                      dense: true,
                      leading: Icon(
                        e.value == true ? Icons.check_circle : Icons.cancel,
                        color: e.value == true ? Colors.green : Colors.red,
                        size: 18,
                      ),
                      title: Text(e.key, style: const TextStyle(fontSize: 13)),
                    ),
                  ),
                  ListTile(
                    dense: true,
                    title: Text(
                      'actionAllowed=${compat['actionAllowed']} · format=${compat['packageFormat']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  if (packageError != null)
                    Text(packageError,
                        style: const TextStyle(color: Colors.red, fontSize: 12)),
                  if (files.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('包内文件', style: Theme.of(ctx).textTheme.titleSmall),
                    ...files.map(
                      (f) => ListTile(
                        dense: true,
                        title: Text(
                          f['name']?.toString() ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color: f['banned'] == true ? Colors.red : null,
                          ),
                        ),
                        trailing: Text(
                          '${f['size'] ?? 0}B',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                  ],
                  if (pluginJson != null) ...[
                    const SizedBox(height: 8),
                    Text('plugin.json',
                        style: Theme.of(ctx).textTheme.titleSmall),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      color: const Color(0xFFF5F5F5),
                      child: Text(
                        const JsonEncoder.withIndent('  ')
                            .convert(pluginJson),
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (item.status == 'pending_review')
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _review(item, approve: true);
                            },
                            child: const Text('通过发布'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _review(item, approve: false);
                            },
                            child: const Text('拒绝'),
                          ),
                        ),
                      ],
                    ),
                ],
              );
            },
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('预览失败：$e')),
      );
    }
  }

  Future<void> _review(PluginSubmissionDto item, {required bool approve}) async {
    final noteCtrl = TextEditingController(
      text: approve ? '' : _rejectTemplates.first,
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? '通过并发布' : '拒绝投稿'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ID: ${item.pluginId}\n动作: ${item.actionCode}\n分区: ${item.areaCode}\n版本: ${item.version}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            if (!approve)
              Wrap(
                spacing: 6,
                children: _rejectTemplates
                    .map(
                      (t) => ActionChip(
                        label: Text(t, style: const TextStyle(fontSize: 11)),
                        onPressed: () => noteCtrl.text = t,
                      ),
                    )
                    .toList(),
              ),
            if (!approve) const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
              decoration: InputDecoration(
                labelText: approve ? '备注（可选）' : '拒绝原因',
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(approve ? '通过' : '拒绝'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.adminReview(
        submissionId: item.id,
        approve: approve,
        note: noteCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(approve ? '已发布' : '已拒绝')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败：$e')),
      );
    }
  }

  // A1: 批量审核（一次性通过/拒绝已选投稿）
  Future<void> _bulkReview({required bool approve}) async {
    if (_selectedIds.isEmpty) return;
    final noteCtrl = TextEditingController(
      text: approve ? '' : _rejectTemplates.first,
    );
    final count = _selectedIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? '批量通过并发布' : '批量拒绝'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '已选 $count 条投稿，将统一${approve ? '通过发布' : '拒绝'}。',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            if (!approve)
              Wrap(
                spacing: 6,
                children: _rejectTemplates
                    .map(
                      (t) => ActionChip(
                        label: Text(t, style: const TextStyle(fontSize: 11)),
                        onPressed: () => noteCtrl.text = t,
                      ),
                    )
                    .toList(),
              ),
            if (!approve) const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
              decoration: InputDecoration(
                labelText: approve ? '统一备注（可选）' : '统一拒绝原因',
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('确定（$count）'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _bulkRunning = true);
    try {
      final result = await _api.adminBulkReview(
        ids: _selectedIds.toList(),
        approve: approve,
        note: noteCtrl.text.trim(),
      );
      final succeeded = (result['succeeded'] as num?)?.toInt() ?? 0;
      final skipped = (result['skipped'] is List)
          ? (result['skipped'] as List).length
          : 0;
      if (!mounted) return;
      setState(() {
        _bulkRunning = false;
        _selectMode = false;
        _selectedIds.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${approve ? '已发布' : '已拒绝'} $succeeded 条'
            '${skipped > 0 ? '，跳过 $skipped 条' : ''}',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _bulkRunning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('批量操作失败：$e')),
      );
    }
  }

  Future<void> _yank(Map<String, dynamic> release) async {
    final id = release['id']?.toString() ?? '';
    if (id.isEmpty) return;
    var forceUninstall = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('下架插件'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('确定下架 $id ？'),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      '强制卸载已装用户（下次同步删除）',
                      style: TextStyle(fontSize: 13),
                    ),
                    value: forceUninstall,
                    onChanged: (v) =>
                        setLocal(() => forceUninstall = v == true),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('下架'),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;
    try {
      await _api.adminYank(
        id,
        note: '管理员下架',
        forceUninstall: forceUninstall,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(forceUninstall ? '已下架并标记强制卸载' : '已下架'),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下架失败：$e')),
      );
    }
  }

  Future<void> _banAuthor(String userId, {required bool ban}) async {
    if (userId.isEmpty) return;
    final noteCtrl = TextEditingController(text: ban ? '违规投稿' : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ban ? '禁止作者投稿' : '解除禁投'),
        content: TextField(
          controller: noteCtrl,
          decoration: const InputDecoration(
            labelText: '原因',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ban ? '禁投' : '解禁'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.adminBanAuthor(
        userId,
        ban: ban,
        note: noteCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ban ? '已禁止投稿' : '已解禁')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败：$e')),
      );
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

    final queue = _queue!;
    final pending =
        queue.items.where((e) => e.status == 'pending_review').toList();
    final others =
        queue.items.where((e) => e.status != 'pending_review').toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          Text(
            '待审 ${queue.pendingCount} · 已发布 ${queue.published.length} · '
            '今日拒绝 ${queue.rejectsToday} · 举报 ${queue.openReports} · '
            '禁投作者 ${queue.bannedAuthors.length}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.black54,
                ),
          ),
          if (queue.storage.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '${'存储 ${(int.tryParse(queue.storage['bytesUsed']?.toString() ?? '') ?? 0) / 1024 / 1024}'
                      .replaceAll(RegExp(r'(\.\d{1})\d+'), r'$1')}${'MB / '
                  '${(int.tryParse(queue.storage['limitBytes']?.toString() ?? '') ?? 0) / 1024 / 1024 / 1024}'
                      .replaceAll(RegExp(r'(\.\d{1})\d+'), r'$1')}GB · 文件 ${queue.storage['fileCount'] ?? 0}${queue.counters.isEmpty ? '' : ' · 计数 ${queue.counters.entries.take(3).map((e) => '${e.key}:${e.value}').join(' ')}'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.black45,
                    fontSize: 11,
                  ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text('待审 ${queue.pendingCount}'),
                selected: _filter == 'pending_review',
                onSelected: (_) {
                  setState(() => _filter = 'pending_review');
                  _load();
                },
              ),
              ChoiceChip(
                label: const Text('全部投稿'),
                selected: _filter == 'all',
                onSelected: (_) {
                  setState(() => _filter = 'all');
                  _load();
                },
              ),
              ChoiceChip(
                label: Text('已发布 ${queue.published.length}'),
                selected: _filter == 'published_view',
                onSelected: (_) {
                  setState(() => _filter = 'published_view');
                },
              ),
              ChoiceChip(
                label: Text('举报 ${queue.openReports}'),
                selected: _filter == 'reports',
                onSelected: (_) {
                  setState(() => _filter = 'reports');
                  _load();
                },
              ),
              ChoiceChip(
                label: const Text('运行状态'),
                selected: _filter == 'stats',
                onSelected: (_) {
                  setState(() => _filter = 'stats');
                },
              ),
              ChoiceChip(
                label: Text('审计 ${queue.audit.length}'),
                selected: _filter == 'audit',
                onSelected: (_) {
                  setState(() => _filter = 'audit');
                },
              ),
              ChoiceChip(
                label: Text('禁投 ${queue.bannedAuthors.length}'),
                selected: _filter == 'banned',
                onSelected: (_) {
                  setState(() => _filter = 'banned');
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_filter == 'stats') ...[
            Text('运行状态', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                title: const Text('包存储'),
                subtitle: Text(
                  '路径 ${queue.storage['path'] ?? '-'}\n'
                  '已用 ${queue.storage['bytesUsed'] ?? 0} B · '
                  '文件 ${queue.storage['fileCount'] ?? 0}\n'
                  '全局上限 ${queue.storage['limitBytes'] ?? 0} · '
                  '用户上限 ${queue.storage['userLimitBytes'] ?? 0}',
                ),
                isThreeLine: true,
              ),
            ),
            if (queue.counters.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('计数器', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      ...queue.counters.entries.map(
                        (e) => Text('${e.key}: ${e.value}',
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              )
            else
              const Text('暂无计数', style: TextStyle(color: Colors.black54)),
          ] else if (_filter == 'audit') ...[
            Text('最近操作', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (queue.audit.isEmpty)
              const Text('暂无审计记录')
            else
              ...queue.audit.take(40).map((a) {
                return Card(
                  child: ListTile(
                    dense: true,
                    title: Text(
                      '${a['action']} · ${a['pluginId'] ?? ''}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      '${a['actorName'] ?? ''} · ${a['note'] ?? ''}\n${a['createdAt'] ?? ''}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    isThreeLine: true,
                  ),
                );
              }),
          ] else if (_filter == 'banned') ...[
            Text('禁投作者', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (queue.bannedAuthors.isEmpty)
              const Text('暂无禁投作者')
            else
              ...queue.bannedAuthors.entries.map((e) {
                return Card(
                  child: ListTile(
                    title: Text(e.key),
                    subtitle: Text(e.value),
                    trailing: TextButton(
                      onPressed: () => _banAuthor(e.key, ban: false),
                      child: const Text('解禁'),
                    ),
                  ),
                );
              }),
          ] else if (_filter == 'reports') ...[
            Text('开放举报', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_reports.isEmpty)
              const Text('暂无举报')
            else
              ..._reports.map((r) {
                return Card(
                  child: ListTile(
                    title: Text(r['pluginId']?.toString() ?? ''),
                    subtitle: Text(
                      '${r['reporterName'] ?? ''} · ${r['reason'] ?? ''}\n${r['createdAt'] ?? ''}',
                    ),
                    isThreeLine: true,
                    trailing: TextButton(
                      onPressed: () => _yank({
                        'id': r['pluginId'],
                      }),
                      child: const Text('下架'),
                    ),
                  ),
                );
              }),
          ] else if (_filter == 'published_view') ...[
            Text('已发布插件', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (queue.published.isEmpty)
              const Text('暂无已发布插件')
            else
              ...queue.published.map((r) {
                final title = r['title']?.toString() ?? '';
                final id = r['id']?.toString() ?? '';
                final author = r['author']?.toString() ?? '';
                final authorUserId = r['authorUserId']?.toString() ?? '';
                final ver = r['version']?.toString() ?? '';
                final dl = r['downloadCount']?.toString() ?? '0';
                return Card(
                  child: ListTile(
                    title: Text(title),
                    subtitle: Text(
                      '$id · $author · v$ver · 下载 $dl'
                      '${(r['packageFormat']?.toString() == 'zip') ? ' · ZIP' : ''}'
                      '${r['forceUninstall'] == true ? ' · 强卸' : ''}',
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        if (authorUserId.isNotEmpty)
                          TextButton(
                            onPressed: () =>
                                _banAuthor(authorUserId, ban: true),
                            child: const Text('禁投'),
                          ),
                        TextButton(
                          onPressed: () => _yank(r),
                          child: const Text('下架'),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    _filter == 'pending_review' ? '待审核投稿' : '投稿列表',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (pending.isNotEmpty)
                  TextButton.icon(
                    onPressed: _bulkRunning
                        ? null
                        : () => setState(() {
                              _selectMode = !_selectMode;
                              if (!_selectMode) _selectedIds.clear();
                            }),
                    icon: Icon(
                      _selectMode
                          ? Icons.close_rounded
                          : Icons.checklist_rounded,
                      size: 18,
                    ),
                    label: Text(_selectMode ? '退出多选' : '批量审核'),
                  ),
              ],
            ),
            if (_selectMode && pending.isNotEmpty)
              _buildBulkToolbar(pending),
            const SizedBox(height: 8),
            if (pending.isEmpty && _filter == 'pending_review')
              const Text('暂无待审投稿', style: TextStyle(color: Colors.black54)),
            ...pending.map(_buildSubmissionCard),
            if (_filter == 'all') ...[
              const SizedBox(height: 12),
              Text('历史', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...others.map(_buildSubmissionCard),
            ],
          ],
        ],
      ),
    );
  }

  // A1: 批量工具栏（全选/清空 + 批量通过/拒绝）
  Widget _buildBulkToolbar(List<PluginSubmissionDto> pending) {
    final allSelected =
        pending.isNotEmpty && _selectedIds.length == pending.length;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: _bulkRunning
                ? null
                : () => setState(() {
                      if (allSelected) {
                        _selectedIds.clear();
                      } else {
                        _selectedIds
                          ..clear()
                          ..addAll(pending.map((e) => e.id));
                      }
                    }),
            child: Text(allSelected ? '清空' : '全选'),
          ),
          Text(
            '已选 ${_selectedIds.length}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const Spacer(),
          if (_bulkRunning)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else ...[
            OutlinedButton(
              onPressed: _selectedIds.isEmpty
                  ? null
                  : () => _bulkReview(approve: false),
              child: const Text('批量拒绝'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _selectedIds.isEmpty
                  ? null
                  : () => _bulkReview(approve: true),
              child: const Text('批量通过'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSubmissionCard(PluginSubmissionDto item) {
    final selectable = _selectMode && item.status == 'pending_review';
    final checked = _selectedIds.contains(item.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: selectable
            ? () => setState(() {
                  if (checked) {
                    _selectedIds.remove(item.id);
                  } else {
                    _selectedIds.add(item.id);
                  }
                })
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selectable)
                Checkbox(
                  value: checked,
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selectedIds.add(item.id);
                    } else {
                      _selectedIds.remove(item.id);
                    }
                  }),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                      '${item.pluginId}\n'
                      '作者 ${item.authorName}${item.authorUserId.isEmpty ? '' : ' (${item.authorUserId})'} · '
                      '${item.actionCode} · ${item.areaCode} · v${item.version}'
                      '${item.hasPackage ? ' · ZIP' : ''}\n'
                      '状态 ${item.statusLabel}'
                      '${item.reviewNote.isEmpty ? '' : '\n备注 ${item.reviewNote}'}',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    if (!_selectMode) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () => _preview(item),
                            child: const Text('预览'),
                          ),
                          if (item.status == 'pending_review') ...[
                            FilledButton(
                              onPressed: () => _review(item, approve: true),
                              child: const Text('通过发布'),
                            ),
                            OutlinedButton(
                              onPressed: () => _review(item, approve: false),
                              child: const Text('拒绝'),
                            ),
                          ],
                          if (item.authorUserId.isNotEmpty)
                            TextButton(
                              onPressed: () =>
                                  _banAuthor(item.authorUserId, ban: true),
                              child: const Text('禁投作者'),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
