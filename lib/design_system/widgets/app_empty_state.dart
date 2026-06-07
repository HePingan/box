import 'package:flutter/material.dart';

import '../app_tokens.dart';

/// Compact empty/error/info state used by pages and panels.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: colorScheme.primary),
            const SizedBox(height: AppTokens.spaceMd),
            Text(
              title,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            if (message != null && message!.trim().isNotEmpty) ...[
              const SizedBox(height: AppTokens.spaceSm),
              Text(
                message!,
                style: textTheme.bodyMedium?.copyWith(
                  color: AppTokens.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppTokens.spaceLg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
