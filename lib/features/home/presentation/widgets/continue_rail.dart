// lib/features/home/presentation/widgets/continue_rail.dart
//
// 首页「继续使用」横向轨。
//
// 这里展示的是**真实**播放/阅读进度（来自 ContinueRepository），不是固定入口。
// 拿不到进度时不画进度条，也不编百分比 —— 详见 ContinueItem.progress 注释。
library;

import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/features/home/data/continue_item.dart';

class ContinueRail extends StatelessWidget {
  const ContinueRail({
    super.key,
    required this.items,
    required this.onOpen,
    required this.onBrowseNovel,
    required this.onBrowseVideo,
    this.onSeeAll,
  });

  final List<ContinueItem> items;
  final ValueChanged<ContinueItem> onOpen;
  final VoidCallback onBrowseNovel;
  final VoidCallback onBrowseVideo;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 右侧不留 padding：让横向列表滚到屏幕边缘，视觉上暗示还能划。
      padding: const EdgeInsets.fromLTRB(AppTokens.shellPageGutter, 0, 0, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: _header(),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: _empty(),
            )
          else
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(right: 14),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) => _ContinueCard(
                  item: items[index],
                  onTap: () => onOpen(items[index]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: AppTokens.amber,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          '继续使用',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTokens.textPrimary,
          ),
        ),
        const Spacer(),
        if (onSeeAll != null && items.isNotEmpty)
          TextButton(
            onPressed: onSeeAll,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              '查看全部',
              style: TextStyle(fontSize: 12, color: AppTokens.textSecondary),
            ),
          ),
      ],
    );
  }

  /// 从没看过也没读过时的引导。
  ///
  /// 不画假的进度卡，也不整块消失 —— 首页少一块会让下面的内容跳位，
  /// 而且新用户正需要知道从哪开始。
  Widget _empty() {
    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(color: AppTokens.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '还没有观看或阅读记录',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            '看过的剧集、读过的书会出现在这里，可一键回到上次位置',
            style: TextStyle(fontSize: 12, color: AppTokens.textSecondary),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Row(
            children: [
              _emptyAction(
                label: '去书架',
                icon: Icons.menu_book_rounded,
                color: AppTokens.amber,
                onTap: onBrowseNovel,
              ),
              const SizedBox(width: AppTokens.spaceSm),
              _emptyAction(
                label: '去影视',
                icon: Icons.play_circle_fill_rounded,
                color: AppTokens.emerald,
                onTap: onBrowseVideo,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyAction({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusChip),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusChip),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.item, required this.onTap});

  final ContinueItem item;
  final VoidCallback onTap;

  bool get _isVideo => item.kind == ContinueKind.video;

  Color get _accent => _isVideo ? AppTokens.emerald : AppTokens.amber;

  IconData get _icon =>
      _isVideo ? Icons.play_circle_fill_rounded : Icons.menu_book_rounded;

  @override
  Widget build(BuildContext context) {
    final label = item.progressLabel;

    return Material(
      color: AppTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        side: const BorderSide(color: AppTokens.divider),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        onTap: onTap,
        child: Container(
          // 宽度给区间而不是死钉：短标题不留大片空白，长标题也不会把卡拉过屏宽。
          constraints: const BoxConstraints(minWidth: 190, maxWidth: 258),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              _cover(),
              const SizedBox(width: 10),
              // Flexible 而非 Expanded：Expanded 会强制占满 maxWidth，
              // 让宽度区间失效、短标题也按最宽算。
              Flexible(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTokens.textSecondary,
                      ),
                    ),
                    if (label != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: item.progress,
                                minHeight: 3,
                                backgroundColor: AppTokens.surfaceMuted,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  _accent,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: _accent,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cover() {
    final placeholder = Container(
      width: 44,
      height: 60,
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTokens.radiusChip),
      ),
      child: Icon(_icon, color: _accent, size: 20),
    );

    if (item.coverUrl.trim().isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTokens.radiusChip),
      child: Image.network(
        item.coverUrl,
        width: 44,
        height: 60,
        fit: BoxFit.cover,
        // 封面挂了就回落到图标，不留裂图。
        errorBuilder: (_, _, _) => placeholder,
        // 加载中也占同样的位，避免卡片宽度抖动。
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : placeholder,
      ),
    );
  }
}
