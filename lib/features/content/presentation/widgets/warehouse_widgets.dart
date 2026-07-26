import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_cards.dart';
import 'package:box/features/content/domain/warehouse_models.dart';

// ═══════════════════════════════════════════════════════════════════
// ContentHubTopCard — 页头英雄卡片（动态指标）
// ═══════════════════════════════════════════════════════════════════

class ContentHubTopCard extends StatelessWidget {
  const ContentHubTopCard({
    super.key,
    required this.onRefresh,
    required this.entryCount,
    required this.sectionCount,
    required this.totalItems,
    required this.syncLabel,
  });

  final VoidCallback onRefresh;
  final int entryCount;
  final int sectionCount;
  final int totalItems;
  final String syncLabel;

  @override
  Widget build(BuildContext context) {
    // 内容页：压扁 Hero 为工具条，指标并入副标题，优先露出入口与收藏库
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7ECF5)),
        boxShadow: AppTokens.shadowSm(color: AppTokens.emerald),
      ),
      child: Row(
        children: [
          _ContentLightIconButton(
            icon: Icons.collections_bookmark_rounded,
            color: AppTokens.emerald,
            onTap: onRefresh,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '内容中心',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTokens.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$entryCount 入口 · $sectionCount 分区 · $totalItems 收藏 · $syncLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTokens.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRefresh,
            child: const AppStatusPill(
              label: '刷新',
              icon: Icons.refresh_rounded,
              color: AppTokens.emerald,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContentLightIconButton extends StatelessWidget {
  const _ContentLightIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.16)),
        ),
        child: Icon(icon, color: color, size: 21),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// ContentEntryGrid — 3×2 均衡入口网格
// ═══════════════════════════════════════════════════════════════════

class ContentEntryGrid extends StatelessWidget {
  const ContentEntryGrid({
    super.key,
    required this.onOpenVideoCenter,
    required this.onOpenNovelLibrary,
    required this.onOpenOpenLibrarySearch,
    required this.onOpenComics,
    required this.onOpenMusic,
    required this.onQuickImport,
  });

  final VoidCallback onOpenVideoCenter;
  final VoidCallback onOpenNovelLibrary;
  final VoidCallback onOpenOpenLibrarySearch;
  final VoidCallback onOpenComics;
  final VoidCallback onOpenMusic;
  final VoidCallback onQuickImport;

  @override
  Widget build(BuildContext context) {
    // 紧凑 3×2：缩短副标题、减小内边距，避免入口区占半屏
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE9EEF7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: '内容入口',
            subtitle: '影视 / 小说 / 漫画 / 音乐',
            icon: Icons.dashboard_customize_rounded,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppCompactActionCard(
                  title: '影视',
                  subtitle: '搜索播放',
                  icon: Icons.smart_display_rounded,
                  color: AppTokens.primaryBlue,
                  onTap: onOpenVideoCenter,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppCompactActionCard(
                  title: '小说搜索',
                  subtitle: 'OpenLib 搜索',
                  icon: Icons.auto_stories_rounded,
                  color: AppTokens.orange,
                  onTap: onOpenOpenLibrarySearch,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppCompactActionCard(
                  title: '书架',
                  subtitle: '本地阅读',
                  icon: Icons.menu_book_rounded,
                  color: AppTokens.amber,
                  onTap: onOpenNovelLibrary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppCompactActionCard(
                  title: '漫画',
                  subtitle: '导入收藏',
                  icon: Icons.collections_bookmark_rounded,
                  color: AppTokens.violet,
                  onTap: onOpenComics,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppCompactActionCard(
                  title: '音乐',
                  subtitle: '歌单历史',
                  icon: Icons.library_music_rounded,
                  color: AppTokens.emerald,
                  onTap: onOpenMusic,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppCompactActionCard(
                  title: '导入资源',
                  subtitle: '手动添加',
                  icon: Icons.add_link_rounded,
                  color: AppTokens.orange,
                  onTap: onQuickImport,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// ContentOnboardingBanner — 新用户引导条
// ═══════════════════════════════════════════════════════════════════

class ContentOnboardingBanner extends StatelessWidget {
  const ContentOnboardingBanner({
    super.key,
    required this.onDismiss,
    required this.onQuickImport,
    required this.onSearchBooks,
  });

  final VoidCallback onDismiss;
  final VoidCallback onQuickImport;
  final VoidCallback onSearchBooks;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE8F5E9), Color(0xFFF1F8E9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC8E6C9)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTokens.emerald.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.rocket_launch_rounded,
              color: AppTokens.emerald,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '首次使用？从这里开始',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2E7D32),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '从公开搜书找到想看的，或手动导入已有资源',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _GuideChip(
            label: '搜书',
            icon: Icons.search_rounded,
            onTap: onSearchBooks,
          ),
          const SizedBox(width: 6),
          _GuideChip(
            label: '导入',
            icon: Icons.add_rounded,
            onTap: onQuickImport,
          ),
          const SizedBox(width: 4),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onDismiss,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.close, size: 18, color: Colors.green.shade400),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideChip extends StatelessWidget {
  const _GuideChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppTokens.emerald.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppTokens.emerald),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTokens.emerald,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// ContentOverviewCard — 收藏操作区（带封面预览）
// ═══════════════════════════════════════════════════════════════════

class ContentOverviewCard extends StatelessWidget {
  const ContentOverviewCard({
    super.key,
    required this.totalItems,
    required this.recentItem,
    required this.isLoading,
    required this.onOpenItem,
  });

  final int totalItems;
  final WarehouseItem? recentItem;
  final bool isLoading;
  final ValueChanged<WarehouseItem>? onOpenItem;

  @override
  Widget build(BuildContext context) {
    // 无收藏且未加载时隐藏整个最近收藏区，节省空间
    if ((recentItem == null && !isLoading) || totalItems == 0)
      return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7ECF5)),
        boxShadow: AppTokens.shadowSm(color: AppTokens.primaryBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '最近收藏',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: AppTokens.textPrimary,
                        height: 1.15,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '继续上次 / 快速导入',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppTokens.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTokens.emerald.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                ),
                child: Text(
                  isLoading ? '加载中' : '$totalItems 项',
                  style: const TextStyle(
                    color: AppTokens.emerald,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _RecentCollectionTile(
            item: recentItem,
            isLoading: isLoading,
            onTap: recentItem != null && onOpenItem != null
                ? () => onOpenItem!(recentItem!)
                : () {},
          ),
        ],
      ),
    );
  }
}

class _RecentCollectionTile extends StatelessWidget {
  const _RecentCollectionTile({
    required this.item,
    required this.isLoading,
    required this.onTap,
  });

  final WarehouseItem? item;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final i = item;
    if (i == null) {
      return Container(
        height: 72,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F3FF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE8E0FF)),
        ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.inbox_rounded,
                size: 18,
                color: AppTokens.violet.withValues(alpha: 0.55),
              ),
              const SizedBox(width: 6),
              Text(
                '还没有收藏',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTokens.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        height: 72,
        padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F6FF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE8E0FF)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: i.coverUrl.trim().isNotEmpty
                  ? Image.network(
                      i.coverUrl,
                      width: 40,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          _buildCoverFallback(i.category),
                    )
                  : _buildCoverFallback(i.category),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    i.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTokens.textPrimary,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    i.subtitle.trim().isNotEmpty ? i.subtitle : i.sourceLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: i.category.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      i.category.hubLabel,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: i.category.color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverFallback(WarehouseCategory category) {
    return Container(
      width: 40,
      height: 56,
      color: category.color.withValues(alpha: 0.12),
      child: Icon(category.icon, size: 18, color: category.color),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// ContentSearchBar — 收藏库搜索筛选
// ═══════════════════════════════════════════════════════════════════

class ContentSearchBar extends StatelessWidget {
  const ContentSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
    this.resultCount = 0,
    this.isSearching = false,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final int resultCount;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE9EEF7)),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 20, color: Colors.grey.shade500),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: const InputDecoration(
                hintText: '搜索收藏项...',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintStyle: TextStyle(fontSize: 13),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (isSearching)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Colors.grey.shade400,
                ),
              ),
            ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: onClear,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTokens.emerald.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  resultCount > 0 ? '$resultCount 项' : '清除',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: resultCount > 0
                        ? AppTokens.emerald
                        : Colors.grey.shade600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// WarehouseSection — 可折叠收藏分区
// ═══════════════════════════════════════════════════════════════════

class WarehouseSection extends StatefulWidget {
  const WarehouseSection({
    super.key,
    required this.category,
    required this.items,
    required this.isLoading,
    required this.hasError,
    required this.emptyText,
    required this.onAdd,
    required this.onOpenItem,
    required this.onOpenVideoCenter,
    required this.onOpenNovelLibrary,
    this.editMode = false,
    this.selectedKeys = const {},
    this.onToggleSelect,
  });

  final WarehouseCategory category;
  final List<WarehouseItem> items;
  final bool isLoading;
  final bool hasError;
  final String emptyText;
  final ValueChanged<WarehouseCategory> onAdd;
  final ValueChanged<WarehouseItem> onOpenItem;
  final VoidCallback onOpenVideoCenter;
  final VoidCallback onOpenNovelLibrary;
  final bool editMode;
  final Set<String> selectedKeys;
  final ValueChanged<String>? onToggleSelect;

  @override
  State<WarehouseSection> createState() => _WarehouseSectionState();
}

class _WarehouseSectionState extends State<WarehouseSection>
    with SingleTickerProviderStateMixin {
  late bool _expanded;
  late AnimationController _animController;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    // 有内容的默认展开，空的分区默认收起
    _expanded = widget.items.isNotEmpty;
    _animController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _anim = CurvedAnimation(parent: _animController, curve: Curves.easeInOut);
    if (_expanded) _animController.value = 1.0;
  }

  @override
  void didUpdateWidget(WarehouseSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 数据从无到有时自动展开
    if (oldWidget.items.isEmpty && widget.items.isNotEmpty && !_expanded) {
      _setExpanded(true);
    }
  }

  void _setExpanded(bool value) {
    _expanded = value;
    if (value) {
      _animController.forward();
    } else {
      _animController.reverse();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 可点击头部
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _setExpanded(!_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      widget.category.icon,
                      size: 18,
                      color: widget.category.color,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.category.hubLabel,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!widget.isLoading)
                      Text(
                        '${widget.items.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    if (widget.items.isEmpty && !widget.isLoading)
                      Text(
                        ' · 暂无内容',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    const Spacer(),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: '新增',
                      onPressed: () => widget.onAdd(widget.category),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ),
            ),
            // 可折叠内容区
            SizeTransition(
              sizeFactor: _anim,
              axis: Axis.vertical,
              child: _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (widget.isLoading) {
      return const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (widget.hasError) {
      return const WarehouseErrorBox();
    }

    if (widget.items.isEmpty) {
      return AppEmptyState(
        title: '还没有${widget.category.hubLabel}',
        message: widget.emptyText,
        icon: widget.category.icon,
        actionLabel: widget.category == WarehouseCategory.videos
            ? '打开影视搜索'
            : widget.category == WarehouseCategory.books
            ? '打开小说书架'
            : '添加一个',
        onAction: widget.category == WarehouseCategory.videos
            ? widget.onOpenVideoCenter
            : widget.category == WarehouseCategory.books
            ? widget.onOpenNovelLibrary
            : () => widget.onAdd(widget.category),
      );
    }

    return SizedBox(
      height: 182,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: widget.items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = widget.items[index];
          final isSelected = widget.selectedKeys.contains(item.uniqueKey);
          return WarehouseCard(
            item: item,
            editMode: widget.editMode,
            isSelected: isSelected,
            onTap: widget.editMode && widget.onToggleSelect != null
                ? () => widget.onToggleSelect!(item.uniqueKey)
                : () => widget.onOpenItem(item),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// WarehouseCard — 收藏卡片（支持编辑模式）
// ═══════════════════════════════════════════════════════════════════

class WarehouseCard extends StatelessWidget {
  const WarehouseCard({
    super.key,
    required this.item,
    required this.onTap,
    this.editMode = false,
    this.isSelected = false,
  });

  final WarehouseItem item;
  final VoidCallback onTap;
  final bool editMode;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      onLongPress: editMode ? null : onTap,
      child: SizedBox(
        width: 118,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: item.coverUrl.trim().isEmpty
                        ? _buildFallback()
                        : Image.network(
                            item.coverUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _buildFallback(),
                          ),
                  ),
                  if (editMode)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTokens.emerald
                              : Colors.white.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? AppTokens.emerald
                                : Colors.grey.shade400,
                            width: 2,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(
                                Icons.check,
                                size: 14,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              item.subtitle.trim().isNotEmpty
                  ? item.subtitle
                  : item.sourceLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallback() {
    return Container(
      color: const Color(0xFFE9ECEF),
      child: Center(
        child: Icon(item.category.icon, size: 32, color: Colors.grey.shade500),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// WarehouseErrorBox
// ═══════════════════════════════════════════════════════════════════

class WarehouseErrorBox extends StatelessWidget {
  const WarehouseErrorBox({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4F4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade300),
            const SizedBox(height: 8),
            Text(
              '加载失败',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.red.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// BatchActionBar — 批量操作栏
// ═══════════════════════════════════════════════════════════════════

class BatchActionBar extends StatelessWidget {
  const BatchActionBar({
    super.key,
    required this.selectedCount,
    required this.onDelete,
    required this.onCancel,
  });

  final int selectedCount;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Text(
              '已选 $selectedCount 项',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            OutlinedButton(onPressed: onCancel, child: const Text('取消')),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: selectedCount > 0 ? onDelete : null,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text('删除 ($selectedCount)'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Legacy compatibility exports (classes moved to warehouse_tab)
// ═══════════════════════════════════════════════════════════════════

class ContentHeaderMetricPill extends StatelessWidget {
  const ContentHeaderMetricPill({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTokens.textPrimary,
                  fontSize: 18,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTokens.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class WarehouseSectionHeader extends StatelessWidget {
  const WarehouseSectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppTokens.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppTokens.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
