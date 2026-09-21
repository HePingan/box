import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_config.dart';
import 'update_dialog.dart';
import 'update_service.dart';

/// 手动检查更新的公共实现。
///
/// 为什么提取出来：这段逻辑原本是 `app_drawer.dart` 的私有方法
/// `_checkUpdateManually`，而关于页也要有「检查更新」。抄一份过去就会出现
/// 两套手动检查逻辑，以后修一处漏一处 —— 这类重复正是这个项目要避免的。
///
/// 这里面有三处**踩过坑才写成这样**的细节，改动前请先读：
///
/// 1. `messenger` / `navigator` 必须在 `await` **之前**抓好。
///    宿主（抽屉、弹窗）可能在等待期间被关掉，await 之后再 `.of(context)`
///    就会查到一个失效的 context。
///
/// 2. 刻意**不判** `context.mounted`。
///    messenger 与 navigator 的生命周期挂在 App 上，不随宿主消亡；判 mounted
///    的旧写法会在宿主关闭后把结果整个丢掉，用户只看到「点了没反应」。
///    见 `test/update/manual_check_snackbar_test.dart`。
///
/// 3. [resultInDialog] 存在的唯一理由：**SnackBar 会被抽屉盖住**。
///    抽屉那条路径必须走对话框，否则提示弹了也看不见。整页入口（关于页）
///    没这个问题，用 SnackBar 更轻。
class ManualUpdateCheck {
  const ManualUpdateCheck._();

  /// 执行一次手动检查并展示结果。
  ///
  /// [closeHost] 用于在发现新版本时先收掉宿主弹窗，避免两层弹窗叠在一起。
  /// 抽屉不是路由，不要传 —— pop 一下会把身下的主页面顶掉。
  ///
  /// [resultInDialog] 为 true 时结论走 AlertDialog（抽屉场景必须如此）。
  static Future<void> run(
    BuildContext context,
    PackageInfo info, {
    VoidCallback? closeHost,
    bool resultInDialog = false,
    UpdateService? service,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // 「正在检查…」同样会被抽屉盖住，弹了也是白弹。抽屉那条路径改由
    // 列表项自己转圈提示进行中。
    if (!resultInDialog) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('正在检查更新…'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    final currentCode = int.tryParse(info.buildNumber) ?? 0;
    final outcome = await (service ?? UpdateService.instance)
        .checkUpdateDiagnostic(
      checkUrl: AppConfig.updateCheckUrl,
      appId: AppConfig.appId,
      platform: AppConfig.updatePlatform,
      channel: AppConfig.appChannel,
      versionCode: currentCode,
      packageName: info.packageName,
      security: AppConfig.updateSecurityConfig,
    );

    // 见类注释第 2 点：这里刻意不判 context.mounted。
    final manifest = outcome.manifest;
    if (outcome.hasUpdate && manifest != null) {
      closeHost?.call();
      // 判 navigator 而不是判宿主 context：navigator 活得和 App 一样久，
      // 宿主 context 可能刚被 closeHost 关掉，判它必然提前 return。
      if (!navigator.mounted) return;
      await showDialog(
        context: navigator.context,
        builder: (_) => UpdateDialog(
          manifest: manifest,
          currentVersionName: info.version,
          currentVersionCode: currentCode,
          force: manifest.needForceUpdate(currentCode),
          security: AppConfig.updateSecurityConfig,
        ),
      );
      return;
    }

    if (resultInDialog) {
      if (!navigator.mounted) return;
      await showDialog<void>(
        context: navigator.context,
        builder: (dialogContext) => AlertDialog(
          title: Text(outcome.isFailure ? '检查更新失败' : '检查更新'),
          content: Text(outcome.describe()),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(outcome.describe()),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: outcome.isFailure ? 6 : 2),
      ),
    );
  }
}
