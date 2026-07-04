import 'package:flutter/material.dart';

import '../../../design_system/app_tokens.dart';
import '../../core/novel_cache_manager.dart';

/// 小说列表页统计信息条
///
/// 显示书源数量、书籍数量、缓存大小等关键指标。
class NovelStatsBar extends StatefulWidget {
  const NovelStatsBar({
    super.key,
    required this.sourceCount,
    required this.bookCount,
    required this.cacheManager,
    this.onCacheTapped,
  });

  final int sourceCount;
  final int bookCount;
  final NovelCacheManager cacheManager;
  final VoidCallback? onCacheTapped;

  @override
  State<NovelStatsBar> createState() => _NovelStatsBarState();
}

class _NovelStatsBarState extends State<NovelStatsBar> {
  NovelCacheStats? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await widget.cacheManager.getStats();
      if (mounted) {
        setState(() {
          _stats = stats;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _stats == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTokens.divider),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(
            icon: Icons.library_books_rounded,
            value: '${widget.sourceCount}',
            label: '书源',
            color: AppTokens.violet,
          ),
          _StatItem(
            icon: Icons.menu_book_rounded,
            value: '${widget.bookCount}',
            label: '书籍',
            color: AppTokens.primaryBlue,
          ),
          if (widget.onCacheTapped != null)
            _StatItem(
              icon: Icons.storage_rounded,
              value: _stats!.formattedSize,
              label: '缓存',
              color: AppTokens.emerald,
              onTap: widget.onCacheTapped,
            ),
          if (widget.onCacheTapped == null)
            _StatItem(
              icon: Icons.storage_rounded,
              value: _stats!.formattedSize,
              label: '缓存',
              color: AppTokens.emerald,
            ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: AppTokens.textTertiary,
          ),
        ),
      ],
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: child,
      );
    }
    return child;
  }
}
