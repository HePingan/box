import 'package:flutter/material.dart';

import '../app_tokens.dart';

/// Small metric block designed for hero cards and dashboards.
class AppMetricTile extends StatelessWidget {
  const AppMetricTile({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.foreground = Colors.white,
    this.background,
  });

  final String value;
  final String label;
  final IconData? icon;
  final Color foreground;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: background ?? foreground.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: foreground.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: foreground.withValues(alpha: 0.88), size: 16),
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
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: foreground.withValues(alpha: 0.72),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
