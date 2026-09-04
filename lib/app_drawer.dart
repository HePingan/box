import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'app/app_routes.dart';
import 'config/app_config.dart';
import 'design_system/app_tokens.dart';
import 'update/update_dialog.dart';
import 'update/update_service.dart';
import 'features/account/data/account_store.dart';
import 'features/cloud_sync/domain/announcement_center.dart';
import 'features/account/domain/account_models.dart';
import 'features/backup/local_backup_service.dart';

/// 应用侧滑菜单 — 风格与主页面完全一致
class AppDrawer extends StatefulWidget {
  /// 导航项选中回调（首页/工具/内容/扩展 → tab index）
  final ValueChanged<int>? onSwitchTab;

  /// 当前高亮的 tab 索引，用于在抽屉中标记选中态
  final int currentIndex;

  const AppDrawer({super.key, this.onSwitchTab, this.currentIndex = 0});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      // 兜底：若 main.dart 中的异步加载慢于 drawer 构建，在此补读
      if (globalSessionNotifier.value == null) {
        BoxAccountStore().loadSession().then((session) {
          if (session != null) globalSessionNotifier.value = session;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final drawerWidth = screenWidth >= 720
        ? 380.0
        : (screenWidth * 0.86).clamp(304.0, 380.0).toDouble();

    return Drawer(
      width: drawerWidth,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      child: ListenableBuilder(
        listenable: globalSessionNotifier,
        builder: (context, _) {
          return _DrawerContent(
            session: globalSessionNotifier.value,
            onSwitchTab: widget.onSwitchTab,
            currentIndex: widget.currentIndex,
          );
        },
      ),
    );
  }
}

/// 抽屉实际内容（响应 session 变化）
class _DrawerContent extends StatelessWidget {
  final BoxAccountSession? session;
  final ValueChanged<int>? onSwitchTab;
  final int currentIndex;

  const _DrawerContent({
    required this.session,
    required this.onSwitchTab,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.98),
        boxShadow: [
          BoxShadow(
            color: AppTokens.ink.withValues(alpha: 0.08),
            blurRadius: 32,
            offset: const Offset(4, 0),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  24 + MediaQuery.paddingOf(context).bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeaderCard(context),
                    const SizedBox(height: 12),
                    _buildNavSection(context),
                    const SizedBox(height: 12),
                    _buildMoreSection(context),
                  ],
                ),
              ),
            ),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  // ─── Tab 切换 ───

  void _switchTab(BuildContext context, int index) {
    Navigator.of(context).pop();
    onSwitchTab?.call(index);
  }

  // ─── 路由跳转 ───

  void _openRoute(BuildContext context, String route) {
    Navigator.of(context).pop();
    Navigator.of(context).pushNamed(route);
  }

  // ─── 反馈 ───

  void _openFeedback(BuildContext context) {
    const url = 'https://github.com/HePingan/box/issues';
    Navigator.of(context).pop();
    Clipboard.setData(const ClipboardData(text: url));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        ),
        title: const Text('提交反馈'),
        content: const Text(
          'Issue 地址已复制到剪贴板。\n\n打开 GitHub 提交 Issue 即可反馈问题或建议。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _showSnack(context, '已复制 Issue 地址到剪贴板，请粘贴到浏览器打开');
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppTokens.primaryBlue,
            ),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  // ─── 关于对话框 ───

  Future<void> _backupLocalData(BuildContext context) async {
    Navigator.of(context).pop();
    _showSnack(context, '正在整理本地数据…');
    try {
      final file = await LocalBackupService.writeBackupToTemporaryFile();
      // 导出后当场回读自检。只报总条数看不出「某一类整体缺失」，
      // 分类计数能让用户在卸载重装**之前**发现备份不全。
      String summaryText;
      try {
        final summary = LocalBackupService.summarize(
          await file.readAsString(),
        );
        summaryText = summary.describe();
      } catch (_) {
        summaryText = '（自检未通过，请确认备份文件是否完整）';
      }
      if (!context.mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: 'Box 本地数据备份',
          text: '本次备份内容：$summaryText\n请妥善保存此备份文件；重装后可通过“恢复本地数据”导入。',
        ),
      );
      if (context.mounted) _showSnack(context, '备份内容：$summaryText');
    } catch (_) {
      if (context.mounted) _showSnack(context, '备份失败，请稍后重试');
    }
  }

  Future<void> _restoreLocalData(BuildContext context) async {
    Navigator.of(context).pop();
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      final file = picked?.files.single;
      final bytes = await file?.readAsBytes();
      if (bytes == null || bytes.isEmpty || !context.mounted) return;
      final count = await LocalBackupService.restoreBackupBytes(bytes);
      if (context.mounted) {
        // 仍然建议重启：内存缓存已失效，但已经建好的页面（列表、
        // 阅读器）不会自己重建，用户看到的可能还是旧画面。
        _showSnack(context, '已恢复 $count 条本地记录，建议重启应用以刷新界面');
      }
    } on FormatException {
      if (context.mounted) _showSnack(context, '不是有效的 Box 本地数据备份文件');
    } catch (_) {
      if (context.mounted) _showSnack(context, '恢复失败，原数据未被清空');
    }
  }

  Future<void> _showAboutDialog(BuildContext context) async {
    Navigator.of(context).pop();

    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        ),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: AppTokens.blueGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text(
                  'G',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text('Geek工具箱 Pro'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _aboutRow('版本', info.version),
            const SizedBox(height: 6),
            _aboutRow('构建', info.buildNumber),
            const SizedBox(height: 6),
            _aboutRow('平台', info.packageName),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppTokens.divider),
            const SizedBox(height: 12),
            const Text(
              '智能工具集，为极客而生。',
              style: TextStyle(fontSize: 13, color: AppTokens.textSecondary),
            ),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                const url = 'https://github.com/HePingan/box';
                Clipboard.setData(const ClipboardData(text: url));
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('仓库地址已复制到剪贴板'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 10,
                ),
                decoration: BoxDecoration(
                  color: AppTokens.surfaceMuted,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.code_rounded,
                      size: 16,
                      color: AppTokens.textSecondary,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'github.com/HePingan/box',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTokens.primaryBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.open_in_new,
                      size: 14,
                      color: AppTokens.primaryBlue,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            // 必须用关于框自己的 ctx：抽屉的 context 在本方法第一行就被 pop
            // 掉了，用它取 ScaffoldMessenger 再判 mounted 会静默返回，
            // 表现就是「点检查更新没反应」。
            onPressed: () => _checkUpdateManually(ctx, info),
            child: const Text('检查更新'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 手动检查更新（A4）。
  ///
  /// 原先只有启动时那一次静默检查，用户既没有主动入口，出问题也看不到原因
  /// （service 里是 catch(_)，加上 allowProceedOnCheckFailure 默认 true）。
  /// 这里用 checkUpdateDiagnostic，如实把失败原因显示出来。
  ///
  /// 刻意不查 UpdateIgnoreStore：用户主动点「检查更新」时必须看到结果，
  /// 哪怕这个版本之前被忽略过。否则点了没反应会被当成功能坏了。
  /// 这也是忽略之后唯一的找回入口。
  Future<void> _checkUpdateManually(
    BuildContext context,
    PackageInfo info,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    messenger.showSnackBar(
      const SnackBar(
        content: Text('正在检查更新…'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );

    final outcome = await UpdateService.instance.checkUpdateDiagnostic(
      checkUrl: AppConfig.updateCheckUrl,
      appId: AppConfig.appId,
      platform: AppConfig.updatePlatform,
      channel: AppConfig.appChannel,
      versionCode: int.tryParse(info.buildNumber) ?? 0,
      packageName: info.packageName,
      security: AppConfig.updateSecurityConfig,
    );

    // 这里刻意不判 context.mounted：messenger / navigator 已在 await 之前
    // 抓好，它们的生命周期挂在 App 上而不是这个弹窗上。之前判 mounted 的写法
    // 会在弹窗被关掉后把结果整个丢掉，用户只看到「没反应」。

    final manifest = outcome.manifest;
    if (outcome.hasUpdate && manifest != null) {
      navigator.pop();
      // 判 navigator 而不是判弹窗 context：navigator 活得和 App 一样久，
      // 弹窗 context 刚被上一行 pop 掉，判它必然提前 return。
      if (!navigator.mounted) return;
      await showDialog(
        context: navigator.context,
        builder: (_) => UpdateDialog(
          manifest: manifest,
          currentVersionName: info.version,
          currentVersionCode: int.tryParse(info.buildNumber) ?? 0,
          force: manifest.needForceUpdate(int.tryParse(info.buildNumber) ?? 0),
          security: AppConfig.updateSecurityConfig,
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

  Widget _aboutRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppTokens.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTokens.textPrimary,
          ),
        ),
      ],
    );
  }

  // ─── 头部卡片（合并账号入口，去除"账号"按钮） ───

  Widget _buildHeaderCard(BuildContext context) {
    final user = session?.user;

    return InkWell(
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      onTap: () => _openRoute(context, AppRoutes.account),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFEEF2FF), Color(0xFFF0FDFA)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          border: Border.all(color: const Color(0xFFE0E7FF)),
          boxShadow: [
            BoxShadow(
              color: AppTokens.primaryBlue.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: AppTokens.blueGradient,
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              ),
              child: user != null
                  ? Center(
                      child: Text(
                        user.username.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                    )
                  : const Icon(
                      Icons.person_rounded,
                      size: 24,
                      color: Colors.white,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user?.username ?? '未登录',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user != null ? '已登录 · ${user.role}' : '同步收藏与配置',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppTokens.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  // ─── 导航区（紧凑、有选中态） ───

  Widget _buildNavSection(BuildContext context) {
    const tabs = [
      _NavTabData(title: '首页', icon: Icons.home_rounded, index: 0),
      _NavTabData(title: '工具', icon: Icons.handyman_rounded, index: 1),
      _NavTabData(
        title: '内容',
        icon: Icons.collections_bookmark_rounded,
        index: 2,
      ),
      _NavTabData(title: '扩展', icon: Icons.extension_rounded, index: 3),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 6, top: 2),
          child: Text(
            '导航',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTokens.textSecondary, // ≥4.5:1
              letterSpacing: 0.4,
            ),
          ),
        ),
        ...tabs.map((tab) => _buildNavRow(context, tab)),
      ],
    );
  }

  Widget _buildNavRow(BuildContext context, _NavTabData tab) {
    final isActive = tab.index == currentIndex;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusXs),
        onTap: () => _switchTab(context, tab.index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isActive
                ? AppTokens.primaryBlue.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTokens.radiusXs),
          ),
          child: Row(
            children: [
              // 图标：28dp，选中时渐变
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  gradient: isActive ? AppTokens.blueGradient : null,
                  color: isActive
                      ? null
                      : AppTokens.primaryBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  tab.icon,
                  size: 16,
                  color: isActive
                      ? Colors.white
                      : AppTokens.primaryBlue.withValues(alpha: 0.70),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  tab.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive
                        ? AppTokens.primaryBlue
                        : AppTokens.textPrimary,
                  ),
                ),
              ),
              // 右侧指示条（仅活跃时显示）
              if (isActive) ...[
                const SizedBox(width: 4),
                Container(
                  width: 3,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppTokens.primaryBlue,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─── 更多区（紧凑、统一箭头样式） ───

  Widget _buildMoreSection(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        border: Border.all(color: AppTokens.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 10, 14, 2),
            child: Text(
              '更多',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTokens.textSecondary, // ≥4.5:1
                letterSpacing: 0.4,
              ),
            ),
          ),
          ..._withDividers([
            // 公告放在最前并带未读红点：原先埋在个人中心里，出故障时用户
            // 根本找不到，等于没有触达手段。
            Consumer<AnnouncementCenter>(
              builder: (context, center, _) {
                final unread = center.unreadCount;
                return _buildMoreItem(
                  context,
                  icon: Icons.campaign_outlined,
                  title: '公告',
                  subtitle: unread > 0 ? '$unread 条未读' : null,
                  trailing: unread > 0
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTokens.danger,
                            borderRadius: BorderRadius.circular(
                              AppTokens.radiusPill,
                            ),
                          ),
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        )
                      : null,
                  onTap: () =>
                      _openRoute(context, AppRoutes.announcements),
                );
              },
            ),
            _buildMoreItem(
              context,
              icon: Icons.account_circle_rounded,
              title: '账号中心',
              subtitle: null,
              onTap: () => _openRoute(context, AppRoutes.account),
            ),
            _buildMoreItem(
              context,
              icon: Icons.settings_outlined,
              title: '设置',
              subtitle: null,
              onTap: () => _openRoute(context, AppRoutes.account),
            ),
            _buildMoreItem(
              context,
              icon: Icons.feedback_outlined,
              title: '反馈',
              subtitle: '问题报告与功能建议',
              trailing: const Icon(
                Icons.open_in_new_rounded,
                size: 16,
                color: AppTokens.textSecondary,
              ),
              onTap: () => _openFeedback(context),
            ),
            _buildMoreItem(
              context,
              icon: Icons.backup_outlined,
              title: '备份本地数据',
              subtitle: '收藏、历史、下载、书架书源与阅读进度、本地题库',
              onTap: () => _backupLocalData(context),
            ),
            _buildMoreItem(
              context,
              icon: Icons.settings_backup_restore_outlined,
              title: '恢复本地数据',
              subtitle: '重装后导入此前导出的备份',
              onTap: () => _restoreLocalData(context),
            ),
            _buildMoreItem(
              context,
              icon: Icons.bug_report_outlined,
              title: '调试日志',
              subtitle: '出问题时复制这里的日志发给开发者',
              onTap: () => _openRoute(context, AppRoutes.debugLog),
            ),
            _buildMoreItem(
              context,
              icon: Icons.info_outline_rounded,
              title: '关于',
              subtitle: null,
              onTap: () => _showAboutDialog(context),
            ),
          ]),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildMoreItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusXs),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTokens.primaryBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: AppTokens.primaryBlue),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTokens.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTokens.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ?trailing,
              if (trailing == null)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppTokens.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _withDividers(List<Widget> children) {
    final widgets = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      widgets.add(children[i]);
      if (i != children.length - 1) {
        widgets.add(
          const Divider(
            height: 1,
            indent: 52,
            endIndent: 14,
            color: AppTokens.divider,
          ),
        );
      }
    }
    return widgets;
  }

  // ─── 底部 ───

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTokens.divider)),
      ),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              gradient: AppTokens.blueGradient,
              borderRadius: BorderRadius.circular(5),
            ),
            child: const Center(
              child: Text(
                'G',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'Geek工具箱 Pro',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTokens.textSecondary, // ≥4.5:1
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => _openRoute(context, AppRoutes.debugLog),
            child: const _FooterVersionLabel(),
          ),
        ],
      ),
    );
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

/// 抽屉底部的版本号。
///
/// 之前这里硬编码 `v2.0.0`，而 `pubspec.yaml` 早已走到 1.9.x —— 用户想确认
/// 「线上版本装上了没有」时，唯一顺手能看的这个数字反而在说谎。改成读
/// [PackageInfo]，与「关于」弹窗同源。
class _FooterVersionLabel extends StatefulWidget {
  const _FooterVersionLabel();

  @override
  State<_FooterVersionLabel> createState() => _FooterVersionLabelState();
}

class _FooterVersionLabelState extends State<_FooterVersionLabel> {
  String? _label;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _label = 'v${info.version}+${info.buildNumber}');
    } catch (_) {
      // 取不到就保持占位，不能因为拿不到版本号把整个抽屉底栏搞崩。
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _label ?? 'v—',
      style: TextStyle(
        fontSize: 10,
        color: AppTokens.textSecondary.withValues(alpha: 0.65),
      ),
    );
  }
}

/// 导航项数据模型
class _NavTabData {
  final String title;
  final IconData icon;
  final int index;

  const _NavTabData({
    required this.title,
    required this.icon,
    required this.index,
  });
}
