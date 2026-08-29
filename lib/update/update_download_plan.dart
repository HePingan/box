import 'update_models.dart';
import 'update_security.dart';

/// 把 manifest 里的下载地址整理成一个按优先级排序的尝试列表。
///
/// 存在的理由（A2）：后台一直在下发 `backupDownloadUrl`，但下载逻辑从来没读过
/// 它——主地址挂了就整条失败。把"该试哪些地址、按什么顺序"从下载动作里拆出来，
/// 既能让备用线路真正生效，也让这段决策可以单测，不必真的发网络请求。
///
/// 同时补上白名单校验（A3）：安装器原先调用 `validateUpdateDownloadUrl` 时没传
/// `allowedHosts`，而空白名单在 update_security 里等于全放通。验签层已经拦住了
/// 篡改，所以这是纵深防御多加一道，不是在补已发生的漏洞。
///
/// 主地址不合法直接抛异常（没有可用地址，早失败早暴露）；
/// 备用地址不合法只是被跳过（不该因为运营填错备用线路就让整个更新不可用）。
List<String> buildUpdateDownloadPlan({
  required UpdateManifest manifest,
  required UpdateManifestSecurityConfig security,
}) {
  final primary = manifest.downloadUrl.trim();
  if (primary.isEmpty) {
    throw Exception('下载地址为空');
  }

  // 主地址：不合格就抛，让调用方看到明确原因。
  validateUpdateDownloadUrl(
    primary,
    requireHttps: security.requireHttpsDownloadUrl,
    allowedHosts: security.allowedDownloadHosts,
  );

  final plan = <String>[primary];

  final backup = manifest.backupDownloadUrl?.trim() ?? '';
  if (backup.isNotEmpty &&
      backup != primary &&
      isValidUpdateDownloadUrl(
        backup,
        requireHttps: security.requireHttpsDownloadUrl,
        allowedHosts: security.allowedDownloadHosts,
      )) {
    plan.add(backup);
  }

  return plan;
}
