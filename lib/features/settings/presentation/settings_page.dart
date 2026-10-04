import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_routes.dart';
import '../../../design_system/app_theme_controller.dart';
import '../../../design_system/app_tokens.dart';
import '../../../design_system/settings_list.dart';

/// 独立设置页。
///
/// 为什么要有它：改之前抽屉里的「设置」和「账号中心」跳的是**同一个**
/// `AppRoutes.account`（app_drawer.dart 的两处 _buildMoreItem），两个不同
/// 图标、不同名字的入口点进去是同一个页面。那是 bug，不是设计取向。
///
/// 分组按用户拍板的方向：通用设置 / 数据设置。
///
/// 关于深色模式：**开关在这里**，档位交给 `AppThemeController`（跟随系统 /
/// 一直亮 / 一直暗）。它成立的前提是 `AppTokens` 的**表面与文字色**已经从
/// `static const` 改成随亮度解析的 getter（品牌色与状态色仍是常量）——
/// 否则开关只会切换 Material 组件的默认色，页面上那一千多处引用纹丝不动，
/// 结果是白底卡片配深色文字混排，比不做更糟。代价是这些色值不再是编译期
/// 常量，原先写在 `const` 构造里的调用要去掉 `const`。
///
/// 「主题配色」（换主色）仍未开放：那要先把配色做成可切换的语义色板，
/// 与深浅是两件独立的事。它继续如实标着「暂不可用」。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  /// 三档选择：跟随系统 / 一直亮 / 一直暗。
  ///
  /// 用 ListTile + 勾选而不是 RadioListTile：新版 Flutter 的 Radio 分组 API
  /// 正在改（groupValue/onChanged 已被标记），这里不押注某个版本。
  Future<void> _pickThemeMode(BuildContext context) async {
    final controller = AppThemeController.instance;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTokens.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                '深色模式',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTokens.textPrimary,
                ),
              ),
            ),
            for (final option in AppThemePreference.values)
              ListTile(
                title: Text(
                  option.label,
                  style: TextStyle(fontSize: 14, color: AppTokens.textPrimary),
                ),
                trailing: option == controller.preference
                    ? const Icon(
                        Icons.check_rounded,
                        color: AppTokens.primaryBlue,
                        size: 20,
                      )
                    : null,
                onTap: () {
                  unawaited(controller.setPreference(option));
                  Navigator.of(sheetContext).pop();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

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
          SettingsSection(
            title: '通用设置',
            children: [
              ListenableBuilder(
                listenable: AppThemeController.instance,
                builder: (context, _) {
                  final preference = AppThemeController.instance.preference;
                  return SettingsTile(
                    icon: Icons.dark_mode_outlined,
                    title: '深色模式',
                    subtitle: '跟随系统时按手机的深色设置自动切换',
                    trailingText: preference.label,
                    trailingTextColor: AppTokens.primaryBlue,
                    onTap: () => _pickThemeMode(context),
                  );
                },
              ),
              const SettingsTile(
                icon: Icons.palette_outlined,
                title: '主题配色',
                subtitle: '暂不可用：等配色改为可切换后开放',
                enabled: false,
                onTap: null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsSection(
            title: '数据设置',
            children: [
              SettingsTile(
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
          const SizedBox(height: 12),
          // 诊断：原先这里没有落点（扩展页那个假「诊断」入口 2026-10-03 已撤）。
          SettingsSection(
            title: '诊断',
            children: [
              SettingsTile(
                icon: Icons.fact_check_outlined,
                title: '应用自检',
                subtitle: '片源健康、线路记忆、更新通道、网络诊断',
                onTap: () =>
                    Navigator.of(context).pushNamed(AppRoutes.selfCheck),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
