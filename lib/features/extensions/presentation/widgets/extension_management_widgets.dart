import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/press_scale.dart';
import 'package:box/plugin_manager.dart';

// ═══════════════════════════════════════════════════════════════════
// ExtensionHeroCard — 方案 B：紧凑工具条（单行指标 + 主 CTA）
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
    this.onSubmitPlugin,
  });

  final int pluginCount;
  final int enabledCount;
  final int bookSourceCount;
  final int videoSourceCount;
  final VoidCallback onOpenMarket;
  final VoidCallback onImportJson;
  final VoidCallback onExportJson;
  final VoidCallback? onSubmitPlugin;

  @override
  Widget build(BuildContext context) {
    final otherPlugins =
        (pluginCount - bookSourceCount - videoSourceCount).clamp(0, 1 << 30);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        // 与工具/内容 hero 对齐：半透明白，让页面渐变透上来，
        // 原为不透明白会切断 pageGradient，视觉上比另两页「浮」得更高。
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: AppTokens.cardBorder),
        boxShadow: AppTokens.shadowSm(color: AppTokens.violet),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行：图标 + 标题/启用态 + 市场 + 更多
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTokens.violet.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppTokens.violet.withValues(alpha: 0.16),
                  ),
                ),
                child: const Icon(
                  Icons.extension_rounded,
                  color: AppTokens.violet,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '扩展中心',
                      style: TextStyle(
                        color: AppTokens.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '已启用 $enabledCount / 共 $pluginCount',
                      style: const TextStyle(
                        color: AppTokens.textSecondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              PressScale(
                child: Material(
                  color: AppTokens.violet,
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                  child: InkWell(
                    onTap: onOpenMarket,
                    borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.storefront_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                          SizedBox(width: 4),
                          Text(
                            '市场',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                iconSize: 18,
                tooltip: '更多操作',
                icon: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F8FD),
                    borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                    border: Border.all(color: const Color(0xFFE7ECF5)),
                  ),
                  child: const Icon(
                    Icons.more_horiz_rounded,
                    color: AppTokens.textSecondary,
                    size: 16,
                  ),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onSelected: (action) {
                  switch (action) {
                    case 'submit':
                      onSubmitPlugin?.call();
                    case 'import':
                      onImportJson();
                    case 'export':
                      onExportJson();
                  }
                },
                itemBuilder: (_) => [
                  if (onSubmitPlugin != null)
                    const PopupMenuItem(
                      value: 'submit',
                      child: ListTile(
                        leading: Icon(
                          Icons.upload_rounded,
                          color: AppTokens.violet,
                        ),
                        title: Text('投稿插件'),
                        subtitle: Text(
                          '提交审核后上架商店',
                          style: TextStyle(fontSize: 11),
                        ),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'import',
                    child: ListTile(
                      leading: Icon(
                        Icons.download_for_offline_rounded,
                        color: AppTokens.emerald,
                      ),
                      title: Text('导入 JSON'),
                      subtitle: Text(
                        '粘贴或 URL 拉取配置',
                        style: TextStyle(fontSize: 11),
                      ),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'export',
                    child: ListTile(
                      leading: Icon(
                        Icons.upload_file_rounded,
                        color: AppTokens.cyan,
                      ),
                      title: Text('导出 JSON'),
                      subtitle: Text(
                        '复制插件快照',
                        style: TextStyle(fontSize: 11),
                      ),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 单行指标 chips
          Row(
            children: [
              Expanded(
                child: _CompactMetricChip(
                  value: '$bookSourceCount',
                  label: '书源',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _CompactMetricChip(
                  value: '$videoSourceCount',
                  label: '片源',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _CompactMetricChip(
                  value: '$otherPlugins',
                  label: '其它',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactMetricChip extends StatelessWidget {
  const _CompactMetricChip({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// ExtensionQuickChip — 方案 B：横向紧凑快捷入口
// ═══════════════════════════════════════════════════════════════════

class ExtensionQuickChip extends StatelessWidget {
  const ExtensionQuickChip({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
    this.count,
  });

  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE7ECF5)),
              boxShadow: AppTokens.shadowSm(color: color),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTokens.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      if (count != null && count! > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          '$count',
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ],
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
                  // 计数 Badge：0 不展示，避免空状态像「未读告警」
                  if (count != null && count! > 0) ...[
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
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
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
// PluginDetailSheet — 插件详情弹出层（内容页优化）
// ═══════════════════════════════════════════════════════════════════

class PluginDetailSheet extends StatelessWidget {
  const PluginDetailSheet({super.key, required this.plugin});

  final HomePlugin plugin;

  @override
  Widget build(BuildContext context) {
    final payload = plugin.customConfig?.payload ?? '';
    final enabled = plugin.enabled;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.72,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD5DCE8),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // 标题区：题干优先，状态 chip 不挤标题
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: plugin.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: plugin.color.withValues(alpha: 0.16),
                        ),
                      ),
                      child: Icon(plugin.icon, color: plugin.color, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plugin.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: AppTokens.textPrimary,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            plugin.subtitle,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppTokens.textSecondary,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              PluginStatusChip(
                                text: enabled ? '已启用' : '已禁用',
                                color: enabled
                                    ? AppTokens.emerald
                                    : AppTokens.textTertiary,
                              ),
                              PluginStatusChip(
                                text: plugin.area.label,
                                color: plugin.color,
                              ),
                              PluginStatusChip(
                                text: plugin.builtIn ? '内置' : '自定义',
                                color: plugin.builtIn
                                    ? AppTokens.primaryBlue
                                    : AppTokens.violet,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F8FD),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE7ECF5)),
                  ),
                  child: Column(
                    children: [
                      _detailRow('ID', plugin.id),
                      if (payload.isNotEmpty) ...[
                        const Divider(height: 16, color: Color(0xFFE7ECF5)),
                        _detailRow('动作参数', payload),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppTokens.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppTokens.textPrimary,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}
