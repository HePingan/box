import 'package:flutter/material.dart';

import '../app_tokens.dart';

class AppHeroCard extends StatelessWidget {
  const AppHeroCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.badge,
    this.gradient = AppTokens.darkOceanGradient,
    this.metrics = const [],
    this.actions = const [],
    this.padding = const EdgeInsets.all(18),
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String? badge;
  final Gradient gradient;
  final List<Widget> metrics;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(AppTokens.radiusXl),
        boxShadow: AppTokens.heroShadow(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _GlassIcon(icon: icon),
              const Spacer(),
              if (badge != null) _GlassBadge(text: badge!),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (metrics.isNotEmpty) ...[
            const SizedBox(height: 18),
            Row(children: metrics),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(spacing: 10, runSpacing: 10, children: actions),
          ],
        ],
      ),
    );
  }
}

class AppMetricTile extends StatelessWidget {
  const AppMetricTile({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.accentColor,
    this.glass = false,
  });

  final String value;
  final String label;
  final IconData? icon;
  final Color? accentColor;
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? Theme.of(context).colorScheme.primary;
    final foreground = glass ? Colors.white : AppTokens.textPrimary;
    final muted = glass
        ? Colors.white.withValues(alpha: 0.74)
        : AppTokens.textSecondary;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: glass ? Colors.white.withValues(alpha: 0.14) : Colors.white,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(
          color: glass
              ? Colors.white.withValues(alpha: 0.18)
              : AppTokens.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: glass ? Colors.white : color),
            const SizedBox(height: 6),
          ],
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: foreground,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            ),
            child: Icon(
              icon,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppTokens.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class AppGradientActionCard extends StatelessWidget {
  const AppGradientActionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    this.onTap,
    this.width,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Gradient gradient;
  final VoidCallback? onTap;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        boxShadow: AppTokens.shadowMd(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        onTap: onTap,
        child: card,
      ),
    );
  }
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
    this.actionLabel,
    this.onAction,
    this.height = 168,
  });

  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double height;

  @override
  Widget build(BuildContext context) {
    // 用 minHeight 而不是固定 height：说明文字在窄屏折行后，
    // 图标 + 标题 + 文案 + 按钮的自然高度会超过 168，固定高度会把按钮裁掉。
    // 短文案时仍由 minHeight 撑到原来的视觉高度，不会变矮。
    return Container(
      constraints: BoxConstraints(minHeight: height),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: AppTokens.divider),
      ),
      child: Column(
        // 配合上面的 minHeight：没有它 Column 会按 mainAxisSize.max 撑满父级可用高度
        // （固定 height 时不会暴露，改成 minHeight 后会把卡片拉到满屏）。
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            ),
            child: Icon(icon, color: AppTokens.textTertiary),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: AppTokens.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTokens.textSecondary,
              fontSize: 12,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: onAction,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _GlassIcon extends StatelessWidget {
  const _GlassIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Icon(icon, color: Colors.white),
    );
  }
}

class _GlassBadge extends StatelessWidget {
  const _GlassBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

class AppLightHeroCard extends StatelessWidget {
  const AppLightHeroCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.eyebrow,
    this.badge,
    this.leading,
    this.metrics = const [],
    this.actions = const [],
    this.accentGradient = AppTokens.blueGradient,
    this.margin = EdgeInsets.zero,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 14),
  });

  final String title;
  final String subtitle;
  final String eyebrow;
  final String? badge;
  final Widget? leading;
  final List<Widget> metrics;
  final List<Widget> actions;
  final Gradient accentGradient;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(AppTokens.radiusXl),
        border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
        boxShadow: AppTokens.shadowLg(color: AppTokens.primaryBlue),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        child: Stack(
          children: [
            Positioned(
              right: -18,
              top: -20,
              child: Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: accentGradient,
                ),
                foregroundDecoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.72),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ?leading,
                    const Spacer(),
                    if (badge != null) AppStatusPill(label: badge!),
                  ],
                ),
                // eyebrow 为空时折叠，避免空行占位
                if (eyebrow.trim().isNotEmpty) ...[
                  const SizedBox(height: 9),
                  Text(
                    eyebrow,
                    style: const TextStyle(
                      color: AppTokens.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                ] else
                  const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTokens.textPrimary,
                    fontSize: 25,
                    height: 1.03,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppTokens.textSecondary,
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                if (metrics.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(children: metrics),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AppStatusPill extends StatelessWidget {
  const AppStatusPill({
    super.key,
    required this.label,
    this.icon,
    this.color = AppTokens.primaryBlue,
  });

  final String label;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class AppCompactActionCard extends StatelessWidget {
  const AppCompactActionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTokens.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTokens.textSecondary,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      onTap: onTap,
      child: card,
    );
  }
}
