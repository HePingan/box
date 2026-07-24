import 'package:flutter/material.dart';
import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/press_scale.dart';
import 'package:box/plugin_manager.dart';

/// 统一插件卡片 — 取代 PluginListTile
///
/// 布局原则（内容页优化）：
/// - 题干优先：标题/副标题在左上，窄屏不被 trailing 控件挤裁
/// - 操作下沉：固定 / 开关 / 卸载放第二行，避免横排挤压
/// - 去冗余：状态圆点已表达启用，不再重复「已启用」标签
/// - 选择/编辑模式仍保持紧凑单行
class PluginCard extends StatelessWidget {
  const PluginCard({
    super.key,
    required this.plugin,
    required this.onRunPlugin,
    required this.onToggleEnabled,
    required this.onUninstall,
    this.editMode = false,
    this.dragIndex,
    this.isPinned = false,
    this.onPinToggle,
    this.selectMode = false,
    this.isSelected = false,
    this.onSelectToggle,
  });

  final HomePlugin plugin;
  final Future<void> Function(BuildContext context, HomePlugin plugin)
  onRunPlugin;
  final Future<void> Function(HomePlugin plugin, bool enabled) onToggleEnabled;
  final Future<void> Function(HomePlugin plugin) onUninstall;
  final bool editMode;
  final int? dragIndex;
  final bool isPinned;
  final void Function(String pluginId)? onPinToggle;
  final bool selectMode;
  final bool isSelected;
  final void Function(String pluginId)? onSelectToggle;

  @override
  Widget build(BuildContext context) {
    final bool enabled = plugin.enabled;
    final Color baseColor = enabled ? plugin.color : AppTokens.textTertiary;

    return PressScale(
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTokens.violet.withValues(alpha: 0.06)
              : enabled
              ? plugin.color.withValues(alpha: 0.04)
              : AppTokens.surfaceMuted,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppTokens.violet.withValues(alpha: 0.22)
                : const Color(0xFFE7ECF5),
          ),
          boxShadow: AppTokens.shadowSm(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (editMode)
                  ReorderableDragStartListener(
                    index: dragIndex ?? 0,
                    child: const Padding(
                      padding: EdgeInsets.only(right: 6, top: 8),
                      child: Icon(
                        Icons.drag_handle_rounded,
                        color: AppTokens.textTertiary,
                        size: 20,
                      ),
                    ),
                  ),
                if (selectMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 6),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: Checkbox(
                        value: isSelected,
                        onChanged: (_) => onSelectToggle?.call(plugin.id),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                if (!selectMode)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 8, top: 14),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: enabled
                          ? AppTokens.emerald
                          : AppTokens.textTertiary,
                    ),
                  ),
                GestureDetector(
                  onTap: selectMode
                      ? () => onSelectToggle?.call(plugin.id)
                      : () => onRunPlugin(context, plugin),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: plugin.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: plugin.color.withValues(alpha: 0.14),
                      ),
                    ),
                    child: Icon(plugin.icon, color: plugin.color, size: 20),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: selectMode
                        ? () => onSelectToggle?.call(plugin.id)
                        : () => onRunPlugin(context, plugin),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plugin.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTokens.textPrimary,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          plugin.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTokens.textSecondary,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 4,
                          runSpacing: 3,
                          children: [
                            _Tag(text: plugin.area.label, color: baseColor),
                            if (plugin.builtIn)
                              const _Tag(
                                text: '内置',
                                color: AppTokens.primaryBlue,
                              ),
                            if (isPinned)
                              const _Tag(
                                text: '置顶',
                                color: AppTokens.primaryBlue,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // 操作行下沉：窄屏不与题干争宽
            if (!selectMode && !editMode) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    enabled ? '已启用' : '已禁用',
                    style: TextStyle(
                      color: enabled
                          ? AppTokens.emerald
                          : AppTokens.textTertiary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (onPinToggle != null)
                    IconButton(
                      tooltip: isPinned ? '取消固定' : '固定到顶部',
                      onPressed: () => onPinToggle!(plugin.id),
                      icon: Icon(
                        isPinned
                            ? Icons.push_pin_rounded
                            : Icons.push_pin_outlined,
                        size: 17,
                      ),
                      color: isPinned
                          ? AppTokens.primaryBlue
                          : AppTokens.textTertiary,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 34,
                        minHeight: 34,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  Transform.scale(
                    scale: 0.86,
                    child: Switch.adaptive(
                      value: enabled,
                      onChanged: (value) => onToggleEnabled(plugin, value),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  if (!plugin.builtIn)
                    IconButton(
                      tooltip: '卸载插件',
                      onPressed: () => onUninstall(plugin),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      color: AppTokens.rose,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 34,
                        minHeight: 34,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 卡片内小标签
class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      ),
    );
  }
}
