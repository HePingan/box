import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_cards.dart';
import 'package:box/plugin_manager.dart';

class ExtensionHeroCard extends StatelessWidget {
  const ExtensionHeroCard({
    super.key,
    required this.pluginCount,
    required this.onOpenMarket,
    required this.onImportJson,
  });

  final int pluginCount;
  final VoidCallback onOpenMarket;
  final VoidCallback onImportJson;

  @override
  Widget build(BuildContext context) {
    return AppLightHeroCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      eyebrow: '扩展管理中心',
      title: '扩展中心',
      subtitle: '插件、资源规则、备份与诊断统一管理',
      badge: 'EXT HUB',
      accentGradient: AppTokens.violetGradient,
      leading: const _ExtensionLightIcon(
        icon: Icons.admin_panel_settings_rounded,
      ),
      actions: [
        GestureDetector(
          onTap: onOpenMarket,
          child: const AppStatusPill(
            label: '插件市场',
            icon: Icons.storefront_rounded,
            color: AppTokens.violet,
          ),
        ),
        GestureDetector(
          onTap: onImportJson,
          child: const AppStatusPill(
            label: '导入',
            icon: Icons.download_for_offline_rounded,
            color: AppTokens.emerald,
          ),
        ),
      ],
      metrics: [
        Expanded(
          child: _ExtensionLightMetric(value: '$pluginCount', label: '插件'),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: _ExtensionLightMetric(value: '书源', label: '小说规则'),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: _ExtensionLightMetric(value: '片源', label: '影视规则'),
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
        borderRadius: BorderRadius.circular(16),
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

class ExtensionPluginSection extends StatelessWidget {
  const ExtensionPluginSection({
    super.key,
    required this.area,
    required this.plugins,
    required this.onRunPlugin,
    required this.onToggleEnabled,
    required this.onUninstall,
  });

  final HomePluginArea area;
  final List<HomePlugin> plugins;
  final Future<void> Function(BuildContext context, HomePlugin plugin)
  onRunPlugin;
  final Future<void> Function(HomePlugin plugin, bool enabled) onToggleEnabled;
  final Future<void> Function(HomePlugin plugin) onUninstall;

  @override
  Widget build(BuildContext context) {
    final areaColor = _colorForArea(area);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTokens.divider),
        boxShadow: AppTokens.shadowSm(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: areaColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(area.icon, size: 18, color: areaColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _areaHubTitle(area),
                      style: const TextStyle(
                        color: AppTokens.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _areaHubSubtitle(area),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTokens.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              PluginStatusChip(text: '${plugins.length} 个', color: areaColor),
            ],
          ),
          const SizedBox(height: 10),
          if (plugins.isEmpty)
            const AppEmptyState(
              title: '暂无插件',
              message: '可从插件市场安装，或新增自定义插件。',
              icon: Icons.extension_off_rounded,
              height: 118,
            )
          else
            Column(
              children: plugins
                  .map(
                    (plugin) => _PluginListTile(
                      plugin: plugin,
                      onRunPlugin: onRunPlugin,
                      onToggleEnabled: onToggleEnabled,
                      onUninstall: onUninstall,
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Color _colorForArea(HomePluginArea area) {
    switch (area) {
      case HomePluginArea.recommend:
        return Colors.deepPurple;
      case HomePluginArea.music:
        return Colors.pink;
      case HomePluginArea.video:
        return Colors.indigo;
      case HomePluginArea.comic:
        return Colors.teal;
      case HomePluginArea.novel:
        return Colors.orange;
      case HomePluginArea.center:
        return Colors.blueGrey;
    }
  }

  String _areaHubTitle(HomePluginArea area) {
    switch (area) {
      case HomePluginArea.recommend:
        return '首页推荐扩展';
      case HomePluginArea.music:
        return '音乐能力扩展';
      case HomePluginArea.video:
        return '影视能力扩展';
      case HomePluginArea.comic:
        return '漫画能力扩展';
      case HomePluginArea.novel:
        return '小说能力扩展';
      case HomePluginArea.center:
        return '中心控制扩展';
    }
  }

  String _areaHubSubtitle(HomePluginArea area) {
    switch (area) {
      case HomePluginArea.recommend:
        return '展示在首页推荐区的快捷能力';
      case HomePluginArea.music:
        return '音乐搜索、歌单和音频相关扩展';
      case HomePluginArea.video:
        return '影视搜索、片源和播放链路扩展';
      case HomePluginArea.comic:
        return '漫画收藏、搜索和榜单扩展';
      case HomePluginArea.novel:
        return '小说书架、书源和阅读扩展';
      case HomePluginArea.center:
        return '配置、诊断和系统级扩展';
    }
  }
}

class _PluginListTile extends StatelessWidget {
  const _PluginListTile({
    required this.plugin,
    required this.onRunPlugin,
    required this.onToggleEnabled,
    required this.onUninstall,
  });

  final HomePlugin plugin;
  final Future<void> Function(BuildContext context, HomePlugin plugin)
  onRunPlugin;
  final Future<void> Function(HomePlugin plugin, bool enabled) onToggleEnabled;
  final Future<void> Function(HomePlugin plugin) onUninstall;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: plugin.enabled
            ? plugin.color.withValues(alpha: 0.04)
            : AppTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: plugin.enabled
              ? plugin.color.withValues(alpha: 0.18)
              : AppTokens.divider,
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => onRunPlugin(context, plugin),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: plugin.color.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(plugin.icon, color: plugin.color, size: 19),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onRunPlugin(context, plugin),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          plugin.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTokens.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      PluginStatusChip(
                        text: plugin.enabled ? '已启用' : '未启用',
                        color: plugin.enabled
                            ? AppTokens.emerald
                            : AppTokens.textTertiary,
                      ),
                      if (plugin.builtIn) ...[
                        const SizedBox(width: 4),
                        const PluginStatusChip(
                          text: '内置',
                          color: AppTokens.primaryBlue,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    plugin.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTokens.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Switch.adaptive(
            value: plugin.enabled,
            onChanged: (value) => onToggleEnabled(plugin, value),
          ),
          if (!plugin.builtIn)
            IconButton(
              tooltip: '卸载插件',
              onPressed: () => onUninstall(plugin),
              icon: const Icon(Icons.delete_outline_rounded),
              color: AppTokens.rose,
            ),
        ],
      ),
    );
  }
}

class ExtensionManagementTile extends StatelessWidget {
  const ExtensionManagementTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.primary = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final foreground = primary ? Colors.white : AppTokens.textPrimary;
    final muted = primary
        ? Colors.white.withValues(alpha: 0.78)
        : AppTokens.textSecondary;
    final decoration = primary
        ? BoxDecoration(
            gradient: LinearGradient(
              colors: [color, color.withValues(alpha: 0.72)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppTokens.shadowSm(color: color),
          )
        : BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTokens.divider),
            boxShadow: AppTokens.shadowSm(color: color),
          );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(primary ? 22 : 20),
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: primary ? 92 : 104),
          padding: const EdgeInsets.all(14),
          decoration: decoration,
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: primary
                      ? Colors.white.withValues(alpha: 0.18)
                      : color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: primary ? Colors.white : color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: muted,
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: primary ? Colors.white : AppTokens.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
