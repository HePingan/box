import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_cards.dart';
import 'package:box/features/content/domain/warehouse_models.dart';

class ContentHubTopCard extends StatelessWidget {
  const ContentHubTopCard({super.key, required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFFE4EAF3)),
        boxShadow: AppTokens.shadowMd(color: AppTokens.primaryBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: AppTokens.emeraldGradient,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: AppTokens.emerald.withValues(alpha: 0.22),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.collections_bookmark_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '内容指挥台',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTokens.textPrimary,
                        fontSize: 25,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.6,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'CONTENT HUB · 首屏压缩',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTokens.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 42,
                height: 42,
                child: IconButton.filledTonal(
                  tooltip: '刷新',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded, size: 21),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFEDEBFF),
                    foregroundColor: AppTokens.textPrimary,
                    shape: const CircleBorder(),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppTokens.emerald.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppTokens.emerald.withValues(alpha: 0.16),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.bolt_rounded, size: 18, color: AppTokens.emerald),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '内容入口 / 收藏库 / 四页导航统一',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTokens.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              Expanded(
                child: ContentHeaderMetricPill(
                  value: '4',
                  label: '内容入口',
                  icon: Icons.apps_rounded,
                  color: AppTokens.emerald,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: ContentHeaderMetricPill(
                  value: '4',
                  label: '收藏库',
                  icon: Icons.folder_special_rounded,
                  color: AppTokens.primaryBlue,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: ContentHeaderMetricPill(
                  value: '书架',
                  label: '自动同步',
                  icon: Icons.sync_rounded,
                  color: AppTokens.orange,
                ),
              ),
            ],
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
    required this.onHubComingSoon,
  });

  final VoidCallback onOpenVideoCenter;
  final VoidCallback onOpenNovelLibrary;
  final ValueChanged<String> onHubComingSoon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(
          title: '内容入口 · 优先操作区',
          subtitle: '影视搜索和小说书架放在首屏第一优先级',
          icon: Icons.dashboard_customize_rounded,
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              child: AppGradientActionCard(
                title: '影视搜索',
                subtitle: '聚合片源 · 播放历史',
                icon: Icons.smart_display_rounded,
                gradient: AppTokens.darkOceanGradient,
                onTap: onOpenVideoCenter,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppGradientActionCard(
                title: '小说书架',
                subtitle: '书源阅读 · 书架收藏',
                icon: Icons.auto_stories_rounded,
                gradient: AppTokens.sunsetGradient,
                onTap: onOpenNovelLibrary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: AppGradientActionCard(
                title: '漫画收藏',
                subtitle: '收藏夹 · 手动导入',
                icon: Icons.collections_bookmark_rounded,
                gradient: AppTokens.violetGradient,
                onTap: () => onHubComingSoon('漫画收藏'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppGradientActionCard(
                title: '音乐收藏',
                subtitle: '歌单 · 历史 · 链接',
                icon: Icons.library_music_rounded,
                gradient: AppTokens.emeraldGradient,
                onTap: () => onHubComingSoon('音乐收藏'),
              ),
            ),
          ],
        ),
      ],
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
                      borderRadius: BorderRadius.circular(999),
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
                    child: AppGradientActionCard(
                      title: '最近收藏',
                      subtitle: recentTitle,
                      icon: Icons.history_rounded,
                      gradient: AppTokens.violetGradient,
                      onTap: recent.isEmpty
                          ? null
                          : () => onOpenItem(recent.first),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppGradientActionCard(
                      title: '快速导入',
                      subtitle: '选择分类添加资源',
                      icon: Icons.add_link_rounded,
                      gradient: AppTokens.sunsetGradient,
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
