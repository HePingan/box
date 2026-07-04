import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_cards.dart';
import 'package:box/design_system/widgets/press_scale.dart';
import 'package:box/plugin_manager.dart';

// ═══════════════════════════════════════════════════════════════════
// ExtensionHeroCard — 动态指标 + 核心操作
// ═══════════════════════════════════════════════════════════════════

class ExtensionHeroCard extends StatelessWidget {
  const ExtensionHeroCard({
    super.key,
    required this.pluginCount,
    required this.enabledCount,
    required this.bookSourceCount,
    required this.videoSourceCount,
    required this.onOpenMarket,
    required this.onImportJson,
    required this.onExportJson,
  });

  final int pluginCount;
  final int enabledCount;
  final int bookSourceCount;
  final int videoSourceCount;
  final VoidCallback onOpenMarket;
  final VoidCallback onImportJson;
  final VoidCallback onExportJson;

  @override
  Widget build(BuildContext context) {
    return AppLightHeroCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      eyebrow: '',
      title: '扩展中心',
      subtitle:
          '${pluginCount} 个插件 · ${bookSourceCount + videoSourceCount} 个资源规则',
      badge: 'EXT HUB',
      accentGradient: AppTokens.violetGradient,
      leading: _ExtensionLightIcon(icon: Icons.admin_panel_settings_rounded),
      actions: [
        // 插件市场 — 主入口
        PressScale(
          child: GestureDetector(
          onTap: onOpenMarket,
          child: const AppStatusPill(
            label: '插件市场',
            icon: Icons.storefront_rounded,
            color: AppTokens.violet,
          ),
        ),
        ),
        // 管理菜单
        PopupMenuButton<String>(
          padding: EdgeInsets.zero,
          iconSize: 20,
          icon: const Icon(
            Icons.more_vert_rounded,
            color: AppTokens.textSecondary,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          onSelected: (action) {
            switch (action) {
              case 'import':
                onImportJson();
              case 'export':
                onExportJson();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'import',
              child: ListTile(
                leading: Icon(
                  Icons.download_for_offline_rounded,
                  color: AppTokens.emerald,
                ),
                title: Text('导入 JSON'),
                subtitle: Text('粘贴或 URL 拉取配置', style: TextStyle(fontSize: 11)),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ),
            PopupMenuItem(
              value: 'export',
              child: ListTile(
                leading: Icon(Icons.upload_file_rounded, color: AppTokens.cyan),
                title: Text('导出 JSON'),
                subtitle: Text('复制插件快照', style: TextStyle(fontSize: 11)),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ),
          ],
        ),
      ],
      metrics: [
        Expanded(
          child: _ExtensionLightMetric(value: '$pluginCount', label: '插件'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ExtensionLightMetric(value: '$bookSourceCount', label: '书源'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ExtensionLightMetric(
            value: '${enabledCount - bookSourceCount - videoSourceCount}',
            label: '其他',
          ),
        ),
      ],
    );
  }
}

class _ExtensionLightIcon extends StatelessWidget {
  const _ExtensionLightIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: AppTokens.violet.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTokens.violet.withValues(alpha: 0.16)),
      ),
      child: const Icon(
        Icons.admin_panel_settings_rounded,
        color: AppTokens.violet,
        size: 21,
      ),
    );
  }
}

class _ExtensionLightMetric extends StatelessWidget {
  const _ExtensionLightMetric({required this.value, required this.label});

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
                fontFeatures: [FontFeature.tabularFigures()],
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

// ═══════════════════════════════════════════════════════════════════
// ExtensionManagementTile — 管理操作卡片
// ═══════════════════════════════════════════════════════════════════

class ExtensionManagementTile extends StatelessWidget {
  const ExtensionManagementTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.primary = false,
    this.count,
    this.trailing,
    this.gradient,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool primary;
  final int? count;
  final Widget? trailing;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final foreground = primary ? Colors.white : AppTokens.textPrimary;
    final muted = primary
        ? Colors.white.withValues(alpha: 0.78)
        : AppTokens.textSecondary;
    final bgGradient =
        gradient ??
        (primary
            ? LinearGradient(
                colors: [color, color.withValues(alpha: 0.72)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null);

    final decoration = bgGradient != null
        ? BoxDecoration(
            gradient: bgGradient,
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppTokens.shadowSm(color: color),
          )
        : BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppTokens.shadowSm(color: color),
          );

    return PressScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(primary ? 22 : 20),
          onTap: onTap,
          child: Container(
          constraints: const BoxConstraints(minHeight: 98),
          padding: const EdgeInsets.all(14),
          decoration: decoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部：图标 + 计数 Badge
              Row(
                children: [
                  // 图标容器
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: primary
                          ? Colors.white.withValues(alpha: 0.20)
                          : color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                      border: primary
                          ? null
                          : Border.all(color: color.withValues(alpha: 0.12)),
                    ),
                    child: Icon(
                      icon,
                      color: primary ? Colors.white : color,
                      size: 22,
                    ),
                  ),
                  const Spacer(),
                  // 计数 Badge
                  if (count != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: primary
                            ? Colors.white.withValues(alpha: 0.20)
                            : color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(
                          AppTokens.radiusPill,
                        ),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          color: foreground,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  const SizedBox(width: 6),
                  // 右侧箭头
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: primary
                        ? Colors.white.withValues(alpha: 0.50)
                        : AppTokens.textTertiary,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 标题
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              // 副标题
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: muted,
                  fontSize: 11,
                  height: 1.3,
                  fontWeight: FontWeight.w500,
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

// ═══════════════════════════════════════════════════════════════════
// PluginStatusChip
// ═══════════════════════════════════════════════════════════════════

class PluginStatusChip extends StatelessWidget {
  const PluginStatusChip({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// PluginDetailSheet — 插件详情弹出层
// ═══════════════════════════════════════════════════════════════════

class PluginDetailSheet extends StatelessWidget {
  const PluginDetailSheet({super.key, required this.plugin});

  final HomePlugin plugin;

  @override
  Widget build(BuildContext context) {
    final payload = plugin.customConfig?.payload ?? '';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: plugin.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(plugin.icon, color: plugin.color, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plugin.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        plugin.subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _detailRow('状态', plugin.enabled ? '已启用' : '已禁用'),
            _detailRow('区域', plugin.area.label),
            _detailRow('类型', plugin.builtIn ? '内置插件' : '自定义插件'),
            _detailRow('ID', plugin.id),
            _detailRow('描述', plugin.subtitle),
            if (payload.isNotEmpty) _detailRow('动作参数', payload),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTokens.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
