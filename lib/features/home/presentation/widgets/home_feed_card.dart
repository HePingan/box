// lib/features/home/presentation/widgets/home_feed_card.dart
//
// 首页「资讯」卡：把原先上下紧邻的「今日热闻」和「AI 热点」两个独立分区
// 合并成一张带 Tab 的卡片。
//
// 为什么合：实测真机尺寸（392x850）渲染下来，两块的外框、行高、条数（都是 3 条）
// 完全一致，扫视时像同一个组件贴了两遍；两块合计吃掉首屏近六成高度，而它们都是
// 「读一眼就走」的低频内容，却压在「继续使用」这种高频入口下面。合并省掉一个
// 分区标题 + 一套卡片边框，同时给两种资讯一个明确的形态区分（Tab 切换）。
//
// 两个数据源都保留，各自的加载态/空态/重试互不影响——一边挂了另一边照常看。
library;

import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/features/home/data/ai_hot_models.dart';
import 'package:box/features/home/data/daily_news_service.dart';
import 'package:box/features/home/presentation/widgets/ai_hot_section.dart';
import 'package:box/features/home/presentation/widgets/home_widgets.dart';

/// 资讯卡的两个页签。
enum HomeFeedTab { news, aiHot }

class HomeFeedCard extends StatefulWidget {
  const HomeFeedCard({
    super.key,
    required this.isLoadingNews,
    required this.newsItems,
    required this.newsError,
    required this.onOpenNews,
    required this.onOpenNewsAll,
    required this.isLoadingAiHot,
    required this.aiHotFeed,
    required this.onOpenAiHot,
    required this.onOpenAiHotAll,
    required this.onRetryAiHot,
  });

  // ── 热闻侧 ──
  final bool isLoadingNews;
  final List<DailyNewsItem> newsItems;

  /// 拿不到热闻时的提示文案；成功时为空串。
  final String newsError;
  final void Function(DailyNewsItem item) onOpenNews;
  final VoidCallback onOpenNewsAll;

  // ── AI 侧 ──
  final bool isLoadingAiHot;
  final AiHotFeed? aiHotFeed;
  final void Function(AiHotItem item) onOpenAiHot;
  final VoidCallback onOpenAiHotAll;
  final VoidCallback onRetryAiHot;

  @override
  State<HomeFeedCard> createState() => _HomeFeedCardState();
}

class _HomeFeedCardState extends State<HomeFeedCard> {
  /// 默认停在热闻：它是通用资讯，受众比 AI 垂类广。
  HomeFeedTab _tab = HomeFeedTab.news;

  @override
  Widget build(BuildContext context) {
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
          _header(),
          Container(
            decoration: BoxDecoration(
              color: AppTokens.surface,
              borderRadius: BorderRadius.circular(AppTokens.radiusCard),
              border: Border.all(color: AppTokens.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _tab == HomeFeedTab.news
                  ? _newsChildren()
                  : _aiHotChildren(),
            ),
          ),
        ],
      ),
    );
  }

  /// 分区标题：沿用首页其它分区的「彩色竖条 + 标题」样式，右侧放 Tab 和「更多」。
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: AppTokens.orange,
              borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            '资讯',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: AppTokens.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(width: 10),
          _tabChip(HomeFeedTab.news, '热闻'),
          const SizedBox(width: 4),
          _tabChip(HomeFeedTab.aiHot, 'AI'),
          // 离线提示：AI 内容来自缓存时明确告诉用户，别让人以为是最新的。
          // 只在 AI 页签下显示（热闻侧没有缓存态这个概念）。
          if (_tab == HomeFeedTab.aiHot && widget.aiHotFeed?.fromCache == true)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
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
            ),
          const Spacer(),
          // 「更多」按当前 Tab 分派：热闻进热闻页，AI 进 AI HOT 站点。
          GestureDetector(
            onTap: _tab == HomeFeedTab.news
                ? widget.onOpenNewsAll
                : widget.onOpenAiHotAll,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                '更多',
                style: TextStyle(
                  fontSize: 12.5,
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

  Widget _tabChip(HomeFeedTab tab, String label) {
    final bool active = _tab == tab;
    return GestureDetector(
      onTap: () {
        if (_tab == tab) return;
        setState(() => _tab = tab);
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: active ? AppTokens.primaryBlue.withValues(alpha: 0.10) : null,
          borderRadius: BorderRadius.circular(AppTokens.radiusChip),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w900 : FontWeight.w600,
            color: active ? AppTokens.primaryBlue : AppTokens.textTertiary,
          ),
        ),
      ),
    );
  }

  // ── 热闻侧内容 ──
  List<Widget> _newsChildren() {
    if (widget.isLoadingNews) return const <Widget>[_CardSpinner()];
    if (widget.newsError.isNotEmpty) {
      return <Widget>[
        HomeNewsLine(
          text: widget.newsError,
          showDivider: false,
          isPlaceholder: true,
        ),
      ];
    }
    return List<Widget>.generate(widget.newsItems.length, (int index) {
      final DailyNewsItem item = widget.newsItems[index];
      final bool showDivider = index != widget.newsItems.length - 1;
      // 上游偶尔给不出 url，这种条目点开会是空白详情页，
      // 所以不挂手势也不显示箭头。
      final Widget line = HomeNewsLine(
        text: item.title,
        showDivider: showDivider,
        isPlaceholder: !item.isOpenable,
      );
      if (!item.isOpenable) return line;
      return GestureDetector(
        onTap: () => widget.onOpenNews(item),
        behavior: HitTestBehavior.opaque,
        child: line,
      );
    });
  }

  // ── AI 侧内容 ──
  List<Widget> _aiHotChildren() {
    final List<AiHotItem> items =
        widget.aiHotFeed?.items.take(kAiHotPreviewCount).toList() ??
        const <AiHotItem>[];

    if (widget.isLoadingAiHot && items.isEmpty) {
      return const <Widget>[_CardSpinner()];
    }
    if (items.isEmpty) {
      return <Widget>[AiHotEmptyState(onRetry: widget.onRetryAiHot)];
    }
    return <Widget>[
      ...List<Widget>.generate(items.length, (int index) {
        final AiHotItem item = items[index];
        return AiHotRow(
          item: item,
          showDivider: index != items.length - 1,
          onTap: () => widget.onOpenAiHot(item),
        );
      }),
      // 署名是上游硬要求，有内容就必须标出来。
      AiHotAttributionFooter(
        label: widget.aiHotFeed?.attributionLabel ?? 'AIHOT',
      ),
    ];
  }
}

class _CardSpinner extends StatelessWidget {
  const _CardSpinner();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
