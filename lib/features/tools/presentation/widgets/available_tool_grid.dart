import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/features/api_hub/presentation/api_hub_page.dart';
import 'package:box/features/local_tools/presentation/local_tools_registry.dart';
import 'package:box/features/tools/application/tool_catalog.dart';
import 'package:box/features/tools/application/tool_usage_store.dart';
import 'package:box/features/tools/presentation/source_fetch_page.dart';
import 'package:box/tool_web_page.dart';

/// 打开一个 [ToolEntry] 的去向。
///
/// 派发只认 [ToolTarget]，没有兜底分支 —— 未接线条目压根不会进网格，
/// 真出现 null 就弹提示，不静默打开别的页。
///
/// 顺带记一次使用（[ToolUsageStore]）：这里是**唯一派发点**，所以「常用」那一行
/// 的数据只可能从这一处产生，不会出现某个入口漏记、或两处各记一套的情况。
/// 先写盘再跳转 —— 跳转返回后页面读到的必须是已经落地的计数。
Future<void> openToolTarget(
  BuildContext context,
  String toolName,
  ToolTarget? target,
) async {
  await ToolUsageStore.instance.record(toolName);
  if (!context.mounted) return;
  switch (target) {
    case ApiHubToolTarget(:final toolId):
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ApiHubPage(initialTool: toolId)),
      );
    case WebToolTarget(:final title, :final url):
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ToolWebPage(title: title, url: url),
        ),
      );
    case SourceFetchToolTarget():
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SourceFetchPage()),
      );
    case LocalToolTarget(:final localId):
      // 纯本地工具：不走 ApiHubPage。那条路会先拉一次公共 API 索引，
      // 计算器没必要为此等一个网络请求。
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => LocalToolPage(localId: localId)),
      );
    case null:
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('【$toolName】还没做，先别点了'),
          duration: const Duration(milliseconds: 1100),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
  }
}

/// 工具图标：**唯一来源**。网格卡片、区标题、常用行都从这里取。
///
/// 原来这个 switch 是网格的私有方法（`_iconFor`），其它地方要用只能再抄一份
/// —— 抄出来的那份迟早和这份不一致（页面图标与网格图标打架）。
IconData toolIconFor(ToolTarget? target) => switch (target) {
  WebToolTarget() => Icons.public_rounded,
  SourceFetchToolTarget() => Icons.code_rounded,
  // 本地工具的图标从 kLocalTools 取，图标定义只有一处（registry）。
  LocalToolTarget(:final localId) =>
    kLocalTools[localId]?.icon ?? Icons.calculate_rounded,
  ApiHubToolTarget(:final toolId) => switch (toolId) {
    'weather' => Icons.wb_sunny_rounded,
    'currency' || 'exchange_rate' => Icons.currency_exchange_rounded,
    'holidays' => Icons.event_available_rounded,
    'dictionary' || 'daily_english' => Icons.menu_book_rounded,
    'books' => Icons.auto_stories_rounded,
    'mock' => Icons.badge_rounded,
    'qr' => Icons.qr_code_2_rounded,
    'avatar' => Icons.account_circle_rounded,
    'cover' => Icons.wallpaper_rounded,
    'shortlink' => Icons.link_rounded,
    'ip' || 'ip_query' => Icons.router_rounded,
    'dummy_image' => Icons.image_rounded,
    'directory' => Icons.travel_explore_rounded,
    _ => Icons.api_rounded,
  },
  null => Icons.help_outline_rounded,
};

/// 一个工具在网格里的紧凑卡：图标 + 名字。
///
/// 不再在卡片底部写分类 —— 分类现在是**区标题**。66 张卡各写一遍
/// 「开发工具」是同一份信息重复 13 遍，还占掉卡片三分之一高度。
class AvailableToolCard extends StatelessWidget {
  const AvailableToolCard({super.key, required this.entry});

  final ToolEntry entry;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => openToolTarget(context, entry.name, entry.target),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
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
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFF059669).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                toolIconFor(entry.target),
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
          ],
        ),
      ),
    );
  }
}
