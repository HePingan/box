import 'package:flutter/material.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFFF3FAFC), // 淡青蓝背景色
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 顶部卡片
              _buildHeaderCard(),
              const SizedBox(height: 20),

              // 2. 主页模块
              _buildSectionTitle('主页'),
              _buildNavItem(icon: Icons.home_outlined, title: '软件首页', isSelected: true),
              _buildNavItem(icon: Icons.grid_view_rounded, title: '全部工具'),
              _buildNavItem(icon: Icons.inventory_2_outlined, title: '仓库合集'),

              const SizedBox(height: 8),
              const Divider(color: Colors.black12, height: 24),

              // 3. 更多模块
              _buildSectionTitle('更多'),
              _buildNavItem(icon: Icons.update, title: '更新日志'),
              _buildNavItem(icon: Icons.share_outlined, title: '分享软件'),
              _buildNavItem(icon: Icons.help_outline, title: '关于软件'),
              
              const SizedBox(height: 8),
              const Divider(color: Colors.black12, height: 24),
              _buildNavItem(icon: Icons.palette_outlined, title: '主题颜色'),

              const SizedBox(height: 12),
              
              // 4. 支持模块
              _buildSectionTitle('支持'),
              _buildInfoItem(icon: Icons.sim_card_outlined, title: '暮光官方流量卡', subtitle: '四大运营商正规超实惠流量卡，0元下单领取。'),
              _buildInfoItem(icon: Icons.savings_outlined, title: '捐赠支持', subtitle: '全用于暮光项目开发维护'),

              const SizedBox(height: 16),

              // 5. 政策模块
              _buildSectionTitle('政策'),
              _buildInfoItem(icon: Icons.copyright_outlined, title: '侵权和违规内容处理', subtitle: '暮光开发均为网络收集及用户投稿开放接口开发而成，若侵犯了您的合法权益请点击此处。'),
              _buildInfoItem(icon: Icons.privacy_tip_outlined, title: '隐私政策', subtitle: '暮光隐私政策'),
              _buildInfoItem(icon: Icons.gavel_outlined, title: '用户协议', subtitle: '暮光用户协议'),
              _buildInfoItem(icon: Icons.admin_panel_settings_outlined, title: '权限说明', subtitle: '暮光功能工具所需要到的权限公示'),

              const SizedBox(height: 16),

              // 6. 其他模块
              _buildSectionTitle('其他'),
              _buildInfoItem(icon: Icons.feedback_outlined, title: '反馈', subtitle: '功能投稿 | 功能失效 | 创意投稿 点击此处'),
              _buildInfoItem(icon: Icons.help_outline, title: '帮助', subtitle: '一些暮光使用中会遇到的常见问题'),
              _buildInfoItem(icon: Icons.group_add_outlined, title: '加入官群', subtitle: '与五湖四海的小伙伴吹水聊天'),
              _buildInfoItem(icon: Icons.wechat_outlined, title: '微信公众号', subtitle: '点击查看暮光官方微信公众号'),
              _buildInfoItem(icon: Icons.settings_outlined, title: '设置', subtitle: '暮光个人设置需求'),
              _buildInfoItem(icon: Icons.info_outline, title: '关于', subtitle: '关于暮光'),
              
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 12.0, bottom: 8.0, top: 4.0),
      child: Text(
        title,
        style: TextStyle(fontSize: 15, color: Colors.grey[700], fontWeight: FontWeight.w500, letterSpacing: 1.0),
      ),
    );
  }

  Widget _buildNavItem({required IconData icon, required String title, bool isSelected = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2.0),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFC7ECED) : Colors.transparent, 
        borderRadius: BorderRadius.circular(24.0),
      ),
      child: ListTile(
        leading: Icon(icon, color: isSelected ? const Color(0xFF097E8B) : const Color(0xFF535D66)),
        title: Text(title, style: TextStyle(
          color: isSelected ? const Color(0xFF097E8B) : Colors.black87,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        )),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.0)),
        dense: true, 
        visualDensity: const VisualDensity(vertical: -1), 
        onTap: () {},
      ),
    );
  }

  Widget _buildInfoItem({required IconData icon, required String title, required String subtitle}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      leading: Icon(icon, color: Colors.grey[700], size: 26),
      title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.normal, color: Color(0xFF333333))),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[500], height: 1.3)),
      ),
      onTap: () {},
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))
        ]
      ),
      child: Row(
        children: [
          Icon(Icons.verified_user_outlined, size: 40, color: Colors.blue[800]),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('未登录会员', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
              const SizedBox(height: 4),
              Text('点击登录', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            ],
          )
        ],
      ),
    );
  }
}