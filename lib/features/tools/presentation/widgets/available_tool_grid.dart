import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/features/api_hub/presentation/api_hub_page.dart';
import 'package:box/features/local_tools/presentation/local_tools_registry.dart';
import 'package:box/features/tools/application/tool_catalog.dart';
import 'package:box/tool_web_page.dart';

/// 打开一个 [ToolEntry] 的去向。
///
/// 派发只认 [ToolTarget]，没有兜底分支 —— 未接线条目压根不会进这个网格，
/// 真出现 null 就弹提示，不静默打开别的页。
void openToolTarget(BuildContext context, String toolName, ToolTarget? target) {
  switch (target) {
    case ApiHubToolTarget(:final toolId):
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ApiHubPage(initialTool: toolId)),
      );
    case WebToolTarget(:final title, :final url):
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ToolWebPage(title: title, url: url)),
      );
    case LocalToolTarget(:final localId):
      // 纯本地工具：不走 ApiHubPage。那条路会先拉一次公共 API 索引，
      // 计算器没必要为此等一个网络请求。
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => LocalToolPage(localId: localId)),
      );
    case null:
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('【$toolName】还没做，先别点了'),
          duration: const Duration(milliseconds: 1100),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
  }
}

/// 可用能力平铺网格。
///
/// 结构上的取舍：112 个目录条目里只有 [availableToolEntries] 这十几个真能用，
/// 旧版把两者混在同一批折叠分类里，用户要点开 10 张卡、在一堆「开发中」徽标里
/// 逐个找。这里把能用的直接平铺到首屏 —— 不用展开、不用搜索、不看徽标。
///
/// 每张卡片带分类归属（[ToolEntry.category]），平铺之后不丢「它属于哪一类」。
class AvailableToolGrid extends StatelessWidget {
  const AvailableToolGrid({super.key, required this.entries});

  final List<ToolEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  size: 14,
                  color: Color(0xFF047857),
                ),
              ),
              const SizedBox(width: 7),
              const Text(
                '现在可用',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                  color: AppTokens.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${entries.length} 个',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            // 目标卡宽 ~104，按可用宽度自适应列数，窄屏至少 3 列。
            final columns = (constraints.maxWidth / 104).floor().clamp(3, 6);
            return GridView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.92,
              ),
              itemCount: entries.length,
              itemBuilder: (context, index) =>
                  _AvailableToolCard(entry: entries[index]),
            );
          },
        ),
      ],
    );
  }
}

class _AvailableToolCard extends StatelessWidget {
  const _AvailableToolCard({required this.entry});

  final ToolEntry entry;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => openToolTarget(context, entry.name, entry.target),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE7ECF5)),
          boxShadow: AppTokens.shadowSm(color: AppTokens.violet),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF059669).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _iconFor(entry.target),
                size: 17,
                color: const Color(0xFF047857),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              entry.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.15,
                fontWeight: FontWeight.w800,
                color: AppTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              entry.category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: AppTokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(ToolTarget? target) => switch (target) {
    WebToolTarget() => Icons.public_rounded,
    // 本地工具的图标不在这里再抄一份 —— 从 kLocalTools 取，图标定义
    // 只有一处（registry），加新工具不会出现网格图标和页面图标不一致。
    LocalToolTarget(:final localId) =>
      kLocalTools[localId]?.icon ?? Icons.calculate_rounded,
    ApiHubToolTarget(:final toolId) => switch (toolId) {
      'weather' => Icons.wb_sunny_rounded,
      'currency' => Icons.currency_exchange_rounded,
      'holidays' => Icons.event_available_rounded,
      'dictionary' => Icons.menu_book_rounded,
      'books' => Icons.auto_stories_rounded,
      'mock' => Icons.badge_rounded,
      'qr' => Icons.qr_code_2_rounded,
      'avatar' => Icons.account_circle_rounded,
      'cover' => Icons.wallpaper_rounded,
      'shortlink' => Icons.link_rounded,
      'ip' => Icons.router_rounded,
      'dummy_image' => Icons.image_rounded,
      'directory' => Icons.travel_explore_rounded,
      _ => Icons.api_rounded,
    },
    null => Icons.help_outline_rounded,
  };
}
