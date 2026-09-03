import 'package:flutter/material.dart';

import 'package:box/features/account/data/account_store.dart';
import 'package:box/features/account/domain/account_models.dart';
import 'package:box/features/admin/domain/admin_resource.dart';
import 'package:box/features/admin/domain/admin_resource_provider.dart';
import 'package:box/features/admin/domain/announcement_admin_draft.dart';
import 'package:box/features/cloud_sync/data/cloud_sync_client.dart';

class AnnouncementResourceProvider implements ResourceProvider<ResourceData> {
  @override
  AdminResourceType get resourceType => AdminResourceType.announcement;

  @override
  Future<List<ResourceData>> fetchAll(String? serverUrl, String? token) async =>
      const [];
  @override
  Future<ResourceData> create(
    String? serverUrl,
    String? token,
    Map<String, dynamic> data,
  ) async => const _AnnouncementPlaceholder();
  @override
  Future<ResourceData> update(
    String? serverUrl,
    String? token,
    String id,
    Map<String, dynamic> data,
  ) async => const _AnnouncementPlaceholder();
  @override
  Future<void> delete(String? serverUrl, String? token, String id) async {}

  @override
  Widget buildListPage({
    required BuildContext context,
    String? serverUrl,
    String? token,
  }) => AnnouncementAdminTab(serverUrl: serverUrl, token: token);
}

class _AnnouncementPlaceholder extends ResourceData {
  const _AnnouncementPlaceholder();
  @override
  Map<String, dynamic> toJson() => const {};
}

class AnnouncementAdminTab extends StatefulWidget {
  const AnnouncementAdminTab({super.key, this.serverUrl, this.token});
  final String? serverUrl;
  final String? token;

  @override
  State<AnnouncementAdminTab> createState() => _AnnouncementAdminTabState();
}

class _AnnouncementAdminTabState extends State<AnnouncementAdminTab> {
  final _client = CloudSyncAdminClient();
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  ({String serverUrl, String token}) _credentials() {
    final session = globalSessionNotifier.value;
    final serverUrl = widget.serverUrl ?? session?.serverUrl ?? '';
    final token = widget.token ?? session?.token ?? '';
    if (serverUrl.isEmpty || token.isEmpty) {
      throw const BoxAccountException('请先以管理员账号登录');
    }
    return (serverUrl: serverUrl, token: token);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = _credentials();
      final raw = await _client.listAnnouncements(
        serverUrl: auth.serverUrl,
        token: auth.token,
      );
      final rows = raw['announcements'];
      if (!mounted) return;
      setState(() {
        _items = rows is List
            ? rows
                  .whereType<Map>()
                  .map((row) => Map<String, dynamic>.from(row))
                  .toList()
            : const [];
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _edit([Map<String, dynamic>? item]) async {
    final result = await showModalBottomSheet<_AnnouncementEditResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AnnouncementEditor(item: item),
    );
    if (result == null) return;
    try {
      final auth = _credentials();
      if (item == null) {
        await _client.createAnnouncement(
          serverUrl: auth.serverUrl,
          token: auth.token,
          title: result.payload['title'] as String,
          body: result.payload['body'] as String,
          level: result.payload['level'] as String,
          pinned: result.payload['pinned'] as bool,
          linkUrl: result.payload['linkUrl'] as String,
          published: result.published,
        );
      } else {
        await _client.updateAnnouncement(
          serverUrl: auth.serverUrl,
          token: auth.token,
          id: item['id'].toString(),
          patch: result.payload,
        );
      }
      await _load();
      if (mounted) _snack(result.published ? '公告已发布' : '草稿已保存');
    } catch (e) {
      if (mounted) _snack('保存失败：$e');
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除公告？'),
        content: Text('「${item['title']}」将从管理列表和用户端移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final auth = _credentials();
      await _client.deleteAnnouncement(
        serverUrl: auth.serverUrl,
        token: auth.token,
        id: item['id'].toString(),
      );
      await _load();
      if (mounted) _snack('公告已删除');
    } catch (e) {
      if (mounted) _snack('删除失败：$e');
    }
  }

  Future<void> _togglePinned(Map<String, dynamic> item) async {
    try {
      final auth = _credentials();
      await _client.updateAnnouncement(
        serverUrl: auth.serverUrl,
        token: auth.token,
        id: item['id'].toString(),
        patch: {'pinned': item['pinned'] != true},
      );
      await _load();
    } catch (e) {
      if (mounted) _snack('更新失败：$e');
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.campaign_outlined),
              title: Text('公告 ${_items.length} 条'),
              subtitle: const Text('草稿不会显示给用户；warning 会在启动时弹窗。'),
              trailing: FilledButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('新建'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('还没有公告')),
            ),
          ..._items.map(_buildItem),
        ],
      ),
    );
  }

  Widget _buildItem(Map<String, dynamic> item) {
    final published = item['published'] != false;
    final level = AnnouncementLevel.fromApi(item['level']?.toString());
    return Card(
      child: ListTile(
        isThreeLine: true,
        leading: Icon(
          level == AnnouncementLevel.warning
              ? Icons.warning_amber_rounded
              : Icons.campaign_outlined,
        ),
        title: Text(item['title']?.toString() ?? ''),
        subtitle: Text(
          '${published ? '已发布' : '草稿'} · ${level.label}${item['pinned'] == true ? ' · 已置顶' : ''}\n${item['body']?.toString() ?? ''}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => _edit(item),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'edit') _edit(item);
            if (value == 'pin') _togglePinned(item);
            if (value == 'delete') _delete(item);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('编辑')),
            PopupMenuItem(
              value: 'pin',
              child: Text(item['pinned'] == true ? '取消置顶' : '置顶'),
            ),
            const PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementEditResult {
  const _AnnouncementEditResult(this.payload, this.published);
  final Map<String, dynamic> payload;
  final bool published;
}

class _AnnouncementEditor extends StatefulWidget {
  const _AnnouncementEditor({this.item});
  final Map<String, dynamic>? item;
  @override
  State<_AnnouncementEditor> createState() => _AnnouncementEditorState();
}

class _AnnouncementEditorState extends State<_AnnouncementEditor> {
  late final TextEditingController _title = TextEditingController(
    text: widget.item?['title']?.toString() ?? '',
  );
  late final TextEditingController _body = TextEditingController(
    text: widget.item?['body']?.toString() ?? '',
  );
  late final TextEditingController _link = TextEditingController(
    text: widget.item?['linkUrl']?.toString() ?? '',
  );
  late AnnouncementLevel _level = AnnouncementLevel.fromApi(
    widget.item?['level']?.toString(),
  );
  late bool _pinned = widget.item?['pinned'] == true;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _link.dispose();
    super.dispose();
  }

  void _submit(bool published) {
    final draft = AnnouncementAdminDraft(
      title: _title.text,
      body: _body.text,
      linkUrl: _link.text,
      level: _level,
      pinned: _pinned,
    );
    final error = published ? draft.publishError : null;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.pop(
      context,
      _AnnouncementEditResult(draft.toPayload(published: published), published),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      16,
      16,
      16,
      MediaQuery.viewInsetsOf(context).bottom + 16,
    ),
    child: SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.item == null ? '新建公告' : '编辑公告',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: '标题'),
            ),
            TextField(
              controller: _body,
              minLines: 5,
              maxLines: 10,
              decoration: const InputDecoration(labelText: '正文'),
            ),
            TextField(
              controller: _link,
              decoration: const InputDecoration(labelText: '链接（可选）'),
            ),
            DropdownButtonFormField<AnnouncementLevel>(
              initialValue: _level,
              decoration: const InputDecoration(labelText: '级别'),
              items: AnnouncementLevel.values
                  .map((v) => DropdownMenuItem(value: v, child: Text(v.label)))
                  .toList(),
              onChanged: (v) => setState(() => _level = v!),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _pinned,
              title: const Text('置顶'),
              onChanged: (v) => setState(() => _pinned = v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _submit(false),
                    child: const Text('存为草稿'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _submit(true),
                    child: const Text('发布'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
