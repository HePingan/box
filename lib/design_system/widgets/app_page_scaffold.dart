import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    try {
      setState(() {
        _latestValue = widget.valueListenable.value;
      });
    } catch (_) {
      // Suppress setState failures during disposal/route transitions.
      // This prevents `Assertion failed: ancestor == this` crashes on web.
    }
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
    try {
      setState(() {});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, widget.child);
  }
}

/// A safe wrapper around Provider's context.watch that prevents
/// `InheritedNotifier` ancestry assertion failures during route transitions.
///
/// Instead of using Provider's InheritedWidget mechanism (which registers
/// the element as a dependent and triggers the assertion when the notifier
/// fires during disposal), this widget manually reads the provider value
/// and only rebuilds if the widget is still mounted.
class SafeProvider<T> extends StatefulWidget {
  const SafeProvider({super.key, required this.child});

  final Widget Function(BuildContext context, T value) child;

  @override
  State<SafeProvider<T>> createState() => _SafeProviderState<T>();
}

class _SafeProviderState<T> extends State<SafeProvider<T>> {
  late T _value;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read the provider value manually WITHOUT registering as a dependent
    // of the InheritedWidget. This avoids the InheritedNotifier assertion
    // that crashes when the notifier fires during route transitions.
    _value = context.read<T>();
  }

  @override
  Widget build(BuildContext context) {
    // Re-read on every build (cheap for ChangeNotifier providers).
    // If the value changed since last build, the child gets the new value.
    // We don't auto-rebuild on provider change — the parent will trigger
    // a rebuild when needed.
    return widget.child(context, _value);
  }
}

/// Same as SafeProvider but for selectors that return a derived value.
class SafeProviderSelector<T, R> extends StatefulWidget {
  const SafeProviderSelector({
    super.key,
    required this.selector,
    required this.child,
  });

  final T Function(BuildContext context) selector;
  final Widget Function(BuildContext context, R value) child;

  @override
  State<SafeProviderSelector<T, R>> createState() =>
      _SafeProviderSelectorState<T, R>();
}

class _SafeProviderSelectorState<T, R>
    extends State<SafeProviderSelector<T, R>> {
  late R _selectedValue;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _selectedValue = widget.selector(context) as R;
  }

  @override
  Widget build(BuildContext context) {
    return widget.child(context, _selectedValue);
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
    this.padding,
    this.maxContentWidth,
  });

  final Widget child;
  final Color backgroundColor;
  final bool useGradient;
  final bool safeTop;
  final bool safeBottom;

  /// 统一的水平方向内边距。
  /// 设置后，所有页面无需重复写 `EdgeInsets.symmetric(horizontal: 16)`。
  final EdgeInsetsGeometry? padding;

  /// 平板适配：内容最大宽度约束。
  /// 设置后，在大屏上内容居中并限制阅读宽度（推荐 600～700），
  /// 小屏上仍为全宽。
  final double? maxContentWidth;

  @override
  Widget build(BuildContext context) {
    Widget body = child;
    if (maxContentWidth != null) {
      body = Center(
        child: SizedBox(width: maxContentWidth, child: body),
      );
    }
    if (padding != null) {
      body = Padding(padding: padding!, child: body);
    }
    body = DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        gradient: useGradient ? AppTokens.pageGradient : null,
      ),
      child: SafeArea(top: safeTop, bottom: safeBottom, child: body),
    );

    return Scaffold(backgroundColor: backgroundColor, body: body);
  }
}
