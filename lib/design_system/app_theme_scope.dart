import 'package:flutter/widgets.dart';

import 'app_theme_controller.dart';

/// 主题（深浅）作用域。
///
/// 为什么必须有这一层：`AppTokens` 的颜色是 **static getter**（深色批次 1 的
/// 路线 B），已经建好的页面不会因为"静态值变了"而重建 —— Flutter 只重建
/// 真正建立了依赖的 widget。所以切换深浅时，页面会保持旧颜色，直到退出重进。
///
/// 用法：`AppThemeScope` 放在 `MaterialApp` **之上**，任何需要通过
/// `AppTokens` 重画的层级用 [AppThemeRebuild] 包一层（路由入口、外壳的每个
/// 页签都是这样接的）。
class AppThemeScope extends InheritedNotifier<AppThemeController> {
  const AppThemeScope({
    super.key,
    required AppThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  /// 建立依赖：之后的深浅切换会让调用者重建。
  static AppThemeController watch(BuildContext context) {
    final AppThemeScope? scope =
        context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
    return scope?.notifier ?? AppThemeController.instance;
  }
}

/// 让 [builder] 的产物在深浅切换时整体重建。
///
/// **必须传 builder 而不是现成的 child widget**：传同一个 widget 实例时，
/// Element 会在 `updateChild` 里发现 `child.widget == newWidget` 直接短路，
/// 表现就是"改了要退出重进才会变"。
class AppThemeRebuild extends StatelessWidget {
  const AppThemeRebuild({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    AppThemeScope.watch(context);
    return builder(context);
  }
}
