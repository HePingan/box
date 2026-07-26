import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../config/video_proxy_config.dart';

import '../../design_system/widgets/app_page_scaffold.dart';
import '../controller/history_controller.dart';
import '../controller/video_controller.dart';
import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../video_module.dart';
import '../widgets/douban_ranking_section.dart';
import 'video_downloads_page.dart';
import '../widgets/history_quick_view.dart';
import '../../design_system/app_tokens.dart';
import 'aggregate_search_page.dart';
import 'favorites_page.dart';
import 'home/home_category_bar.dart';
import 'home/home_source_sheet.dart';
import 'home/home_utils.dart';
import 'home/home_video_grid.dart';
import 'video_detail_page.dart';
import 'video_search_page.dart';

class VideoSliverHome extends StatefulWidget {
  final String title;
  final bool showHistory;
  final VoidCallback? onSearchTap;

  const VideoSliverHome({
    super.key,
    this.title = '视频',
    this.showHistory = true,
    this.onSearchTap,
  });

  @override
  State<VideoSliverHome> createState() => _VideoSliverHomeState();
}

class _VideoSliverHomeState extends State<VideoSliverHome> {
  static const String _fallbackCatalogUrl = kDefaultVideoCatalogUrlFormat0;

  final ScrollController _scrollController = ScrollController();
  bool _autoLoadMoreRunning = false;
  VideoController? _observedController;

  /// 「按分类浏览」区默认收起：首屏只露豆瓣热榜 + 继续观看，页面更短更清爽。
  /// 收起时不触发自动翻页，避免为隐藏内容白白 loadMore。
  bool _browseExpanded = false;

  void _toggleBrowse() {
    setState(() => _browseExpanded = !_browseExpanded);
    if (_browseExpanded) {
      // 展开后按需把首屏填满（此前收起时跳过了自动翻页）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _autoLoadMoreIfNeeded();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _attachControllerListener();
      _bootstrapCatalogIfNeeded();
    });
  }

  @override
  void dispose() {
    _observedController?.removeListener(_onControllerChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _attachControllerListener() {
    final controller = context.read<VideoController>();
    if (identical(_observedController, controller)) return;
    _observedController?.removeListener(_onControllerChanged);
    _observedController = controller..addListener(_onControllerChanged);
  }

  /// 消费分类稀疏回退提示：弹一行轻提示后立即清除，避免重复弹出。
  void _onControllerChanged() {
    final controller = _observedController;
    if (controller == null) return;
    final notice = controller.categoryNotice;
    if (notice == null) return;
    controller.clearCategoryNotice();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showSnackBar(notice);
    });
  }

  Future<void> _bootstrapCatalogIfNeeded({bool force = false}) async {
    final controller = context.read<VideoController>();

    if (!force &&
        (controller.sources.isNotEmpty || controller.videoList.isNotEmpty)) {
      return;
    }

    final resolvedUrl = await VideoModule.resolveWorkingCatalogUrl();
    final catalogUrl = resolvedUrl ?? _fallbackCatalogUrl;

    if (!mounted) return;

    await controller.initSources(catalogUrl);

    if (!mounted) return;

    if (controller.currentSource != null && controller.videoList.isEmpty) {
      await controller.refreshCurrentSource();
    }

    if (!mounted) return;
    await _autoLoadMoreIfNeeded();
  }

  Future<void> _reloadCurrentSource() async {
    final controller = context.read<VideoController>();

    if (controller.currentSource != null) {
      await controller.refreshCurrentSource();
      if (!mounted) return;
      await _autoLoadMoreIfNeeded();
      return;
    }

    await _bootstrapCatalogIfNeeded(force: true);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    // 分类浏览收起时网格不可见，不触发翻页。
    if (!_browseExpanded) return;

    final controller = context.read<VideoController>();

    if (_scrollController.position.extentAfter < 220 &&
        !controller.isLoading &&
        controller.hasMore) {
      controller.loadMore();
    }
  }

  Future<void> _autoLoadMoreIfNeeded() async {
    // 分类浏览收起时网格不可见，跳过自动填充翻页。
    if (!_browseExpanded) return;
    if (_autoLoadMoreRunning || !mounted) return;

    _autoLoadMoreRunning = true;
    try {
      const int safetyLimit = 8;
      final controller = context.read<VideoController>();

      for (int i = 0; i < safetyLimit; i++) {
        if (!mounted) break;

        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) break;

        if (!_scrollController.hasClients) continue;
        if (controller.isLoading || !controller.hasMore) break;

        final position = _scrollController.position;
        final needsMoreContent =
            position.maxScrollExtent <= 0 || position.extentAfter < 220;

        if (!needsMoreContent) break;

        await controller.loadMore();
      }
    } finally {
      _autoLoadMoreRunning = false;
    }
  }

  Future<void> _openCurrentSourceSearch(VideoController controller) async {
    final source = controller.currentSource;
    if (source == null) {
      _showSnackBar('暂无可搜索的片源');
      return;
    }

    if (widget.onSearchTap != null) {
      widget.onSearchTap!.call();
      return;
    }

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VideoSearchPage(currentSource: source)),
    );
  }

  Future<void> _openAggregateSearch() async {
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AggregateSearchPage()),
    );
  }

  Future<void> _openFavorites() async {
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FavoritesPage()),
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String? _resolveCoverUrl(VodItem video, VideoSource? source) {
    final resolved = source == null
        ? null
        : resolveVideoCoverSync(video, source)?.trim();

    if (resolved != null && resolved.isNotEmpty) {
      return resolved;
    }

    final fallback = video.vodPic?.trim() ?? '';
    if (fallback.isEmpty) return null;

    return fallback;
  }

  Widget _buildBottomLoader(VideoController controller) {
    if (controller.videoList.isEmpty) return const SizedBox.shrink();

    if (!controller.hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            '—— 已经到底啦 ——',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
      );
    }

    if (controller.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return const SizedBox(height: 48);
  }

  Widget _buildHeaderCard(
    BuildContext context, {
    required VideoController controller,
    required VideoSource? source,
    required String subtitle,
  }) {
    // 工具栏式头部：图标 + 标题 + 片源数一行，右侧三枚紧凑操作按钮，
    // 不再用等宽大按钮占高，让分类/内容更早进入首屏。
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: const Color(0xFFEDF1F8)),
        boxShadow: AppTokens.shadowSm(),
      ),
      child: Row(
        children: [
          const _VideoLightIcon(icon: Icons.local_movies_rounded),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '光影剧场',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTokens.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTokens.textSecondary,
                    fontSize: 11.5,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _VideoHeaderAction(
            icon: Icons.search_rounded,
            label: '搜索',
            color: AppTokens.primaryBlue,
            onTap: () => _openCurrentSourceSearch(controller),
          ),
          _VideoHeaderAction(
            icon: Icons.public_rounded,
            label: '聚合',
            color: AppTokens.violet,
            onTap: _openAggregateSearch,
          ),
          _VideoHeaderAction(
            icon: Icons.favorite_rounded,
            label: '追剧',
            color: AppTokens.rose,
            onTap: _openFavorites,
          ),
          _VideoHeaderAction(
            icon: Icons.file_download_rounded,
            label: '下载',
            color: AppTokens.primaryBlue,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const VideoDownloadsPage()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderSection(VideoController controller, double screenWidth) {
    return SafeAnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final source = controller.currentSource;
        final subtitle = source == null
            ? (controller.sources.isEmpty ? '暂无可用片源' : '加载中...')
            : '已接入 ${controller.sources.length} 个片源 · 绿色净化';

        return Container(
          color: Colors.transparent,
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
          child: _buildHeaderCard(
            context,
            controller: controller,
            source: source,
            subtitle: subtitle,
          ),
        );
      },
    );
  }

  Widget _buildCategorySection(VideoController controller) {
    return SafeAnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.only(top: 4.0, bottom: 2.0),
          child: HomeCategoryBar(controller: controller),
        );
      },
    );
  }

  Widget _buildVideoHeaderSection(VideoController controller) {
    return SafeAnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final source = controller.currentSource;
        final hasSources = controller.sources.isNotEmpty;

        // 清新版：整行可点击折叠「按分类浏览」区。展开后才显示刷新/换源，
        // 收起时只留标题 + 展开箭头，首屏更短。
        return InkWell(
          onTap: _toggleBrowse,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 10, 4),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 15,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    source == null ? '按分类浏览' : '按分类浏览 · ${source.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppTokens.textPrimary,
                    ),
                  ),
                ),
                if (_browseExpanded) ...[
                  _VideoTextAction(
                    icon: Icons.refresh_rounded,
                    label: '刷新',
                    onTap: _reloadCurrentSource,
                  ),
                  const SizedBox(width: 2),
                  _VideoTextAction(
                    icon: Icons.swap_horiz_rounded,
                    label: '换源',
                    onTap: hasSources
                        ? () => showHomeSourcePickerSheet(context, controller)
                        : null,
                  ),
                  const SizedBox(width: 2),
                ],
                Icon(
                  _browseExpanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 22,
                  color: AppTokens.textSecondary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideoGridSection(
    VideoController controller,
    double screenWidth,
  ) {
    return SafeAnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final source = controller.currentSource;
        final safeVideoList = controller.videoList
            .where((video) {
              return isSafeContent(video.typeName) &&
                  isSafeContent(video.vodName);
            })
            .toList(growable: false);

        final hasRawVideos = controller.videoList.isNotEmpty;

        final emptyMessage = source == null
            ? '暂无可用视频源'
            : hasRawVideos
            ? '当前内容已被安全过滤\n请尝试切换其他分类或片源'
            : '站长没有往这个分类里放视频哦~\n请尝试在上方选择其他实体分类';

        return HomeVideoSliverGrid(
          videos: safeVideoList,
          screenWidth: screenWidth,
          isLoading: controller.isLoading,
          coverUrlFor: (video) => _resolveCoverUrl(video, source),
          onTapVideo: (video) {
            if (source == null) {
              _showSnackBar('暂无可用片源');
              return;
            }

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    VideoDetailPage(source: source, vodId: video.vodId),
              ),
            );
          },
          onItemBuild: (index) => controller.prefetchCoversAround(index),
          emptyMessage: emptyMessage,
          emptyActionLabel: '刷新重试',
          onEmptyAction: _reloadCurrentSource,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final videoController = context.read<VideoController>();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final layoutWidth = min(screenWidth, 560.0);

    final hasHistory =
        widget.showHistory &&
        context.read<HistoryController>().historyList.isNotEmpty;

    return AppPageScaffold(
      // safeTop:true 让内容避开状态栏/刘海（背景渐变在 SafeArea 外层，仍全屏铺满，
      // 不会露白边）。此前 false 导致 Header 卡片与系统状态栏重叠。
      safeTop: true,
      child: RefreshIndicator(
        onRefresh: _reloadCurrentSource,
        child: Center(
          child: SizedBox(
            width: layoutWidth,
            child: CustomScrollView(
              controller: _scrollController,
              // 默认 250px 只预渲染视口外一点点。封面墙给一屏左右的
              // cacheExtent，配合扩容后的 ImageCache，滚动方向提前解码好，
              // 快速下滑不露白、回滚即命中。
              scrollCacheExtent: const ScrollCacheExtent.pixels(800),
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(
                  child: _buildHeaderSection(videoController, screenWidth),
                ),
                if (hasHistory)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: HistoryQuickView(
                        title: '继续观看',
                        subtitle: '最近播放记录',
                        emptyText: '暂无继续观看内容',
                      ),
                    ),
                  ),
                // 豆瓣热榜(真实数据,非编造): 热门电影/剧集双 Tab,
                // 点击后当前源优先搜→聚合兜底→进详情页。
                const SliverToBoxAdapter(
                  child: DoubanRankingSection(),
                ),
                // 「按分类浏览」头部常驻（可点击展开/收起）；
                // 分类栏 + 网格 + 加载更多仅在展开时挂载。
                SliverToBoxAdapter(
                  child: _buildVideoHeaderSection(videoController),
                ),
                if (_browseExpanded) ...[
                  SliverToBoxAdapter(
                    child: _buildCategorySection(videoController),
                  ),
                  _buildVideoGridSection(videoController, screenWidth),
                  SliverToBoxAdapter(
                    child: SafeAnimatedBuilder(
                      animation: videoController,
                      builder: (context, _) =>
                          _buildBottomLoader(videoController),
                    ),
                  ),
                ],
                const SliverToBoxAdapter(
                  child: SizedBox(height: AppTokens.pageBottomPadding + 32),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoLightIcon extends StatelessWidget {
  const _VideoLightIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFFF2F6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E8F6)),
      ),
      child: Icon(icon, color: AppTokens.primaryBlue, size: 21),
    );
  }
}

/// 工具栏式头部操作：小图标 + 短标签，浅色底，竖排紧凑，占高低。
class _VideoHeaderAction extends StatelessWidget {
  const _VideoHeaderAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 17, color: color),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 清新版轻文字按钮：图标 + 文案，无边框，点按浅色高亮。
class _VideoTextAction extends StatelessWidget {
  const _VideoTextAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = enabled ? AppTokens.textSecondary : AppTokens.textTertiary;
    return InkWell(
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


