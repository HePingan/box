import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_cards.dart';
import 'package:box/features/content/domain/warehouse_models.dart';

class ContentHubTopCard extends StatelessWidget {
  const ContentHubTopCard({super.key, required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return AppLightHeroCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      eyebrow: '内容聚合中心',
      title: '内容中心',
      subtitle: '小说、影视、漫画、音乐统一收纳',
      badge: 'CONTENT',
      accentGradient: AppTokens.emeraldGradient,
      leading: _ContentLightIconButton(
        icon: Icons.collections_bookmark_rounded,
        color: AppTokens.emerald,
        onTap: onRefresh,
      ),
      actions: [
        GestureDetector(
          onTap: onRefresh,
          child: const AppStatusPill(
            label: '刷新',
            icon: Icons.refresh_rounded,
            color: AppTokens.emerald,
          ),
        ),
        const AppStatusPill(
          label: '收藏库',
          icon: Icons.folder_special_rounded,
          color: AppTokens.primaryBlue,
        ),
      ],
      metrics: const [
        Expanded(
          child: _ContentLightMetric(value: '4', label: '内容入口'),
        ),
        SizedBox(width: 8),
        Expanded(
          child: _ContentLightMetric(value: '4', label: '收藏分区'),
        ),
        SizedBox(width: 8),
        Expanded(
          child: _ContentLightMetric(value: '书架', label: '自动同步'),
        ),
      ],
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

class _ContentLightMetric extends StatelessWidget {
  const _ContentLightMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FD),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        border: Border.all(color: const Color(0xFFE7ECF5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTokens.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppTokens.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

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

class ContentEntryGrid extends StatelessWidget {
  const ContentEntryGrid({
    super.key,
    required this.onOpenVideoCenter,
    required this.onOpenNovelLibrary,
    required this.onOpenOpenLibrarySearch,
    required this.onHubComingSoon,
  });

  final VoidCallback onOpenVideoCenter;
  final VoidCallback onOpenNovelLibrary;
  final VoidCallback onOpenOpenLibrarySearch;
  final ValueChanged<String> onHubComingSoon;

  @override
  Widget build(BuildContext context) {
    final entries = [
      AppCompactActionCard(
        title: '影视',
        subtitle: '搜索/播放',
        icon: Icons.smart_display_rounded,
        color: AppTokens.primaryBlue,
        onTap: onOpenVideoCenter,
      ),
      AppCompactActionCard(
        title: '公开搜书',
        subtitle: 'Open Library',
        icon: Icons.auto_stories_rounded,
        color: AppTokens.orange,
        onTap: onOpenOpenLibrarySearch,
      ),
      AppCompactActionCard(
        title: '漫画',
        subtitle: '收藏/导入',
        icon: Icons.collections_bookmark_rounded,
        color: AppTokens.violet,
        onTap: () => onHubComingSoon('漫画收藏'),
      ),
      AppCompactActionCard(
        title: '音乐',
        subtitle: '歌单/历史',
        icon: Icons.library_music_rounded,
        color: AppTokens.emerald,
        onTap: () => onHubComingSoon('音乐收藏'),
      ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE9EEF7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: '内容入口',
            subtitle: '影视、书架与公开搜书优先，漫画音乐轻量收纳',
            icon: Icons.dashboard_customize_rounded,
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(child: entries[0]),
              const SizedBox(width: 9),
              Expanded(child: entries[1]),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: AppCompactActionCard(
                  title: '小说书架',
                  subtitle: '本地阅读',
                  icon: Icons.menu_book_rounded,
                  color: AppTokens.amber,
                  onTap: onOpenNovelLibrary,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(child: entries[2]),
            ],
          ),
          const SizedBox(height: 9),
          Row(children: [Expanded(child: entries[3])]),
        ],
      ),
    );
  }
}

class ContentOverviewCard extends StatelessWidget {
  const ContentOverviewCard({
    super.key,
    required this.future,
    required this.onOpenItem,
    required this.onShowCategoryPicker,
  });

  final Future<List<List<WarehouseItem>>> future;
  final ValueChanged<WarehouseItem> onOpenItem;
  final VoidCallback onShowCategoryPicker;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<List<WarehouseItem>>>(
      future: future,
      builder: (context, snapshot) {
        final groups = snapshot.data ?? const <List<WarehouseItem>>[];
        final total = groups.fold<int>(0, (sum, items) => sum + items.length);
        final recent = groups.expand((items) => items).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final recentTitle = recent.isEmpty
            ? '暂无收藏，先导入一个资源'
            : recent.first.title;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Colors.white, Color(0xFFF8FBFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
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
                          '收藏操作区',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: AppTokens.textPrimary,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          '最近收藏 / 快速导入 / 分类管理集中处理',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTokens.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTokens.emerald.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                    ),
                    child: Text(
                      snapshot.connectionState == ConnectionState.done
                          ? '$total 项'
                          : '加载中',
                      style: const TextStyle(
                        color: AppTokens.emerald,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: AppCompactActionCard(
                      title: '最近收藏',
                      subtitle: recentTitle,
                      icon: Icons.history_rounded,
                      color: AppTokens.violet,
                      onTap: recent.isEmpty
                          ? null
                          : () => onOpenItem(recent.first),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppCompactActionCard(
                      title: '快速导入',
                      subtitle: '选择分类添加资源',
                      icon: Icons.add_link_rounded,
                      color: AppTokens.orange,
                      onTap: onShowCategoryPicker,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class WarehouseSection extends StatelessWidget {
  const WarehouseSection({
    super.key,
    required this.category,
    required this.future,
    required this.emptyText,
    required this.onAdd,
    required this.onOpenItem,
    required this.onOpenVideoCenter,
    required this.onOpenNovelLibrary,
  });

  final WarehouseCategory category;
  final Future<List<WarehouseItem>> future;
  final String emptyText;
  final ValueChanged<WarehouseCategory> onAdd;
  final ValueChanged<WarehouseItem> onOpenItem;
  final VoidCallback onOpenVideoCenter;
  final VoidCallback onOpenNovelLibrary;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<WarehouseItem>>(
      future: future,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState != ConnectionState.done;
        final items = snapshot.data ?? const <WarehouseItem>[];

        return Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(category.icon, size: 18, color: category.color),
                    const SizedBox(width: 8),
                    Text(
                      category.hubLabel,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!loading)
                      Text(
                        '${items.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    const Spacer(),
                    IconButton(
                      tooltip: '新增',
                      onPressed: () => onAdd(category),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (loading)
                  const SizedBox(
                    height: 160,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snapshot.hasError)
                  const WarehouseErrorBox()
                else if (items.isEmpty)
                  AppEmptyState(
                    title: '还没有${category.hubLabel}',
                    message: emptyText,
                    icon: category.icon,
                    actionLabel: category == WarehouseCategory.videos
                        ? '打开影视搜索'
                        : category == WarehouseCategory.books
                        ? '打开小说书架'
                        : '添加一个',
                    onAction: category == WarehouseCategory.videos
                        ? onOpenVideoCenter
                        : category == WarehouseCategory.books
                        ? onOpenNovelLibrary
                        : () => onAdd(category),
                  )
                else
                  SizedBox(
                    height: 182,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return WarehouseCard(
                          item: item,
                          onTap: () => onOpenItem(item),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

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

class WarehouseCard extends StatelessWidget {
  const WarehouseCard({super.key, required this.item, required this.onTap});

  final WarehouseItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: SizedBox(
        width: 118,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: item.coverUrl.trim().isEmpty
                    ? _buildFallback()
                    : Image.network(
                        item.coverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _buildFallback(),
                      ),
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
