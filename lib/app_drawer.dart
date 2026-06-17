import 'package:flutter/material.dart';

import 'app/app_routes.dart';

import 'design_system/app_tokens.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  static const Color _bgColor = Color(0xFFF3FAFC);
  static const Color _primaryColor = Color(0xFF0B8793);
  static const Color _selectedBgColor = Color(0xFFE2F4F6);

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final drawerWidth = screenWidth >= 720
        ? 380.0
        : (screenWidth * 0.86).clamp(304.0, 380.0).toDouble();

    return Drawer(
      width: drawerWidth,
      backgroundColor: _bgColor,
      surfaceTintColor: Colors.transparent,
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
                          isSelected: true,
                        ),
                        _buildNavItem(
                          context,
                          icon: Icons.handyman_rounded,
                          title: '工具',
                        ),
                        _buildNavItem(
                          context,
                          icon: Icons.collections_bookmark_rounded,
                          title: '内容',
                        ),
                        _buildNavItem(
                          context,
                          icon: Icons.extension_rounded,
                          title: '扩展',
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
                          onTap: () => _openAccount(context),
                        ),
                        _buildNavItem(
                          context,
                          icon: Icons.settings_outlined,
                          title: '设置',
                        ),
                        _buildNavItem(
                          context,
                          icon: Icons.feedback_outlined,
                          title: '反馈',
                        ),
                        _buildNavItem(
                          context,
                          icon: Icons.info_outline_rounded,
                          title: '关于',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
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
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 6),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF5A6570),
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
            color: Color(0xFFF2F5F8),
          ),
        );
      }
    }
    return widgets;
  }

  Widget _buildNavItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: isSelected ? _selectedBgColor : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 0,
          ),
          minLeadingWidth: 24,
          leading: Icon(
            icon,
            size: 20,
            color: isSelected ? _primaryColor : const Color(0xFF596674),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? _primaryColor : const Color(0xFF1F2933),
            ),
          ),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF75808C),
                  ),
                ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: Color(0xFFB2BDC8),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          onTap: onTap,
        ),
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFF7FDFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFE6F5F8),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.verified_user_outlined,
              size: 24,
              color: _primaryColor,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '未登录',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2933),
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  '同步收藏与配置',
                  style: TextStyle(fontSize: 12, color: Color(0xFF75808C)),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _openAccount(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: _primaryColor,
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('登录'),
          ),
        ],
      ),
    );
  }

  void _openAccount(BuildContext context) {
    Navigator.of(context).pop();
    Navigator.of(context).pushNamed(AppRoutes.account);
  }

  Widget _buildFooter() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(18, 6, 18, 22),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF8B98A7)),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'Geek工具箱',
              style: TextStyle(fontSize: 12, color: Color(0xFF8B98A7)),
            ),
          ),
        ],
      ),
    );
  }
}
