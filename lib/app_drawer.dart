import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'app/app_routes.dart';
import 'config/app_config.dart';
import 'design_system/app_tokens.dart';
import 'update/update_dialog.dart';
import 'update/update_service.dart';
import 'features/account/data/account_store.dart';
import 'features/cloud_sync/domain/announcement_center.dart';
import 'features/account/domain/account_models.dart';

/// 应用侧滑菜单 — 风格与主页面完全一致
///
/// 这里**刻意没有** tab 导航区。`app_shell.dart` 的 bottomNavigationBar 已
/// 常驻首页/工具/内容/扩展 四项，数据源是同一个 `_tabs`；抽屉里再列一份是
/// 纯复制品，还更难用（底栏一次点击到位，抽屉要先划开再点），且白占约
/// 150dp 高度，把只能从抽屉进的功能挤到需要滚动才看得到。
class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

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
          return _DrawerContent(session: globalSessionNotifier.value);
        },
      ),
    );
  }
}

/// 抽屉实际内容（响应 session 变化）
class _DrawerContent extends StatelessWidget {
  final BoxAccountSession? session;

  const _DrawerContent({required this.session});

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

  // ─── 路由跳转 ───

  /// 打开二级页，但**不关抽屉**。
  ///
  /// 原先是先 `pop()` 关抽屉再 push 目标页，结果用户从目标页返回时抽屉早已
  /// 不在，得重新划开才能点下一项 —— 抽屉本来就是「连着点几下」的地方。
  /// 现在让目标页直接盖在抽屉之上，返回时抽屉还在原位。
  void _openRoute(BuildContext context, String route) {
    Navigator.of(context).pushNamed(route);
  }

  // ─── 反馈 ───

  /// 反馈弹框，同上：不关抽屉。
  void _openFeedback(BuildContext context) {
    const url = 'https://github.com/HePingan/box/issues';
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

  /// 弹「关于」框，同样不关抽屉：关掉框之后用户还站在抽屉里。
  ///
  /// 顺带消掉一个隐患 —— 原先先 pop 抽屉再 await，之后拿这个已经出栈的
  /// context 去 showDialog / showSnackBar，「检查更新」就曾因此静默失效
  /// （见 test/update/manual_check_snackbar_test.dart）。不 pop 之后
  /// context 全程有效。
  Future<void> _showAboutDialog(BuildContext context) async {
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
            // 用关于框自己的 ctx，并把「关掉宿主」交给 closeHost：
            // 有新版本时先收掉关于框再弹更新框，否则两层弹窗叠在一起。
            onPressed: () => _checkUpdateManually(
              ctx,
              info,
              closeHost: () => Navigator.of(ctx).pop(),
            ),
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
  /// [closeHost] 关掉承载这个动作的宿主。从「关于」框调用时传 pop 关掉框；
  /// 从抽屉列表直接调用时传 null —— 抽屉不是路由，pop 一下会把身下的主页面
  /// 顶掉。所以宿主关闭行为必须由调用方决定，不能在这里写死 pop。
  Future<void> _checkUpdateManually(
    BuildContext context,
    PackageInfo info, {
    VoidCallback? closeHost,
  }) async {
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
      closeHost?.call();
      // 判 navigator 而不是判弹窗 context：navigator 活得和 App 一样久，
      // 弹窗 context 可能刚被 closeHost 关掉，判它必然提前 return。
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

  /// 抽屉列表里的「检查更新」。
  ///
  /// 不传 closeHost：抽屉不是路由，没有需要收掉的宿主弹窗，
  /// pop 一下会把身下的主页面顶掉。
  Future<void> _checkUpdateFromDrawer(BuildContext context) async {
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    await _checkUpdateManually(context, info);
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
            // 公告未读红点提到常驻可见的头部卡片上。原先只挂在「更多」
            // 列表里，抽屉一划开如果不滚动可能看不到——而公告恰恰是线上
            // 出故障时唯一的触达手段。
            Consumer<AnnouncementCenter>(
              builder: (context, center, _) {
                final unread = center.unreadCount;
                if (unread == 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Container(
                    key: const Key('drawer_header_unread_badge'),
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
                  ),
                );
              },
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
          _buildSectionLabel('常用'),
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
              icon: Icons.settings_outlined,
              title: '设置',
              subtitle: null,
              // 改之前这里跳 AppRoutes.account，与上面「账号中心」撞同一个页面。
              onTap: () => _openRoute(context, AppRoutes.settings),
            ),
          ]),
          _buildSectionLabel('数据'),
          ..._withDividers([
            // 备份与恢复是成对使用的功能，合成一个入口进「数据设置」，
            // 抽屉不再平铺两条。具体实现搬到 DataSettingsPage。
            _buildMoreItem(
              context,
              icon: Icons.backup_outlined,
              title: '备份与恢复',
              subtitle: '导出或导入收藏、书架、阅读进度、本地题库',
              onTap: () => _openRoute(context, AppRoutes.dataSettings),
            ),
          ]),
          _buildSectionLabel('帮助'),
          ..._withDividers([
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
              icon: Icons.bug_report_outlined,
              title: '调试日志',
              subtitle: '出问题时复制这里的日志发给开发者',
              onTap: () => _openRoute(context, AppRoutes.debugLog),
            ),
            // 提到列表：原先只在「关于」框的按钮里，用户得先点关于才找得到。
            // 忽略过某个版本之后，这里也是唯一的找回入口。
            _buildMoreItem(
              context,
              icon: Icons.system_update_outlined,
              title: '检查更新',
              subtitle: '看看有没有新版本',
              onTap: () => _checkUpdateFromDrawer(context),
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

  /// 分组小标题。改之前「更多」是一个 8 项的无分隔长列表，常用项和
  /// 出故障才找的项混在一起。
  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppTokens.textSecondary, // ≥4.5:1
          letterSpacing: 0.4,
        ),
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
          // 这里原来挂着「点版本号进调试日志」的隐藏手势。「更多 → 帮助」
          // 已有正式入口，隐藏路径留着只是多一条没人知道的路。
          const _FooterVersionLabel(),
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


