import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/features/api_hub/presentation/api_hub_page.dart';
import 'package:box/features/tools/application/tool_catalog.dart';
import 'package:box/tool_web_page.dart';

/// 分类展开卡片（核心 UI 组件）
class ExpandableCategoryCard extends StatefulWidget {
  final ToolCategory category;
  const ExpandableCategoryCard({super.key, required this.category});

  @override
  State<ExpandableCategoryCard> createState() => _ExpandableCategoryCardState();
}

class _ExpandableCategoryCardState extends State<ExpandableCategoryCard> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.category.isExpanded;
  }

  @override
  void didUpdateWidget(covariant ExpandableCategoryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.category.isExpanded != oldWidget.category.isExpanded) {
      _isExpanded = widget.category.isExpanded;
    }
  }

  // 可用名单集中在 tool_catalog.dart，避免 UI 与目录各存一份导致漂移。
  bool _isAvailableTool(String toolName) => isToolAvailable(toolName);

  void _handleToolTap(String toolName) {
    if (_isAvailableTool(toolName)) {
      if (toolName == '汇率换算') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ApiHubPage(initialTool: 'currency'),
          ),
        );
        return;
      }
      if (toolName == '节假日查询') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ApiHubPage(initialTool: 'holidays'),
          ),
        );
        return;
      }
      if (toolName == 'API能力中心') {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ApiHubPage()),
        );
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ToolWebPage(
            title: '在线PS',
            url: 'https://www.photopea.com/',
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('【$toolName】开发中，稍后开放'),
        duration: const Duration(milliseconds: 1100),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final previewTools = widget.category.tools.take(3).toList();
    final availableCount = widget.category.tools.where(_isAvailableTool).length;
    final hasAvailable = availableCount > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18.0),
        border: Border.all(color: const Color(0xFFE7ECF5)),
        boxShadow: [
          BoxShadow(
            color: AppTokens.ink.withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 10.0,
              ),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(18.0),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: widget.category.iconBgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      widget.category.icon,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.category.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF333333),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isExpanded
                              ? widget.category.subtitle
                              : (previewTools.isNotEmpty
                                    ? previewTools.join(' / ')
                                    : widget.category.subtitle),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppTokens.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  _ToolStatusBadge(
                    label: hasAvailable
                        ? '$availableCount/${widget.category.tools.length}·可用'
                        : '${widget.category.tools.length}·开发中',
                    color: hasAvailable
                        ? const Color(0xFF059669)
                        : const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 22,
                    color: const Color(0xFF6B7FA2),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeInOut,
            child: _isExpanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8.0,
                        runSpacing: 8.0,
                        children: widget.category.tools.map((toolName) {
                          final available = _isAvailableTool(toolName);
                          return GestureDetector(
                            onTap: () => _handleToolTap(toolName),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11.0,
                                vertical: 8.0,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    (available
                                            ? const Color(0xFF059669)
                                            : widget.category.iconBgColor)
                                        .withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(
                                  AppTokens.radiusPill,
                                ),
                                border: Border.all(
                                  color:
                                      (available
                                              ? const Color(0xFF059669)
                                              : widget.category.iconBgColor)
                                          .withValues(alpha: 0.18),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    toolName,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: available
                                          ? const Color(0xFF059669)
                                          : widget.category.iconBgColor,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    available ? '可用' : '开发中',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: available
                                          ? const Color(0xFF047857)
                                          : AppTokens.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// 状态标签（仅 ExpandableCategoryCard 内部使用）
class _ToolStatusBadge extends StatelessWidget {
  const _ToolStatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
