import 'package:flutter/material.dart';

import '../app_tokens.dart';

/// 区块标题：4px 金橙竖条 + 标题文字（可带右侧 trailing）。
///
/// 详情页里「选集」「影片资料」「剧情简介」三处标题原来各写一份样式 ——
/// 选集是纯文字 14/w800，另两处是 15/w900 + 橙竖条，同一屏出现两种标题风格，
/// 看着不像同一套界面。统一到这里：改一处，三处跟着变。
class AppSectionTitle extends StatelessWidget {
  const AppSectionTitle(
    this.title, {
    super.key,
    this.trailing,
    this.accent = const Color(0xFFFB923C),
  });

  final String title;

  /// 右侧可选控件（刷新、倒序这类），不传就不占位。
  final Widget? trailing;

  /// 竖条颜色，默认主题金橙。
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTokens.inkDark,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}
