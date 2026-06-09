import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';

class MarketPill extends StatelessWidget {
  const MarketPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected ? AppTokens.blueGradient : null,
          color: selected ? null : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? Colors.transparent : AppTokens.divider,
          ),
          boxShadow: selected
              ? AppTokens.shadowSm(color: AppTokens.primaryBlue)
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppTokens.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class MarketStatusBadge extends StatelessWidget {
  const MarketStatusBadge({super.key, required this.installed});

  final bool installed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: installed
            ? AppTokens.emerald.withValues(alpha: 0.12)
            : AppTokens.primaryBlue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        installed ? '已安装' : '可安装',
        style: TextStyle(
          color: installed ? AppTokens.emerald : AppTokens.primaryBlue,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class MarketEmptyState extends StatelessWidget {
  const MarketEmptyState({
    super.key,
    required this.loading,
    required this.onReset,
  });

  final bool loading;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppTokens.divider),
        boxShadow: AppTokens.shadowSm(),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            loading ? Icons.hourglass_empty_rounded : Icons.search_off_rounded,
            color: AppTokens.primaryBlue,
            size: 38,
          ),
          const SizedBox(height: 12),
          Text(
            loading ? '正在加载插件市场...' : '没有匹配插件',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: AppTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '换个关键词，或重置筛选查看全部模板',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTokens.textSecondary, fontSize: 12),
          ),
          if (!loading) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重置筛选'),
            ),
          ],
        ],
      ),
    );
  }
}

class MarketTagChip extends StatelessWidget {
  const MarketTagChip({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: Colors.grey[700]),
      ),
    );
  }
}

class MarketMetric extends StatelessWidget {
  const MarketMetric({
    super.key,
    required this.value,
    required this.label,
    this.glass = true,
  });

  final String value;
  final String label;
  final bool glass;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: glass
            ? Colors.white.withValues(alpha: 0.14)
            : AppTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: glass
              ? Colors.white.withValues(alpha: 0.18)
              : AppTokens.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: glass ? Colors.white : AppTokens.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: glass
                  ? Colors.white.withValues(alpha: 0.76)
                  : AppTokens.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
