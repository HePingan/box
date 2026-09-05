import 'package:flutter/material.dart';

import '../../domain/account_models.dart';

/// 个人中心里的管理后台入口。
///
/// 抽屉头卡在 B6 之后已登录直达个人中心，账号中心退回「登录 / 服务器设置」。
/// 管理后台原先只挂在账号中心的 AccountStatusCard 上，若不在这里补一个入口，
/// 管理员登录后就再也点不到后台了。
///
/// 权限边界：只有 `role == 'admin'` 才渲染。这里只是**入口可见性**，真正的
/// 权限判定仍在服务端 —— 客户端隐藏入口不构成鉴权。
class PersonalCenterAdminEntry extends StatelessWidget {
  const PersonalCenterAdminEntry({
    super.key,
    required this.user,
    required this.onTap,
  });

  final BoxAccountUser? user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final current = user;
    if (current == null || !current.isAdmin) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.admin_panel_settings_outlined),
        title: const Text('管理后台'),
        subtitle: const Text('用户、额度与题库审核'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
