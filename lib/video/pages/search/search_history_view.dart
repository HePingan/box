import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';

import 'search_empty_state.dart';

/// 源内搜索 / 聚合搜索共用的「历史 + 热词」视图。
///
/// 此前只有聚合页有历史，源内搜索空状态只有一句提示。抽成共享组件后，
/// 两页体验拉齐：有历史/热词就展示可点击 chip，没有就回退到空状态提示。
class SearchHistoryView extends StatelessWidget {
  const SearchHistoryView({
    super.key,
    required this.recentKeywords,
    required this.hotKeywords,
    required this.onTapKeyword,
    required this.onRemoveRecent,
    required this.onClearRecent,
    required this.emptyMessage,
    this.emptyIcon = Icons.travel_explore_rounded,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 32),
  });

  final List<String> recentKeywords;
  final List<String> hotKeywords;
  final ValueChanged<String> onTapKeyword;
  final ValueChanged<String> onRemoveRecent;
  final VoidCallback onClearRecent;
  final String emptyMessage;
  final IconData emptyIcon;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final hasRecent = recentKeywords.isNotEmpty;
    final hasHot = hotKeywords.isNotEmpty;

    if (!hasRecent && !hasHot) {
      return SearchEmptyState(message: emptyMessage, icon: emptyIcon);
    }

    return ListView(
      padding: padding,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (hasHot) ...[
          _header(
            title: '热门搜索',
            icon: Icons.local_fire_department_rounded,
            color: AppTokens.orange,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < hotKeywords.length; i++)
                _KeywordChip(
                  label: hotKeywords[i],
                  leading: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: i < 3 ? AppTokens.orange : AppTokens.textSecondary,
                    ),
                  ),
                  onTap: () => onTapKeyword(hotKeywords[i]),
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        if (hasRecent) ...[
          Row(
            children: [
              Expanded(
                child: _header(
                  title: '最近搜索',
                  icon: Icons.history_rounded,
                  color: AppTokens.primaryBlue,
                ),
              ),
              TextButton.icon(
                onPressed: onClearRecent,
                icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                label: const Text('清空'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTokens.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final keyword in recentKeywords)
                _KeywordChip(
                  label: keyword,
                  onTap: () => onTapKeyword(keyword),
                  onDeleted: () => onRemoveRecent(keyword),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _header({
    required String title,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppTokens.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _KeywordChip extends StatelessWidget {
  const _KeywordChip({
    required this.label,
    required this.onTap,
    this.leading,
    this.onDeleted,
  });

  final String label;
  final VoidCallback onTap;
  final Widget? leading;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: EdgeInsets.fromLTRB(12, 8, onDeleted != null ? 6 : 12, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE7ECF5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 6)],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.textPrimary,
                ),
              ),
            ),
            if (onDeleted != null) ...[
              const SizedBox(width: 2),
              GestureDetector(
                onTap: onDeleted,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.close_rounded,
                    size: 15,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
