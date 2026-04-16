import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controller/history_controller.dart';
import '../controller/video_controller.dart';
import '../models/video_source.dart';
import '../video_module.dart';
import '../widgets/history_quick_view.dart';
import 'aggregate_search_page.dart';
import 'home/home_category_bar.dart';
import 'home/home_quick_access_grid.dart';
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
  static const String _fallbackCatalogUrl =
      'https://proxy.shuabu.eu.org?format=0&source=jin18';

  final ScrollController _scrollController = ScrollController();
  VideoController? _videoController;
  bool _autoLoadMoreRunning = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _videoController = context.read<VideoController>();
      _videoController?.addListener(_onControllerChanged);

      _bootstrapCatalogIfNeeded();
    });
  }

  @override
  void dispose() {
    _videoController?.removeListener(_onControllerChanged);
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

    // 关键兜底：
    // 如果 initSources 只加载了片源，但没有自动拉视频，这里补一次刷新
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

  void _onControllerChanged() {
    if (!mounted) return;
    _autoLoadMoreIfNeeded();
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

      for (int i = 0; i < safetyLimit; i++) {
        if (!mounted) break;

        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) break;

        if (!_scrollController.hasClients) continue;

        final controller = context.read<VideoController>();
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

  Future<void> _openCurrentSourceSearch() async {
    final controller = context.read<VideoController>();
    final source = controller.currentSource;
    if (source == null) return;

    if (widget.onSearchTap != null) {
      widget.onSearchTap!.call();
      return;
    }

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoSearchPage(currentSource: source),
      ),
    );
  }

  Future<void> _openAggregateSearch() async {
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AggregateSearchPage(),
      ),
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

  VideoSource? _findSourceById(List<VideoSource> sources, String sourceId) {
    for (final source in sources) {
      if (source.id == sourceId) return source;
    }
    return null;
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildBottomLoader(VideoController controller) {
    if (controller.videoList.isEmpty) return const SizedBox.shrink();

    if (!controller.hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            '—— 已经到底啦 ——',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 13,
            ),
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

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VideoController>();
    final source = controller.currentSource;
    final screenWidth = MediaQuery.of(context).size.width;
    final layoutWidth = screenWidth >= 700 ? 560.0 : screenWidth;

    final safeVideoList = controller.videoList.where((video) {
      return isSafeContent(video.typeName) && isSafeContent(video.vodName);
    }).toList(growable: false);

    final hasRawVideos = controller.videoList.isNotEmpty;

    final emptyMessage = source == null
        ? '暂无可用视频源'
        : hasRawVideos
            ? '当前内容已被安全过滤\n请尝试切换其他分类或片源'
            : '站长没有往这个分类里放视频哦~\n请尝试在上方选择其他实体分类';

    final headerSubtitle = source == null
        ? (controller.sources.isEmpty ? '暂无可用片源' : '加载中...')
        : '已接入 ${controller.sources.length} 个片源核心，提供绿色净化服务';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 50,
        actions: [
          IconButton(
            tooltip: '当前源搜索',
            onPressed: source == null ? null : _openCurrentSourceSearch,
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            tooltip: '聚合搜索',
            onPressed: _openAggregateSearch,
            icon: const Icon(Icons.public_rounded),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _reloadCurrentSource,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reloadCurrentSource,
        child: Center(
          child: SizedBox(
            width: layoutWidth,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                    child: _buildHeaderCard(
                      context,
                      controller: controller,
                      source: source,
                      subtitle: headerSubtitle,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.only(bottom: 12),
                    child: HomeQuickAccessGrid(
                      controller: controller,
                      screenWidth: screenWidth,
                    ),
                  ),
                ),
                if (widget.showHistory &&
                    context.select<HistoryController, bool>(
                      (history) => history.historyList.isNotEmpty,
                    ))
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
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16.0, bottom: 4.0),
                    child: HomeCategoryBar(controller: controller),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 12, 8),
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
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
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
                                : () => showHomeSourcePickerSheet(
                                      context,
                                      controller,
                                    ),
                            icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                            label: const Text(
                              '换源',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                HomeVideoSliverGrid(
                  videos: safeVideoList,
                  screenWidth: screenWidth,
                  isLoading: controller.isLoading,
                  coverUrlFor: (video) =>
                      source == null ? null : resolveVideoCoverSync(video, source),
                  onTapVideo: (video) {
                    if (source == null) {
                      _showSnackBar('暂无可用片源');
                      return;
                    }

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VideoDetailPage(
                          source: source,
                          vodId: video.vodId,
                        ),
                      ),
                    );
                  },
                  emptyMessage: emptyMessage,
                  emptyActionLabel: '刷新重试',
                  onEmptyAction: _reloadCurrentSource,
                ),
                SliverToBoxAdapter(
                  child: _buildBottomLoader(controller),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(
    BuildContext context, {
    required VideoController controller,
    required VideoSource? source,
    required String subtitle,
  }) {
    final theme = Theme.of(context);
    final sourceTitle = source?.name ?? widget.title;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.smart_display_rounded,
              color: theme.colorScheme.primary,
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sourceTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoChip(
                      icon: Icons.hub_rounded,
                      label: '${controller.sources.length} 源',
                    ),
                    _InfoChip(
                      icon: Icons.video_library_outlined,
                      label: '${controller.videoList.length} 条',
                    ),
                    _InfoChip(
                      icon: Icons.category_outlined,
                      label: _currentCategoryLabel(controller),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (controller.sources.isNotEmpty)
            TextButton.icon(
              onPressed: () => showHomeSourcePickerSheet(context, controller),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                minimumSize: const Size(0, 38),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: const Text(
                '换源',
                style: TextStyle(fontSize: 12.5),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12.5,
            color: Colors.grey.shade600,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}