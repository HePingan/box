import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../design_system/app_theme.dart';
import '../globals.dart';
import '../update/update_bootstrap_page.dart';
import 'app_bootstrap.dart';
import 'app_routes.dart';
import '../features/extensions/plugins/remote_storage/presentation/share_inbox_gate.dart';
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
      // ShareInboxGate 放在 home 之下、Navigator 之上（286 P3）：
      // 放在 MaterialApp.builder 里会拿不到 Navigator（弹不出面板），
      // 放在 BoxApp 之外又会被用户切页绕过。
      home: ShareInboxGate(
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
    );
  }
}
