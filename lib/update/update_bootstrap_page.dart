import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'update_check_outcome.dart';
import 'update_dialog.dart';
import 'update_security.dart';
import 'update_service.dart';

/// 启动时的更新检查（B2：非阻塞）。
///
/// 旧行为是「先白屏等检查，再进主界面」：本页是 `home:`，网络超时配置为
/// connect 8s + receive 10s，最坏情况用户要盯着近 20 秒的加载圈。而
/// allowProceedOnCheckFailure 默认 true，意味着任何失败都被静默放行——
/// 验签口径 bug 能长期存活没被发现，缺少可见失败原因是主因之一。
///
/// 新行为：主界面立即渲染，检查在后台进行；只有确实存在新版本才弹窗。
/// 强制更新依然拦得住（弹窗不可绕过），只是拦截点从「进门前」变成
/// 「进门后立刻」——这样即使更新服务整体挂掉，用户也不会被关在门外。
class UpdateBootstrapPage extends StatefulWidget {
  final Widget nextPage;
  final String appId;
  final String checkUrl;
  final String platform;
  final String channel;

  final UpdateManifestSecurityConfig updateSecurity;

  /// 保留该参数仅为兼容既有调用方。非阻塞模式下检查失败一律放行，
  /// 因为主界面早已显示，不存在"卡在门外"的情形。
  final bool allowProceedOnCheckFailure;

  /// 测试注入：跳过真实网络请求。
  @visibleForTesting
  final Future<UpdateCheckOutcome> Function()? checkOverride;

  /// 测试注入：跳过 PackageInfo 平台调用。
  @visibleForTesting
  final int? currentVersionCodeOverride;

  /// 检查诊断信息回调。失败原因走这里，不再被静默吞掉。
  final void Function(String message)? onCheckDiagnostic;

  const UpdateBootstrapPage({
    super.key,
    required this.nextPage,
    required this.appId,
    required this.checkUrl,
    required this.platform,
    required this.channel,
    this.allowProceedOnCheckFailure = true,
    this.updateSecurity = const UpdateManifestSecurityConfig(),
    this.checkOverride,
    this.currentVersionCodeOverride,
    this.onCheckDiagnostic,
  });

  @override
  State<UpdateBootstrapPage> createState() => _UpdateBootstrapPageState();
}

class _UpdateBootstrapPageState extends State<UpdateBootstrapPage> {
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    // 不 await：主界面这一帧就渲染，检查在后台跑。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInBackground();
    });
  }

  Future<void> _checkInBackground() async {
    if (kIsWeb) return;

    try {
      final int currentCode;
      final String versionName;
      final String packageName;

      final override = widget.currentVersionCodeOverride;
      if (override != null) {
        currentCode = override;
        versionName = '$override';
        // 仅测试注入路径会走到这里。必须与 applicationId 一致，
        // 否则服务端按 package_name 过滤会查不到发布版本。
        packageName = 'top.hpa888.box';
      } else {
        final info = await PackageInfo.fromPlatform();
        currentCode = int.tryParse(info.buildNumber) ?? 0;
        versionName = info.version;
        packageName = info.packageName;
      }

      final outcome = widget.checkOverride != null
          ? await widget.checkOverride!()
          : await UpdateService.instance.checkUpdateDiagnostic(
              checkUrl: widget.checkUrl,
              appId: widget.appId,
              platform: widget.platform,
              channel: widget.channel,
              versionCode: currentCode,
              packageName: packageName,
              security: widget.updateSecurity,
            );

      if (!mounted) return;

      if (outcome.isFailure) {
        // 不再 catch(_) 静默：把原因交出去，至少 debug 日志能看到。
        _report('更新检查失败：${outcome.describe()}');
        return;
      }

      final manifest = outcome.manifest;
      if (!outcome.hasUpdate || manifest == null) {
        _report('更新检查完成：${outcome.describe()}');
        return;
      }

      final force = manifest.needForceUpdate(currentCode);
      if (_dialogShown) return;
      _dialogShown = true;

      await showDialog(
        context: context,
        barrierDismissible: !force,
        builder: (_) => UpdateDialog(
          manifest: manifest,
          currentVersionName: versionName,
          currentVersionCode: currentCode,
          force: force,
          security: widget.updateSecurity,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _report('更新检查异常：$e');
    }
  }

  void _report(String message) {
    widget.onCheckDiagnostic?.call(message);
    if (kDebugMode) debugPrint(message);
  }

  @override
  Widget build(BuildContext context) {
    // 直接就是主界面：没有中间加载页，也就没有白屏等待。
    return widget.nextPage;
  }
}
