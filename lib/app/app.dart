import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../design_system/app_theme.dart';
import '../design_system/app_theme_controller.dart';
import '../globals.dart';
import '../update/update_bootstrap_page.dart';
import 'app_bootstrap.dart';
import 'app_routes.dart';
import '../features/extensions/plugins/remote_storage/presentation/share_inbox_gate.dart';
import 'app_shell.dart';
import '../design_system/app_theme_scope.dart';

class BoxApp extends StatefulWidget {
  const BoxApp({super.key, required this.bootstrap});

  final AppBootstrapResult bootstrap;

  @override
  State<BoxApp> createState() => _BoxAppState();
}

class _BoxAppState extends State<BoxApp> with WidgetsBindingObserver {
  final AppThemeController _theme = AppThemeController.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _theme.addListener(_onThemeChanged);
    // 读盘是异步的：读出来之前先按默认（跟随系统）渲染，不留白屏。
    unawaited(_theme.load().then((_) => AppBootstrap.applySystemUi()));
    AppBootstrap.applySystemUi();
  }

  @override
  void dispose() {
    _theme.removeListener(_onThemeChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onThemeChanged() {
    // 系统状态栏/导航栏图标亮度要跟着一起变，否则深色下图标看不见。
    AppBootstrap.applySystemUi();
    if (mounted) setState(() {});
  }

  @override
  void didChangePlatformBrightness() {
    _theme.updatePlatformBrightness(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bootstrap = widget.bootstrap;
    // 深浅切换必须当场生效（不能"退出重进才变"）：
    // `AppTokens` 是 static getter，已建好的页面不会自己重建，所以
    // ① 用 AppThemeScope 把控制器挂成 InheritedNotifier；
    // ② 每个路由入口与外壳都用 AppThemeRebuild 包一层 —— 它必须传 builder，
    //    传现成的 widget 实例会被 Element 短路（`child.widget == newWidget`）。
    return AppThemeScope(
      controller: _theme,
      child: MaterialApp(
        title: '极客匣',
        debugShowCheckedModeBanner: false,
        navigatorObservers: [appRouteObserver],
        routes: <String, WidgetBuilder>{
          for (final MapEntry<String, WidgetBuilder> entry
              in AppRoutes.buildRoutes(bootstrap.novelBootstrap).entries)
            entry.key: (context) => AppThemeRebuild(builder: entry.value),
        },
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: _theme.themeMode,
        // ShareInboxGate 放在 home 之下、Navigator 之上（286 P3）：
        // 放在 MaterialApp.builder 里会拿不到 Navigator（弹不出面板），
        // 放在 BoxApp 之外又会被用户切页绕过。
        home: AppThemeRebuild(
          builder: (context) => ShareInboxGate(
            child: UpdateBootstrapPage(
              nextPage: MainAppShell(novelBootstrap: bootstrap.novelBootstrap),
              appId: AppConfig.appId,
              checkUrl: AppConfig.updateCheckUrl,
              platform: AppConfig.updatePlatform,
              channel: AppConfig.appChannel,
              allowProceedOnCheckFailure: AppConfig.allowProceedOnCheckFailure,
              updateSecurity: AppConfig.updateSecurityConfig,
            ),
          ),
        ),
      ),
    );
  }
}
