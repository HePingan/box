import 'package:flutter/material.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  static const Color _bgColor = Color(0xFFF3FAFC);
  static const Color _primaryColor = Color(0xFF0B8793);
  static const Color _selectedBgColor = Color(0xFFE2F4F6);

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: _bgColor,
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeaderCard(),
                    const SizedBox(height: 14),

                    _buildSectionCard(
                      title: '主页',
                      children: [
                        _buildNavItem(
                          icon: Icons.home_rounded,
                          title: '软件首页',
                          isSelected: true,
                        ),
                        _buildNavItem(
                          icon: Icons.grid_view_rounded,
                          title: '全部工具',
                        ),
                        _buildNavItem(
                          icon: Icons.inventory_2_outlined,
                          title: '仓库合集',
                        ),
                        _buildNavItem(
                          icon: Icons.palette_outlined,
                          title: '主题颜色',
                        ),
                      ],
                    ),

                    _buildSectionCard(
                      title: '更多',
                      children: [
                        _buildNavItem(
                          icon: Icons.update_rounded,
                          title: '更新日志',
                        ),
                        _buildNavItem(
                          icon: Icons.share_outlined,
                          title: '分享软件',
                        ),
                        _buildNavItem(
                          icon: Icons.help_outline_rounded,
                          title: '关于软件',
                        ),
                      ],
                    ),

                    _buildSectionCard(
                      title: '支持',
                      children: [
                        _buildInfoItem(
                          icon: Icons.sim_card_outlined,
                          title: 'Geek工具箱仅供娱乐',
                          subtitle: '我的天，开发者真帅😏',
                        ),
                        _buildInfoItem(
                          icon: Icons.savings_outlined,
                          title: '捐赠支持',
                          subtitle: '全部用于Geek工具箱开发与维护。',
                        ),
                      ],
                    ),

                    _buildSectionCard(
                      title: '政策',
                      children: [
                        _buildInfoItem(
                          icon: Icons.copyright_outlined,
                          title: '侵权和违规内容处理',
                          subtitle:
                              'Geek工具箱基于网络公开资源及用户投稿接口开发，如侵犯您的权益请点击处理。',
                        ),
                        _buildInfoItem(
                          icon: Icons.privacy_tip_outlined,
                          title: '隐私政策',
                          subtitle: 'Geek工具箱隐私政策。',
                        ),
                        _buildInfoItem(
                          icon: Icons.gavel_outlined,
                          title: '用户协议',
                          subtitle: 'Geek工具箱用户协议。',
                        ),
                        _buildInfoItem(
                          icon: Icons.admin_panel_settings_outlined,
                          title: '权限说明',
                          subtitle: 'Geek工具箱功能所需权限公示。',
                        ),
                      ],
                    ),

                    _buildSectionCard(
                      title: '其他',
                      children: [
                        _buildInfoItem(
                          icon: Icons.feedback_outlined,
                          title: '反馈',
                          subtitle: '功能投稿 | 功能失效 | 创意建议，点击此处提交。',
                        ),
                        _buildInfoItem(
                          icon: Icons.help_outline_rounded,
                          title: '帮助',
                          subtitle: 'Geek工具箱使用中的常见问题。',
                        ),
                        _buildInfoItem(
                          icon: Icons.group_add_outlined,
                          title: '加入官群',
                          subtitle: '与五湖四海的小伙伴交流聊天。',
                        ),
                        _buildInfoItem(
                          icon: Icons.wechat,
                          title: '微信公众号',
                          subtitle: '点击查看Geek工具箱官方微信公众号。',
                        ),
                        _buildInfoItem(
                          icon: Icons.settings_outlined,
                          title: '设置',
                          subtitle: 'Geek工具箱个人设置需求。',
                        ),
                        _buildInfoItem(
                          icon: Icons.info_outline_rounded,
                          title: '关于',
                          subtitle: 'Geek工具箱信息与作者联系方式（QQ：3377639199）。',
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
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF5A6570),
                letterSpacing: 0.8,
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
            indent: 56,
            endIndent: 14,
            color: Color(0xFFEFF3F6),
          ),
        );
      }
    }
    return widgets;
  }

  Widget _buildNavItem({
    required IconData icon,
    required String title,
    bool isSelected = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Material(
        color: isSelected ? _selectedBgColor : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          minLeadingWidth: 24,
          leading: Icon(
            icon,
            size: 21,
            color: isSelected ? _primaryColor : const Color(0xFF596674),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? _primaryColor : const Color(0xFF1F2933),
            ),
          ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: Color(0xFFB2BDC8),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onTap: () {},
        ),
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      minLeadingWidth: 24,
      leading: Icon(icon, size: 21, color: const Color(0xFF5F6B78)),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Color(0xFF1F2933),
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          subtitle,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF7B8794),
            height: 1.35,
          ),
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: Color(0xFFB2BDC8),
      ),
      onTap: () {},
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFF7FDFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFE6F5F8),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.verified_user_outlined,
              size: 28,
              color: _primaryColor,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '未登录会员',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2933),
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  '登录后可同步收藏与配置',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF75808C),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {},
            style: TextButton.styleFrom(
              foregroundColor: _primaryColor,
              backgroundColor: const Color(0xFFEAF8F9),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('点击登录'),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(18, 4, 18, 14),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF8B98A7)),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'Geek工具箱 · 作者QQ：3377639199',
              style: TextStyle(fontSize: 12, color: Color(0xFF8B98A7)),
            ),
          ),
        ],
      ),
    );
  }
}