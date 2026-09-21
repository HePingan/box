import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'app/app.dart';
import 'app/app_bootstrap.dart';
import 'app/app_providers.dart';
import 'features/about/domain/legal_consent_store.dart';
import 'features/about/presentation/legal_consent_gate.dart';
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

  /// 协议闸门状态。null 表示还没判定（bootstrap 未完成）。
  LegalConsentStore? _consent;

  /// 本次启动是否仍需展示闸门。同意成功后置 false 放行。
  bool _needsConsent = false;

  @override
  void initState() {
    super.initState();
    AppBootstrap.initialize()
        .then((result) {
          if (mounted) {
            final consent = LegalConsentStore(result.prefs);
            setState(() {
              _bootstrap = result;
              _consent = consent;
              _needsConsent = consent.needsConsent;
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
    // 协议闸门放在 BoxApp **之外**：套在里面的话用户可以通过 Navigator 或
    // 底栏切走绕过它，同意流程就形同虚设。这里直接不构建 BoxApp。
    if (_needsConsent) {
      final consent = _consent!;
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: LegalConsentGate(
          isReconsent: consent.isReconsent,
          onAccept: () async {
            final ok = await consent.accept();
            // 写入失败不放行：假装成功的话用户下次启动会再被拦一次，
            // 而且不知道为什么。闸门自己会提示重试。
            if (ok && mounted) {
              setState(() => _needsConsent = false);
            }
            return ok;
          },
          // 不同意只能退出：协议是使用前提，给"跳过"等于协议不成立。
          onDecline: () => SystemNavigator.pop(),
        ),
      );
    }
    return AppProviders(
      bootstrap: _bootstrap!,
      child: BoxApp(bootstrap: _bootstrap!),
    );
  }
}
