import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controller/video_controller.dart';
import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../video_module.dart';
import 'video_detail_page.dart';
import '../widgets/history_quick_view.dart';

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
      'https://raw.githubusercontent.com/ZhuBaiwan-oOZZXX/OuonnkiTV-Source/main/tv_source/OuonnkiTV/full-noadult.json';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapCatalogIfNeeded();
    });
  }

  Future<void> _bootstrapCatalogIfNeeded() async {
    final controller = context.read<VideoController>();

    if (controller.sources.isNotEmpty || controller.videoList.isNotEmpty) {
      return;
    }

    final resolvedUrl = await VideoModule.resolveWorkingCatalogUrl();
    final catalogUrl = resolvedUrl ?? VideoModule.preferredCatalogUrl ?? _fallbackCatalogUrl;

    if (!mounted) return;
    await controller.initSources(catalogUrl);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VideoController>();
    final source = controller.currentSource;
    final screenWidth = MediaQuery.of(context).size.width;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _buildHeader(context, controller, source),
        ),

        if (widget.showHistory)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: HistoryQuickView(),
            ),
          ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Text(
                  source == null ? '视频推荐' : '正在浏览 · ${source.name}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: controller.sources.isEmpty
                      ? null
                      : () => _showSourcePicker(context, controller),
                  icon: const Icon(Icons.source_outlined, size: 18),
                  label: const Text('切源'),
                ),
              ],
            ),
          ),
        ),

        if (controller.isLoading && controller.videoList.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (controller.videoList.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildEmptyState(context, controller),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final video = controller.videoList[index];
                  return _VideoCard(
                    video: video,
                    onTap: source == null
                        ? null
                        : () {
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
                  );
                },
                childCount: controller.videoList.length,
              ),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                // 同样做网页宽屏防拉伸和手机端适配
                crossAxisCount: screenWidth > 600 ? 6 : 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.55, // 给底部文字保留充分的绘制空间
              ),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _buildHeader(
    BuildContext context,
    VideoController controller,
    VideoSource? source,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary.withOpacity(0.12),
            Theme.of(context).colorScheme.primary.withOpacity(0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.smart_display_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  source == null
                      ? '正在加载视频源...'
                      : '当前源：${source.name} · 共 ${controller.videoList.length} 条',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: widget.onSearchTap ??
                (source == null
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _VideoSearchBridgePage(currentSource: source),
                          ),
                        );
                      }),
            icon: const Icon(Icons.search_rounded),
            tooltip: '搜索',
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, VideoController controller) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(
          Icons.live_tv_outlined,
          size: 72,
          color: Colors.grey.shade400,
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            controller.currentSource == null
                ? '暂无可用视频源'
                : '当前源暂无视频数据',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 15,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton.icon(
            onPressed: () => _bootstrapCatalogIfNeeded(),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重新加载'),
          ),
        ),
      ],
    );
  }

  void _showSourcePicker(BuildContext context, VideoController controller) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: controller.sources.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final s = controller.sources[index];
            final selected = s.id == controller.currentSource?.id;

            return ListTile(
              leading: Icon(
                selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                color: selected ? Theme.of(context).colorScheme.primary : null,
              ),
              title: Text(s.name),
              subtitle: Text(
                s.url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                controller.setCurrentSource(s);
              },
            );
          },
        );
      },
    );
  }
}

class _VideoCard extends StatelessWidget {
  final VodItem video;
  final VoidCallback? onTap;

  const _VideoCard({
    required this.video,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Expanded 自动撑开，防止文字越界
          Expanded(
            child: SizedBox(
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  // ✨ 加上 Uri.encodeComponent 进行终极安全编码
                  (video.vodPic != null && video.vodPic!.isNotEmpty)
                      ? 'https://images.weserv.nl/?url=${Uri.encodeComponent(video.vodPic!)}'
                      : '',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.grey.shade300,
                    child: const Center(
                      child: Icon(Icons.movie_outlined, size: 30),
                    ),
                  ),
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      color: Colors.grey.shade200,
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            video.vodName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            video.vodRemarks ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoSearchBridgePage extends StatelessWidget {
  final VideoSource currentSource;

  const _VideoSearchBridgePage({
    required this.currentSource,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: Center(
        child: Text(
          '请在项目中接入你的 VideoSearchPage。\n当前源：${currentSource.name}',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}