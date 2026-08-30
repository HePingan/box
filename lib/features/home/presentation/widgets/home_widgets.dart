import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';

/// 今日热闻的单行条目。
///
/// 改版说明：原样式是「浅灰填充圆角块 + 蓝点」，每条自带底色，
/// 三条叠在白色卡片里会出现「卡中卡」的层次噪声。现在改成
/// 无底色的列表行 + 细分隔线，让白卡本身承担容器角色。
class HomeNewsLine extends StatelessWidget {
  const HomeNewsLine({
    super.key,
    required this.text,
    this.showDivider = true,
    this.isPlaceholder = false,
  });

  final String text;

  /// 是否画底部分隔线。最后一条传 false 可以免掉末尾多余的线。
  final bool showDivider;

  /// 这一行是不是「空态/错误态提示」而不是真新闻。
  ///
  /// 之前拉取失败时提示文案被塞成一条 _NewsItem，于是长得跟真新闻一样：
  /// 带蓝点、带右侧箭头、还能点开一个 url 为 null 的详情页。
  /// 置 true 时去掉箭头、换成弱化的提示样式，明确「这里不可点」。
  final bool isPlaceholder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(bottom: BorderSide(color: AppTokens.divider))
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: isPlaceholder
                  ? AppTokens.textTertiary
                  : AppTokens.primaryBlue,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isPlaceholder ? FontWeight.w500 : FontWeight.w600,
                color: isPlaceholder
                    ? AppTokens.textSecondary
                    : AppTokens.textPrimary,
                height: 1.3,
              ),
            ),
          ),
          if (!isPlaceholder) ...[
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: AppTokens.textTertiary,
            ),
          ],
        ],
      ),
    );
  }
}
