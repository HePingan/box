import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_tokens.dart';

/// A safe ValueListenableBuilder that manually manages listener lifecycle
/// to prevent `Assertion failed: ancestor == this` crashes on Flutter web
/// when the notifier fires during route transitions or widget disposal.
class SafeValueListenableBuilder<T> extends StatefulWidget {
  const SafeValueListenableBuilder({
    super.key,
    required this.valueListenable,
    required this.builder,
    this.child,
  });

  final ValueListenable<T> valueListenable;
  final Widget Function(BuildContext context, T value, Widget? child) builder;
  final Widget? child;

  @override
  State<SafeValueListenableBuilder<T>> createState() =>
      _SafeValueListenableBuilderState<T>();
}

class _SafeValueListenableBuilderState<T>
    extends State<SafeValueListenableBuilder<T>> {
  late T _latestValue;

  @override
  void initState() {
    super.initState();
    _latestValue = widget.valueListenable.value;
    widget.valueListenable.addListener(_onValueChange);
  }

  @override
  void didUpdateWidget(SafeValueListenableBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.valueListenable != widget.valueListenable) {
      oldWidget.valueListenable.removeListener(_onValueChange);
      widget.valueListenable.addListener(_onValueChange);
      _latestValue = widget.valueListenable.value;
    }
  }

  @override
  void dispose() {
    widget.valueListenable.removeListener(_onValueChange);
    super.dispose();
  }

  void _onValueChange() {
    if (!mounted) return;
    setState(() {
      _latestValue = widget.valueListenable.value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _latestValue, widget.child);
  }
}

/// A safe AnimatedBuilder that manually manages Listenable listener lifecycle
/// to prevent `Assertion failed: ancestor == this` crashes.
class SafeAnimatedBuilder extends StatefulWidget {
  const SafeAnimatedBuilder({
    super.key,
    required this.animation,
    required this.builder,
    this.child,
  });

  final Listenable animation;
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  @override
  State<SafeAnimatedBuilder> createState() => _SafeAnimatedBuilderState();
}

class _SafeAnimatedBuilderState extends State<SafeAnimatedBuilder> {
  @override
  void initState() {
    super.initState();
    widget.animation.addListener(_onAnimationChange);
  }

  @override
  void didUpdateWidget(SafeAnimatedBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeListener(_onAnimationChange);
      widget.animation.addListener(_onAnimationChange);
    }
  }

  @override
  void dispose() {
    widget.animation.removeListener(_onAnimationChange);
    super.dispose();
  }

  void _onAnimationChange() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, widget.child);
  }
}

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
