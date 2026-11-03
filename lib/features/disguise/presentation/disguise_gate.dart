import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_bootstrap.dart';
import '../../../design_system/app_theme.dart';
import '../data/disguise_platform.dart';
import '../domain/disguise_session.dart';
import '../domain/disguise_settings.dart';
import 'calculator_disguise_page.dart';

/// 伪装闸门：锁着的时候，整个应用**只有**一支计算器。
///
/// ## 为什么必须包在 `BoxApp` 之外
///
/// 与 `LegalConsentGate` 同一个理由：套在 BoxApp 里面的话，用户可以通过
/// Navigator 返回、底栏切页、深链跳转绕过它 —— 闸门就成了摆设。这里直接
/// **不构建**真应用，锁着的时候内存里根本没有那个界面。
///
/// ## 三件事都在这里做（散在别处一定会各做各的）
///
/// 1. **启动自愈**：OTA 覆盖安装会把 activity-alias 的启用状态重置成 manifest
///    默认值，图标自己变回「极客匣」。所以每次启动都拿本地偏好和系统的真实
///    状态对一次，不一致就重新切。
/// 2. **切后台自动上锁**：`paused` 记时刻，`resumed` 算差值。不用定时器 ——
///    手机深度睡眠时定时器根本不会按时跑。
/// 3. **最近任务缩略图遮挡**（可选）：按设置开关 FLAG_SECURE。
class DisguiseGate extends StatefulWidget {
  const DisguiseGate({super.key, required this.settings, required this.child});

  final DisguiseSettings settings;

  /// 真应用。
  final Widget child;

  @override
  State<DisguiseGate> createState() => _DisguiseGateState();
}

class _DisguiseGateState extends State<DisguiseGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DisguiseSession.instance.addListener(_onSessionChanged);
    unawaited(_syncNative());
  }

  @override
  void dispose() {
    DisguiseSession.instance.removeListener(_onSessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// 与原生侧对齐一次：图标状态自愈 + 缩略图遮挡。
  Future<void> _syncNative() async {
    final enabled = widget.settings.enabled;
    await DisguisePlatform.instance.heal(enabled);
    await DisguisePlatform.instance.setSecureRecents(
      enabled && widget.settings.secureRecents,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
        DisguiseSession.instance.markBackgrounded();
      case AppLifecycleState.resumed:
        final locked = DisguiseSession.instance.lockIfIdle(
          widget.settings.relockMinutes,
        );
        if (!locked) {
          DisguiseSession.instance.markForeground();
        }
        // 回到前台重新压一次 FLAG_SECURE：部分 ROM 在这个窗口上会丢 flag。
        if (widget.settings.enabled && widget.settings.secureRecents) {
          unawaited(DisguisePlatform.instance.setSecureRecents(true));
        }
      case AppLifecycleState.detached:
        break;
    }
  }

  void _unlock() {
    DisguiseSession.instance.unlock();
    // 计算器界面把状态栏改成白底深色图标；进真应用要交还给应用自己的规则。
    AppBootstrap.applySystemUi();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final bool showDisguise =
        settings.enabled && !DisguiseSession.instance.unlocked;

    if (!showDisguise) {
      return widget.child;
    }

    // 锁着的时候只构建计算器：一个自带 MaterialApp 的独立界面，
    // 不接真应用的 Navigator，也就不存在任何"切走"的入口。
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: CalculatorDisguisePage(settings: settings, onUnlock: _unlock),
    );
  }
}
