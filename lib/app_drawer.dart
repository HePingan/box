import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app/app_routes.dart';
import 'design_system/app_tokens.dart';
import 'features/account/data/account_store.dart';
import 'features/account/domain/account_models.dart';

/// 应用侧滑菜单 — 风格与主页面完全一致
class AppDrawer extends StatefulWidget {
  /// 导航项选中回调（首页/工具/内容/扩展 → tab index）
  final ValueChanged<int>? onSwitchTab;

  const AppDrawer({super.key, this.onSwitchTab});

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

  const _DrawerContent({
    required this.session,
    required this.onSwitchTab,
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
                    _buildSectionCard(
                      title: '导航',
                      children: [
                        _buildNavItem(
                          context,
                          icon: Icons.home_rounded,
                          title: '首页',
                          subtitle: null,
                          trailing: null,
                          onTap: () => _switchTab(context, 0),
                        ),
                        _buildNavItem(
                          context,
                          icon: Icons.handyman_rounded,
                          title: '工具',
                          onTap: () => _switchTab(context, 1),
                        ),
                        _buildNavItem(
                          context,
                          icon: Icons.collections_bookmark_rounded,
                          title: '内容',
                          onTap: () => _switchTab(context, 2),
                        ),
                        _buildNavItem(
                          context,
                          icon: Icons.extension_rounded,
                          title: '扩展',
                          onTap: () => _switchTab(context, 3),
                        ),
                      ],
                    ),
                    _buildSectionCard(
                      title: '更多',
                      children: [
                        _buildNavItem(
                          context,
                          icon: Icons.account_circle_rounded,
                          title: '账号中心',
                          subtitle: '登录 Box 后端与管理员后台',
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: AppTokens.textTertiary,
                          ),
                          onTap: () => _openRoute(context, AppRoutes.account),
                        ),
                        _buildNavItem(
                          context,
                          icon: Icons.settings_outlined,
                          title: '设置',
                          subtitle: '个性化配置与偏好',
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: AppTokens.textTertiary,
                          ),
                          onTap: () => _openRoute(context, AppRoutes.account),
                        ),
                        _buildNavItem(
                          context,
                          icon: Icons.feedback_outlined,
                          title: '反馈',
                          subtitle: '问题报告与功能建议',
                          trailing: const Icon(
                            Icons.open_in_new_rounded,
                            size: 18,
                            color: AppTokens.textTertiary,
                          ),
                          onTap: () => _openFeedback(context),
                        ),
                        _buildNavItem(
                          context,
                          icon: Icons.info_outline_rounded,
                          title: '关于',
                          subtitle: '版本与开发者信息',
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: AppTokens.textTertiary,
                          ),
                          onTap: () => _showAboutDialog(context),
                        ),
                      ],
                    ),
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
    Navigator.of(context).pop(); // 先关抽屉
    onSwitchTab?.call(index);
  }

  // ─── 路由跳转 ───

  void _openRoute(BuildContext context, String route) {
    Navigator.of(context).pop(); // 关抽屉
    Navigator.of(context).pushNamed(route);
  }

  // ─── 反馈 ───

  void _openFeedback(BuildContext context) {
    const url = 'https://github.com/HePingan/box/issues';
    Navigator.of(context).pop(); // 关抽屉
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

  Future<void> _showAboutDialog(BuildContext context) async {
    Navigator.of(context).pop(); // 关抽屉

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
              style: TextStyle(
                fontSize: 13,
                color: AppTokens.textSecondary,
              ),
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
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                decoration: BoxDecoration(
                  color: AppTokens.surfaceMuted,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.code_rounded, size: 16, color: AppTokens.textSecondary),
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
                    Icon(Icons.open_in_new, size: 14, color: AppTokens.primaryBlue),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
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

  // ─── 分组卡片 ───

  Widget _buildSectionCard({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        border: Border.all(color: AppTokens.divider),
        boxShadow: [
          BoxShadow(
            color: AppTokens.ink.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 4),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppTokens.textTertiary,
                letterSpacing: 0.6,
              ),
            ),
          ),
          ..._withDividers(children),
          const SizedBox(height: 4),
        ],
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

  // ─── 导航项 ───

  Widget _buildNavItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: 6,
            vertical: subtitle != null ? 8 : 4,
          ),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: onTap != null ? AppTokens.blueGradient : null,
                  color: onTap != null ? null : AppTokens.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: onTap != null ? Colors.white : AppTokens.textSecondary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: onTap != null ? FontWeight.w600 : FontWeight.w500,
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
            ],
          ),
        ),
      ),
    );
  }

  // ─── 头部卡片 ───

  Widget _buildHeaderCard(BuildContext context) {
    final user = session?.user;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
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
                : const Icon(Icons.person_rounded, size: 24, color: Colors.white),
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
          TextButton(
            onPressed: () => _openRoute(context, AppRoutes.account),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.transparent,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusXs),
              ),
            ).copyWith(
              backgroundColor: WidgetStateProperty.resolveWith((_) => null),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                gradient: AppTokens.blueGradient,
                borderRadius: BorderRadius.circular(AppTokens.radiusXs),
              ),
              child: Text(user != null ? '账号' : '登录'),
            ),
          ),
        ],
      ),
    );
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
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              gradient: AppTokens.blueGradient,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Center(
              child: Text(
                'G',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Geek工具箱 Pro',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTokens.textTertiary,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => _openRoute(context, AppRoutes.debugLog),
            child: const Text(
              'v2.0.0',
              style: TextStyle(
                fontSize: 11,
                color: AppTokens.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
