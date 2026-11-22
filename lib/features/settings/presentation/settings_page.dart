import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_routes.dart';
import '../../../design_system/app_theme_controller.dart';
import '../../../design_system/app_tokens.dart';
import '../../../design_system/settings_list.dart';
import '../../extensions/market/data/plugin_share_link_channel.dart';

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

  /// 深链自检：App Links 是否已被系统校验通过。
  ///
  /// 这是唯一能看见「链接为什么不进 App」的地方 —— 校验失败时系统不给用户
  /// 任何提示，链接只是悄悄变成"打开浏览器"，看起来跟没做这个功能一样。
  Future<void> _showShareLinkDiagnosis(BuildContext context) async {
    final diag = await PluginShareLinkChannel.diagnose();
    if (!context.mounted) return;

    final state = (diag['webLinkState'] ?? 'unknown').toString();
    final schemeOk = diag['schemeResolvable'] == true;

    final (String title, String body) = switch (state) {
      'verified' => (
        '已认领',
        '系统已验证 box.hpa888.top。分享链接会直接打开 App，不经过浏览器。',
      ),
      'selected' => (
        '部分认领',
        '系统允许打开这个域名，但没完全验证（可能弹过选择器）。等系统重新校验，或卸载重装一次。',
      ),
      'none' => (
        '未验证',
        '系统读到了域名声明但校验没通过。常见原因：装机时没联网、assetlinks.json 取不到、或签名指纹不一致。卸载重装一次会重新触发校验。',
      ),
      'unlisted' => (
        '未声明',
        '系统里没有这个域名的记录，多半是当前版本还没有 https 声明（低于 1.21.50）。',
      ),
      'unsupported' => (
        '系统不支持查询',
        'Android 11 以下没有域名验证状态接口，只能看实际行为：点分享链接若停在落地页，就是还没被系统认领。',
      ),
      _ => ('未知', '查不到验证状态（非 Android，或通道不可用）。'),
    };

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('分享链接：$title'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(body),
            const SizedBox(height: 12),
            Text('域名：${diag['host'] ?? 'box.hpa888.top'}'),
            Text('自建 scheme：${schemeOk ? 'boxapp:// 可解析' : '不可解析'}'),
            if (diag['error'] != null) ...[
              const SizedBox(height: 8),
              Text(
                '诊断信息：${diag['error']}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              '不管这里显示什么，这条路永远可用：在「插件 → 导入 → 分享码」里手输那 6 位。',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('知道了'),
          ),
        ],
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
          // 伪装：单独一组而不是塞进「通用设置」。它改的是应用在桌面上的身份，
          // 属于「别人看到的样子」，与主题/配色不是一类；混在一起用户找不到。
          SettingsSection(
            title: '隐私',
            children: [
              SettingsTile(
                icon: Icons.calculate_outlined,
                title: '伪装与隐私',
                subtitle: '桌面图标与名称变成计算器，输口令才进得来',
                onTap: () =>
                    Navigator.of(context).pushNamed(AppRoutes.disguise),
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
              SettingsTile(
                icon: Icons.link,
                title: '分享链接状态',
                subtitle: '检查系统是否已认领 box.hpa888.top（App Links）',
                onTap: () => _showShareLinkDiagnosis(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
