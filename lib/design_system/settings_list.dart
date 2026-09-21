import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// 设置式列表的分组与条目组件。
///
/// 为什么提取出来：这套「分组标题 + 白底圆角卡片 + 图标/标题/副标题/右箭头」
/// 的样式原本是 `settings_page.dart` 里的私有类 `_SettingsSection` /
/// `_SettingsTile`。关于页要长成"和设置一样"，如果照抄一份私有实现，两处样式
/// 就会各自漂移（padding 改一处忘一处、禁用态颜色不一致），这正是本项目已经
/// 踩过的坑（抽屉和个人中心各有一份「关于」实现，连应用名都写得不一样）。
/// 所以升级为公共组件，两个页面共用同一份事实源。
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
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

/// 设置式列表条目。
///
/// [trailingText] 用于「版本号」这类只读信息：有值时替换右侧箭头，
/// 因为一个不可点的条目却带着 chevron 会让人以为点了没反应。
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
    this.trailingText,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool enabled;
  final String? trailingText;

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
            if (trailingText != null)
              Text(
                trailingText!,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTokens.textSecondary,
                ),
              )
            else if (enabled && onTap != null)
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
