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

  /// 当前高亮的 tab 索引，用于在抽屉中标记选中态
  final int currentIndex;

  const AppDrawer({
    super.key,
    this.onSwitchTab,
    this.currentIndex = 0,
  });

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
      _NavTabData(title: '内容', icon: Icons.collections_bookmark_rounded, index: 2),
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
                  color: isActive ? null : AppTokens.primaryBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  tab.icon,
                  size: 16,
                  color: isActive ? Colors.white : AppTokens.primaryBlue.withValues(alpha: 0.70),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  tab.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive ? AppTokens.primaryBlue : AppTokens.textPrimary,
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
                child: Icon(
                  icon,
                  size: 16,
                  color: AppTokens.primaryBlue,
                ),
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
            child: Text(
              'v2.0.0',
              style: TextStyle(
                fontSize: 10,
                color: AppTokens.textSecondary.withValues(alpha: 0.65),
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
