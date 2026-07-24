part of 'plugin_tab.dart';

class _PluginStatusSection extends StatefulWidget {
  const _PluginStatusSection({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.plugins,
    required this.onRunPlugin,
    required this.onToggleEnabled,
    required this.onUninstall,
    required this.totalCount,
    required this.pinnedPluginIds,
    required this.onPinToggle,
    this.selectMode = false,
    this.selectedPluginIds = const {},
    this.onSelectToggle,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final List<HomePlugin> plugins;
  final Future<void> Function(BuildContext context, HomePlugin plugin)
  onRunPlugin;
  final Future<void> Function(HomePlugin plugin, bool enabled) onToggleEnabled;
  final Future<void> Function(HomePlugin plugin) onUninstall;
  final int totalCount;
  final Set<String> pinnedPluginIds;
  final void Function(String pluginId) onPinToggle;
  final bool selectMode;
  final Set<String> selectedPluginIds;
  final void Function(String pluginId)? onSelectToggle;

  @override
  State<_PluginStatusSection> createState() => _PluginStatusSectionState();
}

class _PluginStatusSectionState extends State<_PluginStatusSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(widget.icon, size: 20, color: widget.iconColor),
                const SizedBox(width: 8),
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: AppTokens.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: widget.iconColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                  ),
                  child: Text(
                    '${widget.plugins.length}/${widget.totalCount}',
                    style: TextStyle(
                      color: widget.iconColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _expanded ? 0 : -0.25,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.expand_more_rounded,
                    color: AppTokens.textSecondary,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: Column(
            children: List.generate(widget.plugins.length, (i) {
              final plugin = widget.plugins[i];
              return _StaggeredItem(
                index: i,
                child: PluginCard(
                  plugin: plugin,
                  isPinned: widget.pinnedPluginIds.contains(plugin.id),
                  onPinToggle: widget.onPinToggle,
                  selectMode: widget.selectMode,
                  isSelected: widget.selectedPluginIds.contains(plugin.id),
                  onSelectToggle: widget.onSelectToggle,
                  onRunPlugin: widget.onRunPlugin,
                  onToggleEnabled: widget.onToggleEnabled,
                  onUninstall: widget.onUninstall,
                ),
              );
            }),
          ),
          secondChild: const SizedBox.shrink(),
          crossFadeState: _expanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// _StaggeredItem — 入场错开动画
// ═══════════════════════════════════════════════════════════════════

/// 入场错开动画 — 淡入 + 上滑
class _StaggeredItem extends StatefulWidget {
  const _StaggeredItem({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_StaggeredItem> createState() => _StaggeredItemState();
}

class _StaggeredItemState extends State<_StaggeredItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _opacity = _ctrl;
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    Future.delayed(Duration(milliseconds: widget.index * 50), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// _BatchActionButton — 批量操作小按钮
// ═══════════════════════════════════════════════════════════════════

class _BatchActionButton extends StatelessWidget {
  const _BatchActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
