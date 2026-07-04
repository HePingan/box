import 'package:flutter/material.dart';
import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/press_scale.dart';
import 'package:box/plugin_manager.dart';

/// 统一插件卡片 — 取代 PluginListTile
///
/// 设计要点：
/// - 状态圆点（左）一键区分启用/禁用
/// - 图标 + 标题 + 副标题
/// - 标签行（区域色块 + 内置/自定义标记）
/// - 尾部操作：启用开关 + 卸载按钮 + 固定按钮
/// - 选择模式：勾选框替代固定按钮
/// - 编辑模式下显示拖拽手柄
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
        padding: const EdgeInsets.fromLTRB(8, 10, 4, 10),
        decoration: BoxDecoration(
        color: isSelected
            ? AppTokens.violet.withValues(alpha: 0.06)
            : enabled
                ? plugin.color.withValues(alpha: 0.04)
                : AppTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(17),
        boxShadow: AppTokens.shadowSm(),
      ),
      child: Row(
        children: [
          // 拖拽手柄（编辑模式）
          if (editMode)
            ReorderableDragStartListener(
              index: dragIndex ?? 0,
              child: const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.drag_handle_rounded,
                    color: AppTokens.textTertiary, size: 22),
              ),
            ),

          // 选择框（选择模式）
          if (selectMode)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: isSelected,
                  onChanged: (_) => onSelectToggle?.call(plugin.id),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),

          // 状态圆点（非选择模式）
          if (!selectMode)
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: enabled ? AppTokens.emerald : AppTokens.textTertiary,
              ),
            ),

          // 图标
          GestureDetector(
            onTap: selectMode
                ? () => onSelectToggle?.call(plugin.id)
                : () => onRunPlugin(context, plugin),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: plugin.color.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(plugin.icon, color: plugin.color, size: 20),
            ),
          ),
          const SizedBox(width: 10),

          // 标题 + 副标题 + 标签行
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: selectMode
                  ? () => onSelectToggle?.call(plugin.id)
                  : () => onRunPlugin(context, plugin),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题行
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
                      if (isPinned)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(Icons.push_pin_rounded,
                              size: 14, color: AppTokens.primaryBlue),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  // 副标题
                  Text(
                    plugin.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTokens.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 5),
                  // 标签行：区域 + 内置标记 + 启用状态
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _Tag(
                        text: plugin.area.label,
                        color: baseColor,
                      ),
                      if (plugin.builtIn)
                        const _Tag(
                          text: '内置',
                          color: AppTokens.primaryBlue,
                        ),
                      _Tag(
                        text: enabled ? '已启用' : '未启用',
                        color: enabled
                            ? AppTokens.emerald
                            : AppTokens.textTertiary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 2),

          // 尾部操作
          if (!selectMode && !editMode) ...[
            // 固定按钮
            if (onPinToggle != null)
              IconButton(
                tooltip: isPinned ? '取消固定' : '固定到顶部',
                onPressed: () => onPinToggle!(plugin.id),
                icon: Icon(
                  isPinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  size: 18,
                ),
                color:
                    isPinned ? AppTokens.primaryBlue : AppTokens.textTertiary,
                visualDensity: VisualDensity.compact,
              ),
            Switch.adaptive(
              value: enabled,
              onChanged: (value) => onToggleEnabled(plugin, value),
            ),
            if (!plugin.builtIn)
              IconButton(
                tooltip: '卸载插件',
                onPressed: () => onUninstall(plugin),
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                color: AppTokens.rose,
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
