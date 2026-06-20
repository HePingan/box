import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/features/api_hub/presentation/api_hub_page.dart';
import 'package:box/features/tools/application/tool_catalog.dart';
import 'package:box/tool_web_page.dart';

class ToolGlassButton extends StatelessWidget {
  const ToolGlassButton({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFFF2F6FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0E8F6)),
        ),
        child: Icon(icon, color: AppTokens.primaryBlue, size: 22),
      ),
    );
  }
}

class ToolMetric extends StatelessWidget {
  const ToolMetric({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FD),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        border: Border.all(color: const Color(0xFFE7ECF5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: AppTokens.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTokens.textSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ToolHighlightCard extends StatelessWidget {
  const ToolHighlightCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = gradient.first;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        width: 168,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE7ECF5)),
          boxShadow: AppTokens.shadowSm(color: color),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTokens.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTokens.textSecondary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ToolStatusBadge extends StatelessWidget {
  const ToolStatusBadge({super.key, required this.label, required this.color});

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

  bool _isAvailableTool(String toolName) =>
      ['在线PS', '汇率换算', '节假日查询', 'API能力中心'].contains(toolName);

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
    return Container(
      margin: const EdgeInsets.only(bottom: 14.0),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xFFF8FBFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26.0),
        border: Border.all(color: const Color(0xFFE7ECF5)),
        boxShadow: [
          BoxShadow(
            color: AppTokens.ink.withValues(alpha: 0.045),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(26.0),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: widget.category.iconBgColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.category.icon,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.category.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF333333),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.category.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            ToolStatusBadge(
                              label: '${widget.category.tools.length} 个工具',
                              color: widget.category.iconBgColor,
                            ),
                            if (widget.category.tools.any(_isAvailableTool))
                              const ToolStatusBadge(
                                label: '含可用工具',
                                color: Color(0xFF059669),
                              )
                            else
                              const ToolStatusBadge(
                                label: '开发中',
                                color: Color(0xFF64748B),
                              ),
                          ],
                        ),
                        if (!_isExpanded && previewTools.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          Text(
                            previewTools.join(' / '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTokens.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _isExpanded
                      ? const Icon(
                          Icons.arrow_drop_up,
                          size: 30,
                          color: Color(0xFF132D6B),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6B7FA2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${widget.category.tools.length}个功能',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _isExpanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 12.0,
                        runSpacing: 12.0,
                        children: widget.category.tools.map((toolName) {
                          final available = _isAvailableTool(toolName);
                          return GestureDetector(
                            onTap: () => _handleToolTap(toolName),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14.0,
                                vertical: 10.0,
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
                                          .withValues(alpha: 0.20),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    toolName,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: available
                                          ? const Color(0xFF059669)
                                          : widget.category.iconBgColor,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    available ? '可用 · 外部网页' : '开发中',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
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
