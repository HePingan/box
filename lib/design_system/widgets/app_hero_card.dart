import 'package:flutter/material.dart';

import '../app_tokens.dart';

/// Reusable gradient hero surface for top-of-page identity blocks.
class AppHeroCard extends StatelessWidget {
  const AppHeroCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.gradient,
    this.badge,
    this.icon,
    this.metrics = const [],
    this.actions = const [],
    this.margin = const EdgeInsets.fromLTRB(16, 10, 16, 14),
  });

  final String title;
  final String subtitle;
  final Gradient gradient;
  final String? badge;
  final IconData? icon;
  final List<Widget> metrics;
  final List<Widget> actions;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(AppTokens.radiusXl),
        boxShadow: AppTokens.heroShadow(),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -34,
            top: -30,
            child: _GlowBlob(size: 112, opacity: 0.16),
          ),
          Positioned(
            right: 42,
            bottom: -44,
            child: _GlowBlob(size: 92, opacity: 0.10),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icon != null)
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Icon(icon, color: Colors.white, size: 25),
                    ),
                  const Spacer(),
                  if (badge != null && badge!.trim().isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(
                          AppTokens.radiusPill,
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
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
                Row(
                  children: [
                    for (int i = 0; i < metrics.length; i++) ...[
                      Expanded(child: metrics[i]),
                      if (i != metrics.length - 1) const SizedBox(width: 10),
                    ],
                  ],
                ),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(spacing: 10, runSpacing: 10, children: actions),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: opacity),
      ),
    );
  }
}
