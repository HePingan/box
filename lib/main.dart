import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_bootstrap.dart';
import 'app/app_providers.dart';
import 'features/account/data/account_store.dart';
import 'features/policy/plugin_policy.dart';

void main() {
  // Step 0: 尽早加载登录态，这样 AppDrawer 打开时无需等待
  BoxAccountStore().loadSession().then((session) {
    globalSessionNotifier.value = session;
    // 登录态就绪后拉一次插件远程策略
    PluginPolicyStore.instance.refresh(force: true);
  });
  // 无登录也先加载缓存并尝试拉全局策略
  PluginPolicyStore.instance.ensureLoaded().then((_) {
    PluginPolicyStore.instance.refresh();
  });

  // 注册全局错误处理：调试模式上报到控制台，不再静默吞掉 AssertionError。
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  runApp(_AppBootstrapper());
}

class _AppBootstrapper extends StatefulWidget {
  @override
  State<_AppBootstrapper> createState() => _AppBootstrapperState();
}

class _AppBootstrapperState extends State<_AppBootstrapper> {
  AppBootstrapResult? _bootstrap;
  Object? _error;

  @override
  void initState() {
    super.initState();
    AppBootstrap.initialize()
        .then((result) {
          if (mounted) {
            setState(() {
              _bootstrap = result;
            });
          }
        })
        .catchError((err) {
          if (mounted) {
            setState(() {
              _error = err;
            });
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MaterialApp(
        home: Scaffold(body: Center(child: Text('Bootstrap failed: $_error'))),
      );
    }
    if (_bootstrap == null) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return AppProviders(
      bootstrap: _bootstrap!,
      child: BoxApp(bootstrap: _bootstrap!),
    );
  }
}
