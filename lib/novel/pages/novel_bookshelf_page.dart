import 'package:flutter/material.dart';

import '../../../design_system/app_tokens.dart';
import '../../../design_system/widgets/app_page_scaffold.dart';
import '../../../design_system/widgets/shimmer_skeleton.dart';
import '../../../design_system/widgets/empty_error_states.dart';
import '../core/bookshelf_manager.dart';
import '../core/bookshelf_group.dart';
import '../core/models.dart';
import '../core/offline_cache_service.dart';
import '../novel_module.dart';
import 'novel_detail_page.dart';
import 'offline_cache_manage_page.dart';

/// 我的书架/阅读历史页面
///
/// 显示用户收藏的书籍和最近阅读记录。
/// 支持按分组筛选和管理。
class NovelBookshelfPage extends StatefulWidget {
  const NovelBookshelfPage({super.key});

  @override
  State<NovelBookshelfPage> createState() => _NovelBookshelfPageState();
}

class _NovelBookshelfPageState extends State<NovelBookshelfPage>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  List<NovelBook> _bookshelf = [];
  bool _loading = true;

  // ── 分组状态 ──
  List<BookshelfGroup> _groups = [];
  String? _selectedGroupId; // null = 全部
  Map<String, List<String>> _groupMembers = {};

  // ── 离线缓存状态 ──
  Set<String> _offlineIds = {};
  OfflineCacheService get _offlineService => OfflineCacheService(
        cache: NovelModule.repository.cache,
        repository: NovelModule.repository,
      );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        BookshelfManager.instance.getBookshelf(),
        BookshelfGroupManager.instance.getGroups(),
        BookshelfGroupManager.instance.getMembers(),
        _offlineService.getOfflineBookIds(),
      ]);
      if (mounted) {
        setState(() {
          _bookshelf = results[0] as List<NovelBook>;
          _groups = results[1] as List<BookshelfGroup>;
          _groupMembers = results[2] as Map<String, List<String>>;
          _offlineIds = results[3] as Set<String>;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 获取筛选后的书籍列表
  List<NovelBook> get _filteredBooks {
    if (_selectedGroupId == null) return _bookshelf;
    final ids = _groupMembers[_selectedGroupId] ?? [];
    if (ids.isEmpty) return [];
    return _bookshelf
        .where((b) => ids.contains(b.id) || ids.contains(b.detailUrl))
        .toList();
  }

  // ── 分组管理 ──

  Future<void> _editGroups() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _GroupManageSheet(groups: _groups),
    );
    if (result == true && mounted) {
      _loadData();
    }
  }

  Future<void> _showGroupPicker(NovelBook book) async {
    final members = await BookshelfGroupManager.instance.getMembers();
    final currentGroups =
        _groups.where((g) => (members[g.id] ?? []).contains(book.id)).toList();

    if (!mounted) return;
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _GroupPickerSheet(
        groups: _groups,
        selectedIds: currentGroups.map((g) => g.id).toSet(),
        bookTitle: book.title,
      ),
    );

    if (result != null && mounted) {
      // 更新分组归属
      final manager = BookshelfGroupManager.instance;
      for (final g in _groups) {
        if (result.contains(g.id)) {
          await manager.addBookToGroup(g.id, book.id);
        } else {
          await manager.removeBookFromGroup(g.id, book.id);
        }
      }
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已更新《${book.title}》的分组'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
  }

  // ── 动态：获取 BookshelfGroupManager.getMembers() ──

  Future<void> _removeFromBookshelf(NovelBook book) async {
    try {
      await BookshelfManager.instance.removeFromBookshelf(book.id);
      if (mounted) {
        setState(() {
          _bookshelf.removeWhere(
            (b) => b.id == book.id || b.detailUrl == book.id,
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已移除《${book.title}》'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('移除失败: $e')),
        );
      }
    }
  }

  /// 切换离线缓存状态
  // ── 离线缓存 ──

  void _openOfflineManage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const OfflineCacheManagePage(),
      ),
    );
  }

  Future<void> _toggleOfflineCache(NovelBook book) async {
    final isCached = _offlineIds.contains(book.id);
    if (isCached) {
      await _offlineService.unmarkOfflineById(book.id);
      if (mounted) {
        setState(() => _offlineIds.remove(book.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已取消《${book.title}》的离线缓存'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } else {
      // 标记离线 — 需要 detail 来获取章节列表
      try {
        final detail = await NovelModule.repository.fetchDetail(
          bookId: book.id,
          detailUrl: book.detailUrl,
        );
        await _offlineService.markForOffline(detail);
        if (mounted) {
          setState(() => _offlineIds.add(book.id));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('《${book.title}》已加入离线缓存，后台预下载中…'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('离线缓存失败：$e'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  void _openDetail(NovelBook book) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NovelDetailPage(entryBook: book),
      ),
    ).then((_) => _loadData());
  }

  // ── UI ──

  Widget _buildGroupBar() {
    if (_groups.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _GroupChip(
            label: '全部',
            icon: Icons.select_all_rounded,
            selected: _selectedGroupId == null,
            count: _bookshelf.length,
            onTap: () => setState(() => _selectedGroupId = null),
          ),
          const SizedBox(width: 8),
          ..._groups.map((g) {
            final count = (_groupMembers[g.id] ?? [])
                .where((id) => _bookshelf.any((b) => b.id == id))
                .length;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _GroupChip(
                label: g.name,
                icon: null,
                emoji: g.icon,
                selected: _selectedGroupId == g.id,
                count: count,
                onTap: () => setState(() => _selectedGroupId = g.id),
              ),
            );
          }),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(
              Icons.tune_rounded,
              size: 18,
              color: AppTokens.textTertiary,
            ),
            onPressed: _editGroups,
            tooltip: '管理分组',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildBookshelfTab() {
    final books = _filteredBooks;
    if (_loading) return const BookshelfSkeleton();
    if (_bookshelf.isEmpty) {
      return const EmptyStateView(
        icon: Icons.menu_book_rounded,
        title: '还没有收藏的书籍',
        subtitle: '在搜索结果页长按书籍即可添加到书架',
      );
    }
    if (books.isEmpty) {
      return EmptyStateView(
        icon: Icons.filter_alt_rounded,
        title: '该分组暂无书籍',
        subtitle: '长按书架中的书籍可选择分组',
        actionLabel: '查看全部',
        onAction: () => setState(() => _selectedGroupId = null),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: books.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final book = books[index];
        return _BookshelfBookTile(
          book: book,
          onTap: () => _openDetail(book),
          onRemove: () => _removeFromBookshelf(book),
          onLongPress: () => _showGroupPicker(book),
          isCachedOffline: _offlineIds.contains(book.id),
          onToggleOfflineCache: () => _toggleOfflineCache(book),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      maxContentWidth: 660,
      safeBottom: false,
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTokens.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTokens.divider),
            ),
            child: Row(
              children: [
                Icon(Icons.menu_book_rounded, size: 20, color: AppTokens.violet),
                const SizedBox(width: 8),
                const Text(
                  '我的书架',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_bookshelf.length} 本',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTokens.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(
                    icon: Icon(
                      Icons.download_rounded,
                      size: 16,
                      color: AppTokens.textTertiary,
                    ),
                    onPressed: _openOfflineManage,
                    tooltip: '离线缓存管理',
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildGroupBar(),
          const SizedBox(height: 4),
          TabBar(
            controller: _tabController,
            indicatorColor: AppTokens.violet,
            labelColor: AppTokens.violet,
            unselectedLabelColor: AppTokens.textSecondary,
            tabs: const [
              Tab(text: '书架'),
              Tab(text: '最近'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildBookshelfTab(),
                const Center(
                  child: Text(
                    '最近阅读功能开发中...',
                    style: TextStyle(color: AppTokens.textTertiary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════
// 分组 Chip
// ═══════════════════════════════════════════

class _GroupChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final String? emoji;
  final bool selected;
  final int count;
  final VoidCallback onTap;

  const _GroupChip({
    required this.label,
    this.icon,
    this.emoji,
    required this.selected,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selected;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: isSelected ? AppTokens.violet : AppTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null)
                  Icon(icon, size: 16, color: isSelected ? Colors.white : AppTokens.textSecondary),
                if (emoji != null)
                  Text(emoji!, style: TextStyle(fontSize: 14, color: isSelected ? Colors.white : null)),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : AppTokens.textSecondary,
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.25)
                        : AppTokens.divider,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.white : AppTokens.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════
// 分组管理 BottomSheet
// ═══════════════════════════════════════════

class _GroupManageSheet extends StatefulWidget {
  final List<BookshelfGroup> groups;

  const _GroupManageSheet({required this.groups});

  @override
  State<_GroupManageSheet> createState() => _GroupManageSheetState();
}

class _GroupManageSheetState extends State<_GroupManageSheet> {
  late List<BookshelfGroup> _groups;

  @override
  void initState() {
    super.initState();
    _groups = List.from(widget.groups);
  }

  void _addGroup() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建分组'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '分组名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              final id = 'group_${DateTime.now().millisecondsSinceEpoch}';
              await BookshelfGroupManager.instance
                  .addGroup(BookshelfGroup(id: id, name: name, sortOrder: _groups.length + 1));
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                final updated = await BookshelfGroupManager.instance.getGroups();
                setState(() => _groups = updated);
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteGroup(BookshelfGroup group) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除分组'),
        content: Text('确定删除分组「${group.name}」吗？\n书籍不会被删除，只会从该分组中移除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await BookshelfGroupManager.instance.removeGroup(group.id);
      final updated = await BookshelfGroupManager.instance.getGroups();
      if (mounted) setState(() => _groups = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.8,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: AppTokens.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                const Text(
                  '管理分组',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addGroup,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('新建'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _groups.isEmpty
                ? const Center(
                    child: Text('暂无分组', style: TextStyle(color: AppTokens.textTertiary)),
                  )
                : ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _groups.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, indent: 20, endIndent: 20),
                    itemBuilder: (_, i) {
                      final g = _groups[i];
                      return ListTile(
                        leading: Text(g.icon, style: const TextStyle(fontSize: 24)),
                        title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('ID: ${g.id}', style: const TextStyle(fontSize: 11, color: AppTokens.textTertiary)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 20),
                          color: Colors.red.withValues(alpha: 0.7),
                          onPressed: () => _deleteGroup(g),
                          tooltip: '删除',
                        ),
                        onTap: () => Navigator.pop(context, true),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════
// 分组选择器 BottomSheet
// ═══════════════════════════════════════════

class _GroupPickerSheet extends StatefulWidget {
  final List<BookshelfGroup> groups;
  final Set<String> selectedIds;
  final String bookTitle;

  const _GroupPickerSheet({
    required this.groups,
    required this.selectedIds,
    required this.bookTitle,
  });

  @override
  State<_GroupPickerSheet> createState() => _GroupPickerSheetState();
}

class _GroupPickerSheetState extends State<_GroupPickerSheet> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.selectedIds);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 10),
          width: 36, height: 4,
          decoration: BoxDecoration(
            color: AppTokens.divider,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            '为《${widget.bookTitle}》选择分组',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        const Divider(height: 1),
        ...widget.groups.map((g) => CheckboxListTile(
              value: _selected.contains(g.id),
              title: Row(
                children: [
                  Text(g.icon, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Text(g.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                ],
              ),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selected.add(g.id);
                  } else {
                    _selected.remove(g.id);
                  }
                });
              },
            )),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, _selected.toList()),
              child: const Text('确定'),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════
// 书架书籍卡片
// ═══════════════════════════════════════════

class _BookshelfBookTile extends StatelessWidget {
  const _BookshelfBookTile({
    required this.book,
    required this.onTap,
    required this.onRemove,
    this.onLongPress,
    this.isCachedOffline = false,
    this.onToggleOfflineCache,
  });

  final NovelBook book;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback? onLongPress;
  final bool isCachedOffline;
  final VoidCallback? onToggleOfflineCache;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTokens.divider),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        onTap: onTap,
        onLongPress: onLongPress,
        leading: _buildCover(),
        title: Text(
          book.title.isNotEmpty ? book.title : '未知书名',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (book.author.isNotEmpty)
              Text(
                book.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppTokens.textSecondary,
                ),
              ),
            const SizedBox(height: 2),
            Row(
              children: [
                if (book.status.isNotEmpty)
                  _StatusChip(
                    text: book.status,
                    color: book.status.contains('完结')
                        ? AppTokens.emerald
                        : AppTokens.amber,
                  ),
                if (book.category.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  _StatusChip(
                    text: book.category,
                    color: AppTokens.primaryBlue,
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCachedOffline)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _StatusChip(
                  text: '已缓存',
                  color: AppTokens.emerald,
                ),
              ),
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert_rounded,
                size: 18,
                color: AppTokens.textTertiary,
              ),
              onSelected: (value) {
                if (value == 'group') onLongPress?.call();
                if (value == 'cache') onToggleOfflineCache?.call();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'group',
                  child: Row(
                    children: [
                      Icon(Icons.folder_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('分组管理'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'cache',
                  child: Row(
                    children: [
                      Icon(
                        isCachedOffline
                            ? Icons.cloud_off_rounded
                            : Icons.download_rounded,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(isCachedOffline ? '取消离线缓存' : '离线缓存'),
                    ],
                  ),
                ),
              ],
            ),
            // 移除视觉密度
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              color: AppTokens.textTertiary,
              onPressed: onRemove,
              tooltip: '移除',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover() {
    if (book.coverUrl.isNotEmpty) {
      return Container(
        width: 48,
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.10),
            width: 0.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.network(
          book.coverUrl,
          width: 48,
          height: 64,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallbackCover(),
        ),
      );
    }
    return _fallbackCover();
  }

  Widget _fallbackCover() {
    return Container(
      width: 48,
      height: 64,
      decoration: BoxDecoration(
        color: AppTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.10),
          width: 0.5,
        ),
      ),
      child: Icon(
        Icons.menu_book_rounded,
        size: 24,
        color: AppTokens.textTertiary,
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9.5,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
