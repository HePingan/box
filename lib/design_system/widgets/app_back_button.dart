import 'package:flutter/material.dart';

import '../app_tokens.dart';

/// 统一的返回按钮组件 — 用于各页面的头部 / HeroCard leading。
///
/// 视觉口径：**只有箭头（+ 可选文字），不套卡片**。
/// 改之前它是个白底圆角卡片 + 描边 + 阴影，左边还插了一根蓝青渐变竖条 ——
/// 那根竖条是**分区标题**的语言（`AppSectionHeader` 用它），借到返回按钮上
/// 就成了「一张浮起来的小卡片，还带个标题标记」：真机上看着很突兀，
/// 而且它右边往往就是页面自己的标题，两个"家具"挤在一起。
/// 现在跟系统返回一致：箭头 + 去处文字，直接落在页面底色上（无底、无边、无阴影）。
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.onPressed, this.label});

  final VoidCallback? onPressed;

  /// 返回到**哪里**（去处），**不是当前页名** —— 当前页名交给页面自己的标题，
  /// 否则既重复又指错方向。依据见
  /// `test/design_system/back_button_label_semantics_test.dart`。
  final String? label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      onTap: onPressed,
      child: Padding(
        // 8/6 让点击区域不小于 40×36（只有箭头时也够点）。
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.keyboard_arrow_left_rounded,
              size: 24,
              color: AppTokens.textPrimary,
            ),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(
                label!,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.textPrimary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 轻量版返回按钮 — 用于 SliverAppBar leading，无背景容器。
class AppBackButtonLight extends StatelessWidget {
  const AppBackButtonLight({super.key, this.onPressed, this.label});

  final VoidCallback? onPressed;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.keyboard_arrow_left_rounded,
              size: 22,
              color: theme.colorScheme.primary,
            ),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(
                label!,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
