import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/features/tools/application/tool_catalog.dart';

import 'tool_widgets.dart';

/// 「计划中」折叠区：只装还没接线的占位条目。
///
/// 展开状态由父级持有（[expanded] / [onToggle]），不放在卡片 State 里 ——
/// 搜索会 `new ToolCategory(...)` 重建列表，卡片自己记的展开态会被冲掉。
class PlannedToolsSection extends StatelessWidget {
  const PlannedToolsSection({
    super.key,
    required this.categories,
    required this.expanded,
    required this.onToggle,
  });

  final List<ToolCategory> categories;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox.shrink();

    final total = categories.fold<int>(0, (s, c) => s + c.tools.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: onToggle,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE7ECF5)),
              boxShadow: [
                BoxShadow(
                  color: AppTokens.ink.withValues(alpha: 0.035),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF64748B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.more_horiz_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '计划中',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF333333),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '还没做，点开看看规划',
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF64748B).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                    border: Border.all(
                      color: const Color(0xFF64748B).withValues(alpha: 0.18),
                    ),
                  ),
                  child: Text(
                    '$total 个',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 22,
                  color: const Color(0xFF6B7FA2),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          ...categories.map(
            (category) => ExpandableCategoryCard(
              // 搜索会重建列表，没有 key 时 Flutter 按位置复用 State，
              // 「系统操作」的展开态会落到「趣味游戏」上。
              key: ValueKey(category.title),
              category: category,
            ),
          ),
      ],
    );
  }
}
