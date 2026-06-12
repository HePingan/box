import 'package:flutter/material.dart';

import '../app_tokens.dart';

class AppPageScaffold extends StatelessWidget {
  const AppPageScaffold({
    super.key,
    required this.child,
    this.backgroundColor = AppTokens.background,
    this.useGradient = true,
    this.safeTop = true,
    this.safeBottom = false,
  });

  final Widget child;
  final Color backgroundColor;
  final bool useGradient;
  final bool safeTop;
  final bool safeBottom;

  @override
  Widget build(BuildContext context) {
    final body = DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        gradient: useGradient ? AppTokens.pageGradient : null,
      ),
      child: SafeArea(top: safeTop, bottom: safeBottom, child: child),
    );

    return Scaffold(backgroundColor: backgroundColor, body: body);
  }
}
