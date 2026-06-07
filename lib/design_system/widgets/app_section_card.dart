import 'package:flutter/material.dart';

import '../app_tokens.dart';

/// Reusable rounded card with consistent spacing and border radius.
class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppTokens.spaceLg),
    this.margin = const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: AppTokens.divider),
      ),
      child: Padding(padding: padding, child: child),
    );

    return Padding(
      padding: margin,
      child: onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                onTap: onTap,
                child: content,
              ),
            ),
    );
  }
}
