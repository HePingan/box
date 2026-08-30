/// 安装失败的分类。
///
/// 为什么需要这个：强更弹窗是 `canPop: false` 的，用户关不掉。如果失败原因是
/// 「系统拒绝安装」（典型是签名证书换了，老包装不上新包），那么重试一万次都是
/// 同样结果 —— 用户会被永久锁在一个关不掉的弹窗里，App 彻底不可用，且没有任何
/// 自救路径。这类失败必须和「网络抖动」区别对待：前者要给逃生门（手动下载 +
/// 允许退出 + 提示先备份再卸载重装），后者只需要让他再点一次。
class InstallFailureKind {
  const InstallFailureKind({
    required this.isUnrecoverable,
    required this.needsManualReinstall,
    required this.guidance,
  });

  /// 重试不可能成功，UI 必须放弃「再试一次」这条路。
  final bool isUnrecoverable;

  /// 需要用户手动卸载重装（会丢本地数据，所以必须先提示备份）。
  final bool needsManualReinstall;

  /// 给用户看的中文指引。
  final String guidance;
}

/// 系统层面「装不上去」的标志串。
///
/// `INSTALL_FAILED_UPDATE_INCOMPATIBLE` / `INSTALL_FAILED_SHARED_USER_INCOMPATIBLE`
/// 都是签名证书不一致导致的覆盖安装失败。中文串来自 `app_installer_io.dart`
/// 里 `_launchInstaller()` 抛出的 `系统拒绝安装: ...`，以及部分 ROM 的本地化文案。
const _unrecoverableMarkers = <String>[
  'INSTALL_FAILED_UPDATE_INCOMPATIBLE',
  'INSTALL_FAILED_SHARED_USER_INCOMPATIBLE',
  'INSTALL_FAILED_ALREADY_EXISTS',
  'INSTALL_PARSE_FAILED_INCONSISTENT_CERTIFICATES',
  'signatures do not match',
  '系统拒绝安装',
  '签名不一致',
  '证书不一致',
];

const _reinstallGuidance =
    '当前安装包的签名与已安装版本不一致，系统不允许直接覆盖安装。\n\n'
    '请按以下步骤处理：\n'
    '1. 先用下方「导出备份」保存收藏、历史与题库；\n'
    '2. 卸载当前应用；\n'
    '3. 安装新版本后，在「更多 → 恢复本地数据」导入刚才的备份。\n\n'
    '注意：不备份直接卸载会丢失本地收藏、观看历史与未上传的题库。';

const _retryGuidance = '下载或校验没有完成，通常是网络波动导致的。请检查网络后重试。';

/// 判断一个安装/下载失败是否属于「重试也没用」的类型。
InstallFailureKind classifyInstallFailure(Object error) {
  final text = error.toString();
  final upper = text.toUpperCase();

  for (final marker in _unrecoverableMarkers) {
    final hit = marker.startsWith('INSTALL') || marker.contains(' ')
        ? upper.contains(marker.toUpperCase())
        : text.contains(marker);
    if (hit) {
      return const InstallFailureKind(
        isUnrecoverable: true,
        needsManualReinstall: true,
        guidance: _reinstallGuidance,
      );
    }
  }

  return const InstallFailureKind(
    isUnrecoverable: false,
    needsManualReinstall: false,
    guidance: _retryGuidance,
  );
}
