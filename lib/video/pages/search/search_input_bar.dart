import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';

/// 源内搜索 / 聚合搜索共用的搜索输入条。
///
/// 两页此前各写一份样式（圆角、描边、阴影、清空按钮、提交按钮），
/// 极易走样。统一到这里：主色、提示语、按钮文案/图标按页传入，
/// 其余视觉一致，改一处两页生效。
class SearchInputBar extends StatelessWidget {
  const SearchInputBar({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onSubmit,
    required this.onClear,
    this.accentColor = AppTokens.primaryBlue,
    this.leadingIcon = Icons.search_rounded,
    this.actionIcon = Icons.manage_search_rounded,
    this.actionLabel = '搜索',
    this.autofocus = true,
    this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 10),
  });

  final TextEditingController controller;
  final String hintText;
  final VoidCallback onSubmit;
  final VoidCallback onClear;
  final Color accentColor;
  final IconData leadingIcon;
  final IconData actionIcon;
  final String actionLabel;
  final bool autofocus;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7ECF5)),
        boxShadow: AppTokens.shadowSm(color: accentColor),
      ),
      child: Row(
        children: [
          Icon(leadingIcon, color: accentColor),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              decoration: InputDecoration(
                hintText: hintText,
                border: InputBorder.none,
                isDense: true,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onSubmit(),
            ),
          ),
          IconButton(
            tooltip: '清空',
            icon: const Icon(Icons.close_rounded),
            onPressed: onClear,
          ),
          FilledButton.icon(
            onPressed: onSubmit,
            icon: Icon(actionIcon, size: 18),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}
