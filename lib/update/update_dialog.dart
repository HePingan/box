import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../features/backup/local_backup_service.dart';
import 'app_installer.dart';
import 'pending_update_apk_store.dart';
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
    this.downloaderOverride,
    this.launcherOverride,
    this.pendingStore,
    this.backupOverride,
    this.ignoreStore,
    this.onIgnored,
  });

  /// 下载阶段同样要用到白名单等约束，必须从 bootstrap 一路传进来，
  /// 否则安装器只能用默认空白名单（等于全放通）。
  final UpdateManifestSecurityConfig security;

  /// 仅测试注入：替代「下载 + 安装」整条流程，避免 widget 测试真的去下载。
  final Future<void> Function()? installOverride;

  /// 仅测试注入：只替代**下载**这一步，返回已下载好的包路径。
  /// 用来在用例里走通「后台下载完 → 回到前台才拉安装界面」这条链。
  final Future<String> Function(
    UpdateManifest manifest,
    void Function(double progress) onProgress,
  )?
  downloaderOverride;

  /// 仅测试注入：只替代**拉起系统安装界面**这一步。
  final Future<void> Function(String apkPath)? launcherOverride;

  /// 已下载更新包的记录（默认全局单例；测试可注入内存态）。
  final PendingUpdateApkStore? pendingStore;

  /// 仅测试注入：避免 widget 测试碰真实 Hive/文件系统。
  final Future<String> Function()? backupOverride;

  /// 忽略状态存储，默认用全局单例；测试可注入内存态。
  final UpdateIgnoreStore? ignoreStore;

  /// 用户点「忽略此版本」后回调，便于调用方上报/埋点。
  final void Function(int versionCode)? onIgnored;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

/// 更新流程走到哪一步了。
///
/// 为什么需要状态机：「下载完成」不等于「安装界面已经弹出来」。已经把 App 切到后台的
/// 用户会看到界面停在 100%、按钮变灰、什么也不弹，唯一出路是重新下一遍（2026-09-29
/// 用户报的）。拆出 ready / waitingForeground 之后，界面能说清下一步是什么，也能在回到
/// 前台时自动把安装界面补上。
enum _Stage {
  /// 还没开始（按钮显示「更新」）。
  idle,

  /// 正在下载。
  downloading,

  /// 包已下载校验完成，人在前台：可以立刻安装。
  ready,

  /// 包已下载校验完成，但下载完那一刻**不在前台**：等回到前台再拉安装界面。
  waitingForeground,

  /// 已经交给系统安装器。
  launched,
}

class _UpdateDialogState extends State<UpdateDialog>
    with WidgetsBindingObserver {
  bool _downloading = false;
  double _progress = 0;
  _Stage _stage = _Stage.idle;

  /// 已下载校验完成的包路径（有它才能安装，也才能不重下）。
  String? _readyPath;

  /// 现在是否在前台。Android 10+ 会静默丢掉后台发起的 startActivity，
  /// 所以"看不见了"的时候必须推迟到回到前台再拉安装界面。
  bool _foreground = true;

  /// 「现在能不能拉系统安装界面」。
  ///
  /// 只有明确的**看不见了**（hidden / paused）才推迟：`inactive` 也算前台（App 还在屏幕上，
  /// 只是没焦点，比如下拉了通知栏）；`null` / `detached` 这类拿不准的按前台处理 ——
  /// 宁可试一把，也不能因为状态拿不准就永远不弹安装界面。
  static bool _canStartInstaller(AppLifecycleState? state) {
    return state != AppLifecycleState.hidden &&
        state != AppLifecycleState.paused;
  }

  /// 非 null 表示安装已确定失败且重试无意义，此时必须展示逃生门。
  InstallFailureKind? _blockedFailure;

  PendingUpdateApkStore get _pendingStore =>
      widget.pendingStore ?? PendingUpdateApkStore.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = _canStartInstaller(WidgetsBinding.instance.lifecycleState);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = _canStartInstaller(state);
    // 后台下载完的包，回到前台就把安装界面补上 —— 这正是用户报的那个坑。
    if (_foreground && _stage == _Stage.waitingForeground) {
      _installNow();
    }
  }

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
      _stage = _Stage.downloading;
      _blockedFailure = null;
    });

    try {
      if (widget.installOverride != null) {
        // 测试注入：整条流程都替换掉（既有用例就是这么模拟安装失败的）。
        await widget.installOverride!();
        if (!mounted) return;
        setState(() {
          _downloading = false;
          _progress = 1;
          _stage = _Stage.launched;
        });
        return;
      }

      final path = await _downloadOrReuse();
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _progress = 1;
        _readyPath = path;
        _stage = _Stage.ready;
      });
      await _installNow();
    } catch (e) {
      if (!mounted) return;

      // 关键：区分「再点一次就能好」和「怎么点都装不上」。
      // 强更弹窗关不掉，如果不做这个区分，签名不一致的老用户会被永久锁死。
      final kind = classifyInstallFailure(e);
      setState(() {
        _downloading = false;
        _stage = _Stage.idle;
        _blockedFailure = kind.isUnrecoverable ? kind : null;
      });

      if (!kind.isUnrecoverable) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('更新失败：$e')));
      }
    }
  }

  /// 拿到「可以安装的包」：先认本地是不是已经有一个**同版本、哈希对得上**的包
  /// （上次可能已经下完了，只是没装上），有就直接用 —— 不再让用户重下 27MB。
  Future<String> _downloadOrReuse() async {
    final manifest = widget.manifest;
    final expected = normalizeSha256Hex(manifest.sha256 ?? '');

    final reusable = await _pendingStore.reusablePath(
      versionCode: manifest.latestVersionCode,
      expectedSha256: expected,
    );
    if (reusable != null) {
      if (kDebugMode) debugPrint('复用已下载的更新包: $reusable');
      return reusable;
    }

    final downloader = widget.downloaderOverride;
    final String path;
    if (downloader != null) {
      path = await downloader(manifest, (p) {
        if (!mounted) return;
        setState(() => _progress = p);
      });
    } else {
      final apk = await AppInstaller.downloadApk(
        manifest: manifest,
        security: widget.security,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _progress = p);
        },
      );
      path = apk.path;
    }

    await _pendingStore.save(
      versionCode: manifest.latestVersionCode,
      path: path,
      sha256: expected,
    );
    return path;
  }

  /// 拉系统安装界面。
  ///
  /// **不在前台就先不拉**：Android 10+ 会把后台发起的 startActivity 静默丢掉，
  /// 表现就是"卡在 100%、什么也不弹"。等回到前台由生命周期回调补上。
  ///
  /// [assumeForeground] 只给「用户自己点按钮」这条路径用：能点到按钮就说明人在前台。
  Future<void> _installNow({bool assumeForeground = false}) async {
    final path = _readyPath;
    if (path == null) return;
    // 已经交出去了就别重复拉（生命周期回调可能连着来几次，重复拉会弹两次安装界面）。
    // 但**用户自己点**的时候要允许再来一次：他可能是从安装界面取消了、想再装。
    if (_stage == _Stage.launched && !assumeForeground) return;

    if (!assumeForeground && !_foreground) {
      if (mounted) setState(() => _stage = _Stage.waitingForeground);
      return;
    }

    // 先标记再 await：并发的生命周期回调看到 launched 就不会重复拉。
    if (mounted) setState(() => _stage = _Stage.launched);

    try {
      final launcher = widget.launcherOverride;
      if (launcher != null) {
        await launcher(path);
      } else {
        await AppInstaller.launchInstaller(path);
      }
    } catch (e) {
      if (!mounted) return;

      // 拉不起来：**别**丢掉已经下好的包，用户再点一次「立即安装」就行，
      // 不用重新下载。
      final kind = classifyInstallFailure(e);
      setState(() {
        _stage = _Stage.ready;
        _blockedFailure = kind.isUnrecoverable ? kind : null;
      });
      if (!kind.isUnrecoverable) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('拉起安装失败：$e')));
      }
    }
  }

  /// 按钮文字：下载中带百分比；已经下好了就说「立即安装」——
  /// 别让用户以为还得再下一次（他自己也分不清"已下载"和"没下载"）。
  String get _actionLabel {
    if (_downloading) {
      return '下载中 ${(100 * _progress).clamp(0, 100).toStringAsFixed(0)}%';
    }
    if (_readyPath != null) return '立即安装';
    return '更新';
  }

  /// 按钮动作：包已经在手上就直接装，否则走下载。
  void _onActionPressed() {
    if (_readyPath != null) {
      // 用户能点到按钮 ⇒ 人就在前台看这个界面，生命周期状态可能还没跟上
      // （有些 ROM 会漏发回调），不能因为这个就不装。
      _installNow(assumeForeground: true);
      return;
    }
    _doUpdate();
  }

  /// 当前阶段的人话说明。尤其要交代「后台下载完了、安装界面还没弹」这种情况，
  /// 否则用户看到的就是一个停在 100% 却点不动的按钮。
  String? get _stageHint {
    switch (_stage) {
      case _Stage.waitingForeground:
        return '更新包已下载完成。回到 App 会自动弹出安装界面；'
            '没弹出来就点上面的「立即安装」。';
      case _Stage.launched:
        return '已交给系统安装器。装完打开 App 就是新版本。';
      case _Stage.ready:
        return '更新包已下载完成，点「立即安装」继续。';
      case _Stage.idle:
      case _Stage.downloading:
        return null;
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
                                    onPressed: _downloading
                                        ? null
                                        : _onActionPressed,
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
                                      _actionLabel,
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
                              if (_stageHint != null) ...[
                                const SizedBox(height: 10),
                                Text(
                                  _stageHint!,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.5,
                                    color: Color(0xFF666666),
                                  ),
                                ),
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
