// lib/features/home/presentation/widgets/ai_hot_section.dart
//
// 首页「AI 热点」区块，数据来自 aihot.virxact.com 的公开精选接口。
//
// 位置：放在「今日热闻」下面（用户指定）。视觉上刻意做得比热闻更"轻"：
// 热闻是纯文字列表，这里用横向卡片带分类标签 + 热度，两者不会看起来重复。
library;

import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/features/home/data/ai_hot_models.dart';

/// 首页展示的 AI 热点条数。
///
/// 3 条的理由：首页已经有快捷入口 + 插件 + 继续使用 + 今日热闻，
/// 再多这一屏就滚不完了。看更多走「全部」按钮。
const int kAiHotPreviewCount = 3;

// 说明：原先的 `AiHotSection`（独立的「AI 热点」分区）已被 `HomeFeedCard` 取代，
// 首页不再有单独的 AI 分区。类本体已删除，避免同一份 AI 渲染逻辑存在两套实现；
// 下面三个 widget 和 `kAiHotPreviewCount` 是被合并卡复用的公共件，保留在此。

class AiHotEmptyState extends StatelessWidget {
  const AiHotEmptyState({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.cloud_off_rounded,
            size: 16,
            color: AppTokens.textTertiary,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '暂时拿不到 AI 热点',
              style: TextStyle(fontSize: 13, color: AppTokens.textTertiary),
            ),
          ),
          GestureDetector(
            onTap: onRetry,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                '重试',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTokens.primaryBlue,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 署名栏。
///
/// 不是装饰——AI HOT 接口返回的每条数据都带 attribution 字段，
/// 用它的内容就该把来源标出来。空态下不显示（既有约定）。
class AiHotAttributionFooter extends StatelessWidget {
  const AiHotAttributionFooter({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTokens.divider)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.bolt_rounded,
            size: 12,
            color: AppTokens.textTertiary,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '内容来源 $label',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppTokens.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// AI 热点单行。
///
/// 公开（而不是私有）是为了让合并后的 [HomeFeedCard] 直接复用同一套行样式，
/// 避免出现第二份「长得一样但各自维护」的实现。
class AiHotRow extends StatelessWidget {
  const AiHotRow({
    super.key,
    required this.item,
    required this.showDivider,
    required this.onTap,
  });

  final AiHotItem item;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          border: showDivider
              ? const Border(bottom: BorderSide(color: AppTokens.divider))
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: AppTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                if (item.categoryLabel.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTokens.violet.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(
                        AppTokens.radiusChip,
                      ),
                    ),
                    child: Text(
                      item.categoryLabel,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppTokens.violet,
                      ),
                    ),
                  ),
                if (item.source != null) ...<Widget>[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      item.source!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTokens.textTertiary,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (item.relativeTime != null)
                  Text(
                    item.relativeTime!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTokens.textTertiary,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
