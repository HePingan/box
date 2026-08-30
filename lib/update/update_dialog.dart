import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../features/backup/local_backup_service.dart';
import 'app_installer.dart';
import 'update_install_failure.dart';
import 'update_ignore_store.dart';
import 'update_models.dart';
import 'update_security.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateManifest manifest;
  final String currentVersionName;
  final int currentVersionCode;
  final bool force;

  const UpdateDialog({
    super.key,
    required this.manifest,
    required this.currentVersionName,
    required this.currentVersionCode,
    required this.force,
    this.security = const UpdateManifestSecurityConfig(),
    this.installOverride,
    this.backupOverride,
    this.ignoreStore,
    this.onIgnored,
  });

  /// 下载阶段同样要用到白名单等约束，必须从 bootstrap 一路传进来，
  /// 否则安装器只能用默认空白名单（等于全放通）。
  final UpdateManifestSecurityConfig security;

  /// 仅测试注入：模拟安装失败，避免 widget 测试真的去下载。
  final Future<void> Function()? installOverride;

  /// 仅测试注入：避免 widget 测试碰真实 Hive/文件系统。
  final Future<String> Function()? backupOverride;

  /// 忽略状态存储，默认用全局单例；测试可注入内存态。
  final UpdateIgnoreStore? ignoreStore;

  /// 用户点「忽略此版本」后回调，便于调用方上报/埋点。
  final void Function(int versionCode)? onIgnored;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;

  /// 非 null 表示安装已确定失败且重试无意义，此时必须展示逃生门。
  InstallFailureKind? _blockedFailure;
  // 优先显示后台填的 title，如果没有填 title，再退而求其次显示日期
  String _titleText() {
    final title = widget.manifest.title;
    if (title != null && title.isNotEmpty) {
      return title;
    }
    final s = widget.manifest.publishedAt;
    if (s == null || s.isEmpty) return '发现新版本';
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  Future<void> _doUpdate() async {
    setState(() {
      _downloading = true;
      _progress = 0;
    });

    try {
      if (widget.installOverride != null) {
        await widget.installOverride!();
      } else {
        await AppInstaller.downloadAndInstall(
          manifest: widget.manifest,
          security: widget.security,
          onProgress: (p) {
            if (!mounted) return;
            setState(() => _progress = p);
          },
        );
      }
    } catch (e) {
      if (!mounted) return;

      // 关键：区分「再点一次就能好」和「怎么点都装不上」。
      // 强更弹窗关不掉，如果不做这个区分，签名不一致的老用户会被永久锁死。
      final kind = classifyInstallFailure(e);
      setState(() {
        _downloading = false;
        _blockedFailure = kind.isUnrecoverable ? kind : null;
      });

      if (!kind.isUnrecoverable) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('更新失败：$e')));
      }
    }
  }

  Future<void> _exportBackup() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (widget.backupOverride != null) {
        await widget.backupOverride!();
      } else {
        final file = await LocalBackupService.writeBackupToTemporaryFile();
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'application/json')],
            subject: 'Box 本地数据备份',
            text: '请妥善保存此备份文件；重装后可通过“恢复本地数据”导入。',
          ),
        );
      }
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('备份已导出，请保存到安全位置后再卸载')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('导出备份失败：$e')));
    }
  }

  Future<void> _ignoreThisVersion() async {
    final code = widget.manifest.latestVersionCode;
    final store = widget.ignoreStore ?? UpdateIgnoreStore.instance;
    await store.ignoreVersion(code);
    widget.onIgnored?.call(code);
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  Future<void> _copyDownloadUrl() async {
    final url = widget.manifest.downloadUrl;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('下载链接已复制，可用浏览器打开安装')));
  }

  @override
  Widget build(BuildContext context) {
    final manifest = widget.manifest;

    // 一旦确认装不上，强更就必须让路：否则用户被锁在关不掉的弹窗里，App 报废。
    final blocked = _blockedFailure;
    final lockNavigation = widget.force && blocked == null;

    return PopScope(
      canPop: !lockNavigation,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.86,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Container(
              color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.only(top: 28, bottom: 18),
                    color: const Color(0xFF66B7E8),
                    child: const Center(child: _InfoIcon()),
                  ),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Center(
                                  child: Text(
                                    _titleText(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF222222),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  '最新版本为：${manifest.latestVersionName} (${manifest.latestVersionCode})',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Color(0xFF333333),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '已安装版本：${widget.currentVersionName} (${widget.currentVersionCode})',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Color(0xFF333333),
                                  ),
                                ),
                                if (manifest.notice != null &&
                                    manifest.notice!.isNotEmpty) ...[
                                  const SizedBox(height: 14),
                                  Text(
                                    manifest.notice!,
                                    maxLines: 8,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF666666),
                                    ),
                                  ),
                                ],
                                if (manifest.changelog.isNotEmpty) ...[
                                  const SizedBox(height: 14),
                                  const Text(
                                    '更新内容：',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF333333),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  ...manifest.changelog.map(
                                    (item) => Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        '• $item',
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF666666),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                if (blocked != null) ...[
                                  const SizedBox(height: 14),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF4E5),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      blocked.guidance,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        height: 1.5,
                                        color: Color(0xFF8A5A00),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 18),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (blocked == null)
                                SizedBox(
                                  height: 48,
                                  child: OutlinedButton(
                                    onPressed: _downloading ? null : _doUpdate,
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                        color: Color(0xFF6FB7E8),
                                        width: 1.5,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    child: Text(
                                      _downloading
                                          ? '下载中 ${(100 * _progress).clamp(0, 100).toStringAsFixed(0)}%'
                                          : '更新',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        color: Color(0xFF5FADE0),
                                      ),
                                    ),
                                  ),
                                ),
                              if (_downloading) ...[
                                const SizedBox(height: 12),
                                LinearProgressIndicator(value: _progress),
                              ],
                              // 「忽略此版本」：只在非强更、且安装未确定失败时给。
                              // 强更不能被忽略；装不上时下面已有逃生门，不再叠加。
                              if (blocked == null && !widget.force) ...[
                                const SizedBox(height: 10),
                                SizedBox(
                                  height: 44,
                                  child: TextButton(
                                    onPressed: _downloading
                                        ? null
                                        : _ignoreThisVersion,
                                    child: const Text(
                                      '忽略此版本',
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: Color(0xFF888888),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              // 逃生门：装不上时给「先备份」→「手动下载」→「退出」三条路。
                              if (blocked != null) ...[
                                SizedBox(
                                  height: 48,
                                  child: FilledButton(
                                    onPressed: _exportBackup,
                                    child: const Text('导出备份'),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  height: 44,
                                  child: OutlinedButton(
                                    onPressed: _copyDownloadUrl,
                                    child: const Text('复制下载链接'),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  height: 44,
                                  child: TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).maybePop(),
                                    child: const Text('退出应用'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoIcon extends StatelessWidget {
  const _InfoIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 78,
      height: 78,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 4),
      ),
      child: const Center(
        child: Icon(Icons.info_outline, size: 36, color: Colors.white),
      ),
    );
  }
}
