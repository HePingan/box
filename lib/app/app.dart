import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../design_system/app_theme.dart';
import '../globals.dart';
import '../update/update_bootstrap_page.dart';
import 'app_bootstrap.dart';
import 'app_routes.dart';
import 'app_shell.dart';

class BoxApp extends StatelessWidget {
  const BoxApp({super.key, required this.bootstrap});

  final AppBootstrapResult bootstrap;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Geek工具箱',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [appRouteObserver],
      routes: AppRoutes.buildRoutes(bootstrap.novelBootstrap),
      theme: AppTheme.light(),
      home: UpdateBootstrapPage(
        nextPage: MainAppShell(novelBootstrap: bootstrap.novelBootstrap),
        appId: AppConfig.appId,
        checkUrl: AppConfig.updateCheckUrl,
        platform: AppConfig.updatePlatform,
        channel: AppConfig.appChannel,
        allowProceedOnCheckFailure: AppConfig.allowProceedOnCheckFailure,
      ),
    );
  }
}
