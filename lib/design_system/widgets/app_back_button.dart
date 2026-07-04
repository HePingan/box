import 'package:flutter/material.dart';

import '../app_tokens.dart';

/// 统一的返回按钮组件 — 用于各页面的 AppBar / HeroCard leading。
///
/// 视觉特征：
/// - filledTonal 风格的圆角容器
/// - 蓝青渐变选中态指示条（左侧竖线）
/// - 与全局 design token 保持一致
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.onPressed, this.label});

  final VoidCallback? onPressed;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppTokens.surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          border: Border.all(color: AppTokens.divider),
          boxShadow: [
            BoxShadow(
              color: AppTokens.ink.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 左侧渐变指示条
            Container(
              width: 3,
              height: 16,
              decoration: BoxDecoration(
                gradient: AppTokens.blueGradient,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.keyboard_arrow_left_rounded,
              size: 20,
              color: AppTokens.textPrimary,
            ),
            if (label != null) ...[
              const SizedBox(width: 6),
              Text(
                label!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.textPrimary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 轻量版返回按钮 — 用于 SliverAppBar leading，无背景容器。
class AppBackButtonLight extends StatelessWidget {
  const AppBackButtonLight({super.key, this.onPressed, this.label});

  final VoidCallback? onPressed;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.keyboard_arrow_left_rounded,
              size: 22,
              color: theme.colorScheme.primary,
            ),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(
                label!,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
