import 'update_models.dart';

/// 一次更新检查的结论。
///
/// 为什么需要它（A4）：`UpdateService.checkUpdate` 只返回 `UpdateManifest?`，
/// null 同时代表「没有更新」「网络失败」「验签被拒」三种完全不同的情况，且
/// 内部是 `catch (_)` 把原因整个吞掉。配合 allowProceedOnCheckFailure 默认
/// true，结果就是验签一直失败、界面一直静默 —— HMAC 口径 bug 能活那么久，
/// 缺少可见的失败原因是主要原因之一。
///
/// 这个类型只做「分类 + 说人话」，不碰网络，因此可以完整单测。
enum UpdateCheckStatus {
  updateAvailable,
  upToDate,
  networkError,
  signatureRejected,
  badResponse,
  notConfigured,
}

class UpdateCheckOutcome {
  const UpdateCheckOutcome._({
    required this.status,
    this.manifest,
    this.detail,
  });

  final UpdateCheckStatus status;
  final UpdateManifest? manifest;

  /// 原始错误信息。保留下来是为了排查真实问题，不做美化。
  final String? detail;

  factory UpdateCheckOutcome.fromManifest({
    required UpdateManifest manifest,
    required int currentVersionCode,
  }) {
    // 与 UpdateManifest.hasNewVersion 保持同一口径：后台版本不高于本机
    // 就是「已是最新」。后台目前最新发布 118 而工程已 169，这条很关键。
    final hasNew = manifest.hasNewVersion(currentVersionCode);
    return UpdateCheckOutcome._(
      status: hasNew
          ? UpdateCheckStatus.updateAvailable
          : UpdateCheckStatus.upToDate,
      manifest: manifest,
    );
  }

  factory UpdateCheckOutcome.failure(
    UpdateCheckStatus status, {
    String? detail,
  }) {
    return UpdateCheckOutcome._(status: status, detail: detail);
  }

  bool get hasUpdate => status == UpdateCheckStatus.updateAvailable;

  bool get isFailure =>
      status != UpdateCheckStatus.updateAvailable &&
      status != UpdateCheckStatus.upToDate;

  String describe() => describeUpdateCheckStatus(
        status,
        latestVersionCode: manifest?.latestVersionCode,
        latestVersionName: manifest?.latestVersionName,
        detail: detail,
      );
}

/// 把一次更新检查的结论说成人话。
///
/// 抽成顶层函数是因为**关于页的「上次检查」**要显示同一件事，而那时 outcome
/// 对象早已不存在（只剩落盘的 status / detail）。两处各写一套 switch，措辞迟早
/// 不一致 —— 用户会在两个位置看到对同一次检查的不同描述。
///
/// 只吃版本号的**两个字段**而不是整个 manifest：落盘记录里不会存完整清单，
/// 硬塞一个「字段残缺的 manifest」会让调用方以为拿到的是真清单。
String describeUpdateCheckStatus(
  UpdateCheckStatus status, {
  int? latestVersionCode,
  String? latestVersionName,
  String? detail,
}) {
  final d = detail?.trim() ?? '';
  final suffix = d.isEmpty ? '' : '（$d）';

  switch (status) {
    case UpdateCheckStatus.updateAvailable:
      final parts = <String>[
        if (latestVersionName != null && latestVersionName.isNotEmpty)
          latestVersionName,
        if (latestVersionCode != null) '($latestVersionCode)',
      ];
      final label = parts.join(' ');
      return label.isEmpty ? '发现新版本' : '发现新版本 $label';
    case UpdateCheckStatus.upToDate:
      return '已是最新版本';
    case UpdateCheckStatus.networkError:
      return '网络请求失败，请稍后重试$suffix';
    case UpdateCheckStatus.signatureRejected:
      return '更新清单签名校验未通过$suffix';
    case UpdateCheckStatus.badResponse:
      return '服务端返回格式异常$suffix';
    case UpdateCheckStatus.notConfigured:
      return '未配置更新检查地址$suffix';
  }
}
