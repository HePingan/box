import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/video_proxy_config.dart';

import '../../design_system/widgets/app_page_scaffold.dart';
import '../controller/history_controller.dart';
import '../controller/video_controller.dart';
import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../video_module.dart';
import '../widgets/history_quick_view.dart';
import '../../design_system/app_tokens.dart';
import '../../design_system/widgets/app_cards.dart';
import 'aggregate_search_page.dart';
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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bootstrapCatalogIfNeeded();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
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

    final controller = context.read<VideoController>();

    if (_scrollController.position.extentAfter < 220 &&
        !controller.isLoading &&
        controller.hasMore) {
      controller.loadMore();
    }
  }

  Future<void> _autoLoadMoreIfNeeded() async {
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

  String _currentCategoryLabel(VideoController controller) {
    final typeId = controller.currentTypeId;
    if (typeId == null) return '全部';

    for (final category in controller.categories) {
      if (category.typeId == typeId) return category.typeName;
    }

    return '分类#$typeId';
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
    final sourceTitle = source?.name ?? '影视内容中心';
    return AppLightHeroCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      eyebrow: '影视聚合首页',
      title: '光影剧场',
      subtitle: '$sourceTitle · $subtitle',
      badge: 'VIDEO',
      accentGradient: AppTokens.violetGradient,
      leading: const _VideoLightIcon(icon: Icons.local_movies_rounded),
      actions: [
        GestureDetector(
          onTap: () => _openCurrentSourceSearch(controller),
          child: const AppStatusPill(
            label: '当前源搜索',
            icon: Icons.search_rounded,
            color: AppTokens.primaryBlue,
          ),
        ),
        GestureDetector(
          onTap: _openAggregateSearch,
          child: const AppStatusPill(
            label: '聚合搜索',
            icon: Icons.public_rounded,
            color: AppTokens.violet,
          ),
        ),
      ],
      metrics: [
        Expanded(
          child: _VideoLightMetric(
            value: '${controller.sources.length}',
            label: '片源',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _VideoLightMetric(
            value: '${controller.videoList.length}',
            label: '影片',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _VideoLightMetric(
            value: _currentCategoryLabel(controller),
            label: '分类',
          ),
        ),
      ],
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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

  Widget _buildQuickAccessSection(
    VideoController controller,
    double screenWidth,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7ECF5)),
        boxShadow: AppTokens.shadowSm(),
      ),
      child: Row(
        children: [
          Expanded(
            child: _VideoQuickPill(
              icon: Icons.swap_horiz_rounded,
              label: '切换片源',
              color: const Color(0xFF0F766E),
              onTap: controller.sources.isEmpty
                  ? null
                  : () => showHomeSourcePickerSheet(context, controller),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _VideoQuickPill(
              icon: Icons.refresh_rounded,
              label: '刷新推荐',
              color: const Color(0xFFFF7A45),
              onTap: _reloadCurrentSource,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySection(VideoController controller) {
    return SafeAnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.only(top: 16.0, bottom: 4.0),
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

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE7ECF5)),
            boxShadow: AppTokens.shadowSm(),
          ),
          child: Row(
            children: [
              Icon(
                Icons.video_camera_back_rounded,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                source == null ? '视频推荐' : source.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 32,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: controller.sources.isEmpty
                      ? null
                      : () => showHomeSourcePickerSheet(context, controller),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                  label: const Text('换源', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
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
      safeTop: false,
      child: RefreshIndicator(
        onRefresh: _reloadCurrentSource,
        child: Center(
          child: SizedBox(
            width: layoutWidth,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(
                  child: _buildHeaderSection(videoController, screenWidth),
                ),
                SliverToBoxAdapter(
                  child: _buildQuickAccessSection(videoController, screenWidth),
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
                SliverToBoxAdapter(
                  child: _buildCategorySection(videoController),
                ),
                SliverToBoxAdapter(
                  child: _buildVideoHeaderSection(videoController),
                ),
                _buildVideoGridSection(videoController, screenWidth),
                SliverToBoxAdapter(
                  child: SafeAnimatedBuilder(
                    animation: videoController,
                    builder: (context, _) =>
                        _buildBottomLoader(videoController),
                  ),
                ),
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

class _VideoLightMetric extends StatelessWidget {
  const _VideoLightMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FD),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        border: Border.all(color: const Color(0xFFE7ECF5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTokens.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppTokens.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoQuickPill extends StatelessWidget {
  const _VideoQuickPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: enabled ? 0.10 : 0.05),
              borderRadius: BorderRadius.circular(AppTokens.radiusPill),
              border: Border.all(color: color.withValues(alpha: 0.18)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: enabled ? color : Colors.grey),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: enabled ? AppTokens.textPrimary : Colors.grey,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
