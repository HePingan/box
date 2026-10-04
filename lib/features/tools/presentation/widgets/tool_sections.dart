import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/features/tools/application/tool_catalog.dart';

import 'available_tool_grid.dart';

/// 区里的网格列数。目标卡宽 ~82：360dp 的屏能排 4 列（原来 3 列 / 卡宽 104，
/// 66 个工具要滚 22 行 ≈ 4~5 屏）。
int toolGridColumns(double maxWidth) => (maxWidth / 82).floor().clamp(3, 6);

/// 一个分类的区：区标题（图标 + 名字 + 计数）+ 网格。
///
/// 折叠态（[expanded] == false）只露**第一行**，多出来的条目收进一张
/// 「还有 N 个」格子 —— 这样 10 个分类的标题都能在首屏附近扫到，
/// 而不是被某一个分类的 13 个工具顶到屏幕外。
class ToolCategorySection extends StatelessWidget {
  const ToolCategorySection({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.entries,
    required this.expanded,
    required this.onToggle,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<ToolEntry> entries;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(icon, size: 14, color: color),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      color: AppTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${entries.length} 个',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppTokens.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: const Color(0xFF6B7FA2),
                  ),
                ],
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = toolGridColumns(constraints.maxWidth);
              final singleRow = !expanded;
              final visible = singleRow
                  ? entries.take(columns).toList()
                  : entries;
              // 折叠时多出来的那一坨，用一张「还有 N 个」的格子收口 ——
              // 不靠用户猜「这个区是不是被截断了」。
              final hiddenCount = entries.length - visible.length;
              final showMoreTile = hiddenCount > 0;
              final showCollapseTile = expanded && entries.length > columns;

              return GridView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.95,
                ),
                itemCount:
                    visible.length + (showMoreTile || showCollapseTile ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index < visible.length) {
                    return AvailableToolCard(entry: visible[index]);
                  }
                  return _MoreTile(
                    label: showMoreTile ? '还有 $hiddenCount 个' : '收起',
                    expand: showMoreTile,
                    onTap: onToggle,
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.label,
    required this.expand,
    required this.onTap,
  });

  final String label;
  final bool expand;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF4F6FB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F4)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              expand ? Icons.unfold_more_rounded : Icons.unfold_less_rounded,
              size: 18,
              color: const Color(0xFF6B7FA2),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                height: 1.15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF5B6B8C),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 分类芯片条：全部 + 每个分类（带计数）+ 一个「离线可用」开关。
///
/// 芯片只筛**看到哪些区**，不改变区的内部结构 —— 点「开发工具」看到的就是
/// 那个区本身，不是一份被拍平的临时列表。这样「我知道它在哪一类」的人
/// 一次点击就能到，不经过滚动。
class ToolCategoryChips extends StatelessWidget {
  const ToolCategoryChips({
    super.key,
    required this.categories,
    required this.selected,
    required this.totalCount,
    required this.offlineOnly,
    required this.onSelect,
    required this.onToggleOffline,
  });

  /// (分类名, 该分类当前可用的条数)。计数为 0 的分类由调用方过滤掉。
  final List<({String title, int count})> categories;
  final String? selected;
  final int totalCount;
  final bool offlineOnly;
  final ValueChanged<String?> onSelect;
  final VoidCallback onToggleOffline;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          _Chip(
            label: '全部 $totalCount',
            selected: selected == null,
            onTap: () => onSelect(null),
          ),
          // 全局开关紧跟「全部」，不放在横滑列表的末尾 —— 末尾意味着要划一下才够得着，
          // 而它和「看哪一类」不是同一维度的事。
          const SizedBox(width: 6),
          _Chip(
            label: '离线可用',
            icon: Icons.wifi_off_rounded,
            selected: offlineOnly,
            onTap: onToggleOffline,
          ),
          for (final category in categories) ...[
            const SizedBox(width: 6),
            _Chip(
              label: '${category.title} ${category.count}',
              selected: selected == category.title,
              onTap: () => onSelect(category.title),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppTokens.violet : Colors.white,
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          border: Border.all(
            color: selected ? AppTokens.violet : const Color(0xFFE2E8F4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: selected ? Colors.white : const Color(0xFF5B6B8C),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : const Color(0xFF5B6B8C),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部「常用」一行：按使用次数排出来的那几个工具。
///
/// [defaults] 只在**一条记录都没有**时用它 —— 那时标题必须写清是推荐
/// （「试试这些」），不能拿默认集冒充「你常用的」。用过一次之后这一行
/// 就只显示真实记录，不再掺推荐。
class RecentToolsRow extends StatelessWidget {
  const RecentToolsRow({
    super.key,
    required this.entries,
    required this.usingDefaults,
  });

  final List<ToolEntry> entries;
  final bool usingDefaults;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 7),
          child: Row(
            children: [
              Icon(
                usingDefaults
                    ? Icons.lightbulb_outline_rounded
                    : Icons.history_rounded,
                size: 15,
                color: AppTokens.violet,
              ),
              const SizedBox(width: 5),
              Text(
                usingDefaults ? '试试这些' : '常用',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: AppTokens.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                usingDefaults ? '用过的工具会记在这里' : '按使用次数排',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in entries)
              ActionChip(
                avatar: Icon(
                  toolIconFor(entry.target),
                  size: 16,
                  color: AppTokens.violet,
                ),
                label: Text(entry.name),
                onPressed: () =>
                    openToolTarget(context, entry.name, entry.target),
                side: BorderSide(
                  color: AppTokens.violet.withValues(alpha: 0.28),
                ),
                backgroundColor: AppTokens.violet.withValues(alpha: 0.07),
                labelStyle: const TextStyle(
                  color: AppTokens.violet,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

/// 「想要什么工具？」——撤掉「计划中」之后给用户的**真实**出口。
///
/// 原来那 56 条未接线条目假装是"规划"，点进去只会弹「还没做」；现在这条
/// 把人送去关于页的反馈渠道（GitHub Issues）。真话短一点，但它是能兑现的。
class ToolRequestRow extends StatelessWidget {
  const ToolRequestRow({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(16)),
          border: Border.fromBorderSide(BorderSide(color: Color(0xFFE7ECF5))),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.tips_and_updates_outlined,
              size: 18,
              color: Color(0xFF6B7FA2),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '想要什么工具？',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '在「关于 → 反馈与联系」里说 —— 这里只列已经能用的',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: Color(0xFF6B7FA2),
            ),
          ],
        ),
      ),
    );
  }
}
