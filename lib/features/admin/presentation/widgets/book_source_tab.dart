import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../design_system/app_tokens.dart';
import '../../../../novel/core/novel_source_factory.dart';
import '../../../../novel/pages/source_manager/book_source_manager.dart';
import '../../../../novel/pages/source_manager/book_source_model.dart';
import '../../domain/admin_resource.dart';
import '../../domain/admin_resource_provider.dart';

/// 小说书源资源提供者
///
/// 管理本地 `BookSourceManager` 中的书源列表。
/// 支持导入、导出、开关、删除、测试和诊断。
class BookSourceResourceProvider implements ResourceProvider<ResourceData> {
  @override
  AdminResourceType get resourceType => AdminResourceType.bookSource;

  @override
  Future<List<ResourceData>> fetchAll(String? serverUrl, String? token) async {
    return [];
  }

  @override
  Future<ResourceData> create(
    String? serverUrl,
    String? token,
    Map<String, dynamic> data,
  ) {
    throw UnimplementedError('书源管理暂不支持云端创建');
  }

  @override
  Future<ResourceData> update(
    String? serverUrl,
    String? token,
    String id,
    Map<String, dynamic> data,
  ) {
    throw UnimplementedError('书源管理暂不支持云端更新');
  }

  @override
  Future<void> delete(String? serverUrl, String? token, String id) {
    throw UnimplementedError('书源管理暂不支持云端删除');
  }

  @override
  Widget buildListPage({
    required BuildContext context,
    String? serverUrl,
    String? token,
  }) {
    return _BookSourceTab(serverUrl: serverUrl ?? '', token: token ?? '');
  }
}

/// 书源管理 Tab
class _BookSourceTab extends StatefulWidget {
  final String serverUrl;
  final String token;

  const _BookSourceTab({
    required this.serverUrl,
    required this.token,
  });

  @override
  State<_BookSourceTab> createState() => _BookSourceTabState();
}

class _BookSourceTabState extends State<_BookSourceTab> {
  String _keyword = '';
  bool _batchMode = false;
  final Set<String> _selectedIds = {};

  int _refreshKey = 0;

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  BookSourceManager get _manager => context.read<BookSourceManager>();

  void _exitBatch() {
    setState(() {
      _batchMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelectAll(List<BookSourceModel> items) {
    setState(() {
      if (_selectedIds.length == items.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(items.map((s) => s.id));
      }
    });
  }

  Future<void> _batchToggleEnabled(List<BookSourceModel> items, bool enabled) async {
    final target = items.where((s) => _selectedIds.contains(s.id)).toList();
    for (final source in target) {
      await _manager.addOrUpdate(source.copyWith(enabled: enabled));
    }
    _showSnack('已${enabled ? "启用" : "禁用"} ${target.length} 个书源');
    _exitBatch();
  }

  Future<void> _batchDelete(List<BookSourceModel> items) async {
    final target = items.where((s) => _selectedIds.contains(s.id)).toList();
    if (target.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除 ${target.length} 个书源？'),
        content: const Text('此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              '删除 ${target.length} 个',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    for (final source in target) {
      await _manager.deleteById(source.id);
    }
    _showSnack('已删除 ${target.length} 个书源');
    _exitBatch();
  }

  // ── Dialogs ──

  Future<void> _showImportDialog() async {
    final inputController = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) {
        final maxDialogHeight = MediaQuery.sizeOf(context).height * 0.72;
        return AlertDialog(
          title: const Text('导入书源规则 JSON'),
          content: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxDialogHeight),
            child: SizedBox(
              width: 580,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '粘贴单个书源、书源数组，或按空行分隔的多个 JSON。',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: TextField(
                      controller: inputController,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        labelText: '书源规则 JSON',
                        hintText:
                            '[{"bookSourceName": "...", "bookSourceUrl": "..."}]',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: null,
                      style: const TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, inputController.text.trim()),
              child: const Text('导入并检查'),
            ),
          ],
        );
      },
    );
    inputController.dispose();
    if (text == null || text.isEmpty) return;

    await _importSources(text);
  }

  Future<void> _importSources(String raw) async {
    final manager = _manager;

    final blocks = raw
        .split(RegExp(r'\n\s*\n'))
        .map((b) => b.trim())
        .where((b) => b.isNotEmpty)
        .toList();

    int added = 0;
    int skipped = 0;

    for (final block in blocks) {
      dynamic parsed;
      try {
        parsed = jsonDecode(block);
      } catch (_) {
        try {
          parsed = jsonDecode('[$block]');
        } catch (_) {
          skipped++;
          continue;
        }
      }

      final sources = <Map<String, dynamic>>[];
      if (parsed is List) {
        for (final item in parsed) {
          if (item is Map<String, dynamic>) {
            sources.add(item);
          } else if (item is Map) {
            sources.add(Map<String, dynamic>.from(item));
          }
        }
      } else if (parsed is Map<String, dynamic>) {
        sources.add(parsed);
      } else if (parsed is Map) {
        sources.add(Map<String, dynamic>.from(parsed));
      }

      for (final json in sources) {
        if (!json.containsKey('bookSourceName') ||
            !json.containsKey('bookSourceUrl')) {
          skipped++;
          continue;
        }
        try {
          final model = BookSourceModel.fromJson(json);
          await manager.addOrUpdate(model);
          added++;
        } catch (_) {
          skipped++;
        }
      }
    }

    _showSnack(added > 0 ? '成功导入 $added 个书源' : '没有导入任何书源');
    if (skipped > 0) {
      _showSnack('$skipped 个格式不符合要求已跳过');
    }
  }

  Future<void> _deleteSource(BookSourceModel source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除 ${source.bookSourceName}？'),
        content: const Text('此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _manager.deleteById(source.id);
    _showSnack('已删除 ${source.bookSourceName}');
  }

  Future<void> _toggleEnabled(BookSourceModel source) async {
    final updated = source.copyWith(enabled: !source.enabled);
    await _manager.addOrUpdate(updated);
  }

  Future<void> _setActive(BookSourceModel source) async {
    await _manager.setCurrentSource(source.id);

    if (!mounted) return;
    _showSnack('已切换到书源：${source.bookSourceName}');
  }

  Future<void> _exportSource(BookSourceModel source) async {
    await Clipboard.setData(
      ClipboardData(
        text: const JsonEncoder.withIndent('  ').convert(source.toJson()),
      ),
    );
    if (!mounted) return;
    _showSnack('已复制书源：${source.bookSourceName}');
  }

  Future<void> _previewSource(BookSourceModel source) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(source.toJson()),
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _testSource(BookSourceModel source) async {
    final keywordController = TextEditingController(text: '斗罗');
    final keyword = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('测试书源'),
          content: TextField(
            controller: keywordController,
            decoration: const InputDecoration(
              hintText: '请输入测试搜索关键词',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, keywordController.text),
              child: const Text('开始测试'),
            ),
          ],
        );
      },
    );
    keywordController.dispose();
    if (!mounted || keyword == null || keyword.trim().isEmpty) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final sourceImpl = NovelSourceFactory.fromBookSourceJson(source.toJson());
      final books = await sourceImpl.searchBooks(keyword.trim(), page: 1);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      final preview = books.take(8).toList();
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('搜索到 ${books.length} 本'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: preview
                    .map(
                      (b) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.book_rounded, size: 20),
                        title: Text(b.title),
                        subtitle: Text(b.author),
                      ),
                    )
                    .toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showSnack('测试失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<BookSourceManager>();
    final items = manager.items;
    final currentId = manager.currentSourceId;

    final filtered = _keyword.isEmpty
        ? items
        : items
            .where((s) =>
                s.bookSourceName
                    .toLowerCase()
                    .contains(_keyword.toLowerCase()) ||
                s.bookSourceGroup
                    .toLowerCase()
                    .contains(_keyword.toLowerCase()))
            .toList();

    return Column(
      children: [
        // ── 批量操作栏 ──
        if (_batchMode)
          Container(
            color: AppTokens.primaryBlue.withValues(alpha: 0.05),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  '已选 ${_selectedIds.length} / ${filtered.length}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: () => _toggleSelectAll(filtered),
                  icon: Icon(
                    _selectedIds.length == filtered.length
                        ? Icons.deselect_rounded
                        : Icons.select_all_rounded,
                    size: 18,
                  ),
                  label: Text(
                    _selectedIds.length == filtered.length ? '取消全选' : '全选',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const Spacer(),
                if (_selectedIds.isNotEmpty) ...[
                  TextButton.icon(
                    onPressed: () => _batchToggleEnabled(filtered, true),
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                    label: const Text('启用', style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: () => _batchToggleEnabled(filtered, false),
                    icon: const Icon(Icons.block_rounded, size: 18),
                    label: const Text('禁用', style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: () => _batchDelete(filtered),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: Text('删除', style: TextStyle(fontSize: 13, color: Colors.red.shade400)),
                    style: TextButton.styleFrom(foregroundColor: Colors.red.shade400),
                  ),
                ],
                const SizedBox(width: 4),
                TextButton(
                  onPressed: _exitBatch,
                  child: const Text('完成', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),

        // ── 主内容 ──
        Expanded(
          child: RefreshIndicator(
            key: ValueKey('book_source_list_$_refreshKey'),
            onRefresh: () => manager.load(),
            child: CustomScrollView(
              slivers: [
                // ── 统计 + 搜索 + 操作按钮 ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 操作行：统计
                        Row(
                          children: [
                            _statChip(
                              Icons.source_rounded,
                              '${items.length} 个书源',
                              Colors.blue,
                            ),
                            const SizedBox(width: 8),
                            _statChip(
                              Icons.check_circle_rounded,
                              '${items.where((s) => s.enabled).length} 启用',
                              Colors.green,
                            ),
                            const SizedBox(width: 8),
                            if (currentId != null)
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final name = items
                                        .where((s) => s.id == currentId)
                                        .firstOrNull
                                        ?.bookSourceName ?? '未知';
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTokens.amber.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.play_arrow_rounded,
                                            size: 14,
                                            color: AppTokens.amber,
                                          ),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              '当前：$name',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: AppTokens.amber,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // 操作行：批量 + 导入 + 搜索
                        Row(
                          children: [
                            // 批量模式切换
                            if (items.isNotEmpty)
                              SizedBox(
                                height: 36,
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      setState(() => _batchMode = !_batchMode),
                                  icon: Icon(
                                    Icons.checklist_rounded,
                                    size: 16,
                                    color: _batchMode
                                        ? AppTokens.primaryBlue
                                        : Colors.black54,
                                  ),
                                  label: Text(
                                    _batchMode ? '退出批量' : '批量',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _batchMode
                                          ? AppTokens.primaryBlue
                                          : Colors.black54,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    side: BorderSide(
                                      color: _batchMode
                                          ? AppTokens.primaryBlue
                                          : AppTokens.divider,
                                    ),
                                  ),
                                ),
                              ),
                            if (items.isNotEmpty) const SizedBox(width: 8),
                            // 导入
                            SizedBox(
                              height: 36,
                              child: FilledButton.tonalIcon(
                                onPressed: _showImportDialog,
                                icon: const Icon(Icons.add_rounded, size: 16),
                                label: const Text(
                                  '导入书源',
                                  style: TextStyle(fontSize: 12),
                                ),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // 搜索栏
                            Expanded(
                              child: TextField(
                                decoration: InputDecoration(
                                  hintText: '搜索书源名称或分组...',
                                  prefixIcon: const Icon(
                                    Icons.search_rounded,
                                    size: 18,
                                  ),
                                  suffixIcon: _keyword.isEmpty
                                      ? null
                                      : IconButton(
                                          icon: const Icon(
                                            Icons.clear_rounded,
                                            size: 16,
                                          ),
                                          onPressed: () =>
                                              setState(() => _keyword = ''),
                                        ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: AppTokens.divider,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                                style: const TextStyle(fontSize: 13),
                                onChanged: (v) => setState(() => _keyword = v),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ),

                // ── 书源列表 / 空状态 ──
                if (items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(48),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.menu_book_rounded,
                                size: 32,
                                color: Colors.blue,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '还没有书源',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '导入书源规则 JSON 后即可使用小说搜索和阅读功能',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed: _showImportDialog,
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('导入书源'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    sliver: SliverList.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final source = filtered[index];
                        final isActive = source.id == currentId;
                        final selected = _selectedIds.contains(source.id);
                        return _buildSourceCard(source, isActive, selected);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _statChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceCard(
      BookSourceModel source, bool isActive, bool selected) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isActive ? AppTokens.primaryBlue : AppTokens.divider,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _batchMode
            ? () => setState(() {
                  if (selected) {
                    _selectedIds.remove(source.id);
                  } else {
                    _selectedIds.add(source.id);
                  }
                })
            : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 批量模式：勾选框
              if (_batchMode)
                Padding(
                  padding: const EdgeInsets.only(right: 12, top: 2),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      selected
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      key: ValueKey(selected),
                      color: selected ? AppTokens.primaryBlue : Colors.grey,
                      size: 22,
                    ),
                  ),
                ),
              // 状态灯
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: source.enabled ? Colors.green : Colors.grey.shade300,
                ),
              ),
              const SizedBox(width: 10),
              // 名称 + 分组 + URL
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.bookSourceName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if (source.bookSourceGroup.isNotEmpty)
                      Text(
                        source.bookSourceGroup,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black45,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      source.bookSourceUrl,
                      style: const TextStyle(fontSize: 12, color: Colors.black45),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // 单条操作菜单（非批量模式）
              if (!_batchMode)
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_vert_rounded, size: 18),
                  onSelected: (value) async {
                    switch (value) {
                      case 'toggle':
                        await _toggleEnabled(source);
                        break;
                      case 'active':
                        await _setActive(source);
                        break;
                      case 'test':
                        await _testSource(source);
                        break;
                      case 'export':
                        await _exportSource(source);
                        break;
                      case 'preview':
                        await _previewSource(source);
                        break;
                      case 'delete':
                        await _deleteSource(source);
                        break;
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(source.enabled ? '禁用' : '启用'),
                    ),
                    if (!isActive)
                      const PopupMenuItem(
                        value: 'active',
                        child: Text('切换为当前'),
                      ),
                    const PopupMenuItem(value: 'test', child: Text('测试搜索')),
                    const PopupMenuItem(value: 'export', child: Text('导出 JSON')),
                    const PopupMenuItem(value: 'preview', child: Text('预览 JSON')),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('删除', style: TextStyle(color: Colors.red.shade400)),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
