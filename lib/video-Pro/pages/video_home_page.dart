import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controller/history_controller.dart';
import '../controller/video_controller.dart';
import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../video_module.dart';
import '../widgets/history_quick_view.dart';
import 'aggregate_search_page.dart';
import 'home/home_category_bar.dart';
import 'home/home_empty_state.dart';
import 'home/home_header_section.dart';
import 'home/home_quick_access_grid.dart';
import 'home/home_source_sheet.dart';
import 'home/home_utils.dart';
import 'home/home_video_grid.dart';
import 'video_detail_page.dart';
import 'video_search_page.dart';

class VideoHomePage extends StatefulWidget {
  final String title;
  final bool showHistory;
  final VoidCallback? onSearchTap;

  const VideoHomePage({
    super.key,
    this.title = '视频',
    this.showHistory = true,
    this.onSearchTap,
  });

  @override
  State<VideoHomePage> createState() => _VideoHomePageState();
}

class _VideoHomePageState extends State<VideoHomePage> {
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapCatalogIfNeeded();
    });
  }

  Future<void> _bootstrapCatalogIfNeeded({bool force = false}) async {
    final controller = context.read<VideoController>();

    if (!force &&
        (controller.sources.isNotEmpty || controller.videoList.isNotEmpty)) {
      return;
    }

    final resolvedUrl = await VideoModule.resolveWorkingCatalogUrl();
    final catalogUrl = resolvedUrl ?? kFallbackCatalogUrl;

    if (!mounted) return;
    await controller.initSources(catalogUrl);
  }

  Future<void> _reloadCurrentSource() async {
    final controller = context.read<VideoController>();

    if (controller.currentSource != null) {
      await controller.refreshCurrentSource();
      return;
    }

    await _bootstrapCatalogIfNeeded(force: true);
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



  int _readSafeCount(List<VodItem> list) {
    return list.length;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VideoController>();
    final source = controller.currentSource;
    final screenWidth = MediaQuery.of(context).size.width;

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
      body: NotificationListener<ScrollUpdateNotification>(
        onNotification: (notification) {
          if (notification.metrics.axis == Axis.vertical &&
              notification.metrics.pixels >=
                  notification.metrics.maxScrollExtent - 200 &&
              !controller.isLoading &&
              controller.hasMore) {
            controller.loadMore();
          }
          return false;
        },
        child: RefreshIndicator(
          onRefresh: _reloadCurrentSource,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Container(
                  color: Colors.white,
                  child: HomeHeaderSection(
                    title: 'OuonnkiTV 聚合引擎',
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
                  context.select((HistoryController c) => c.historyList.isNotEmpty))
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: HistoryQuickView(),
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
                              : () => showHomeSourcePickerSheet(context, controller),
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
             // 🚀 直接同步返回：O(1)级开销，干掉 Future！
             coverUrlFor: (video) => source == null ? null : resolveVideoCoverSync(video, source), 
             onTapVideo: (video) {
     // ... 下面都不动
                  if (source == null) return;

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
              if (safeVideoList.isNotEmpty)
                SliverToBoxAdapter(
                  child: _buildBottomLoader(controller),
                ),
            ],
          ),
        ),
      ),
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
}