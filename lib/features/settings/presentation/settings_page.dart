import 'package:flutter/material.dart';

import '../../../app/app_routes.dart';
import '../../../design_system/app_tokens.dart';

/// 独立设置页。
///
/// 为什么要有它：改之前抽屉里的「设置」和「账号中心」跳的是**同一个**
/// `AppRoutes.account`（app_drawer.dart 的两处 _buildMoreItem），两个不同
/// 图标、不同名字的入口点进去是同一个页面。那是 bug，不是设计取向。
///
/// 分组按用户拍板的方向：通用设置 / 数据设置。
///
/// 关于深色模式——**这里故意没有开关**。`AppTokens` 的颜色全是
/// `static const` 亮色字面量（surface=0xFFFFFFFF、textPrimary=0xFF101828），
/// 被 70 个文件引用 1100 次，另有 204 处直接写 `Colors.white`，且
/// `AppTheme` 只有 `light()`。加一个 ThemeMode 开关只会切换 Material 组件
/// 默认色，页面上那 1300 处硬编码纹丝不动，结果是白底卡片配深色文字混排，
/// 比不做更糟。真要做得先把 AppTokens 改成随主题解析的动态取值，那是独立
/// 工程。放一个不生效的开关等于骗用户，所以这里只如实说明状态。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.background,
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: AppTokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const _SettingsSection(
            title: '通用设置',
            children: [
              _SettingsTile(
                icon: Icons.dark_mode_outlined,
                title: '深色模式',
                subtitle: '暂不可用：全局配色仍是固定亮色，开了会导致文字与背景撞色',
                enabled: false,
                onTap: null,
              ),
              _SettingsTile(
                icon: Icons.palette_outlined,
                title: '主题配色',
                subtitle: '暂不可用：等配色改为可切换后开放',
                enabled: false,
                onTap: null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SettingsSection(
            title: '数据设置',
            children: [
              _SettingsTile(
                icon: Icons.backup_outlined,
                title: '备份与恢复',
                subtitle: '导出或导入收藏、书架、阅读进度、本地题库',
                // 用常量而非字面量：路由改名时编译期就会报错，
                // 不会留下一个点了没反应的入口。
                onTap: () =>
                    Navigator.of(context).pushNamed(AppRoutes.dataSettings),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTokens.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppTokens.surface,
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            border: Border.all(color: AppTokens.divider),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    // 停用项调低对比度，但仍读得清说明文字——用户需要知道「为什么不能点」。
    final titleColor = enabled ? AppTokens.textPrimary : AppTokens.textTertiary;

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: enabled ? AppTokens.primaryBlue : AppTokens.textTertiary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTokens.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (enabled)
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
}
