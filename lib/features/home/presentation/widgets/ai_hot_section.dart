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

class AiHotSection extends StatelessWidget {
  const AiHotSection({
    super.key,
    required this.isLoading,
    required this.feed,
    required this.onOpenItem,
    required this.onOpenAll,
    required this.onRetry,
  });

  final bool isLoading;
  final AiHotFeed? feed;

  /// 点某一条，参数是该条要打开的地址。
  final void Function(AiHotItem item) onOpenItem;

  /// 点「全部」，进 AI HOT 站点。
  final VoidCallback onOpenAll;

  /// 加载失败时点「重试」。
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final items = feed?.items ?? const <AiHotItem>[];
    final visible = items.take(kAiHotPreviewCount).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.shellPageGutter,
        0,
        AppTokens.shellPageGutter,
        14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _header(context),
          Container(
            decoration: BoxDecoration(
              color: AppTokens.surface,
              borderRadius: BorderRadius.circular(AppTokens.radiusCard),
              border: Border.all(color: AppTokens.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (isLoading && visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (visible.isEmpty)
                  _emptyState()
                else
                  ...List<Widget>.generate(visible.length, (int index) {
                    final AiHotItem item = visible[index];
                    return _AiHotRow(
                      item: item,
                      showDivider: index != visible.length - 1,
                      onTap: () => onOpenItem(item),
                    );
                  }),
                if (visible.isNotEmpty) _footer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: AppTokens.violet,
              borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'AI 热点',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: AppTokens.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(width: 6),
          // 离线提示：内容来自缓存时明确告诉用户，别让人以为是最新的。
          if (feed?.fromCache == true)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTokens.surfaceMuted,
                borderRadius: BorderRadius.circular(AppTokens.radiusChip),
              ),
              child: const Text(
                '缓存',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTokens.textTertiary,
                ),
              ),
            ),
          const Spacer(),
          GestureDetector(
            onTap: onOpenAll,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                '全部 ›',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTokens.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
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

  /// 署名栏。
  ///
  /// 不是装饰——AI HOT 接口返回的每条数据都带 attribution 字段，
  /// 用它的内容就该把来源标出来。
  Widget _footer() {
    final String label = feed?.attributionLabel ?? 'AIHOT';
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

class _AiHotRow extends StatelessWidget {
  const _AiHotRow({
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
