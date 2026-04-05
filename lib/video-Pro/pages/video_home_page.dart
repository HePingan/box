import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controller/video_controller.dart';
import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../video_module.dart';
import 'video_detail_page.dart';
import 'video_search_page.dart';
import 'aggregate_search_page.dart';
class VideoHomePage extends StatefulWidget {
  const VideoHomePage({super.key});

  @override
  State<VideoHomePage> createState() => _VideoHomePageState();
}

class _VideoHomePageState extends State<VideoHomePage> {
  static const String _fallbackCatalogUrl =
      'https://raw.githubusercontent.com/ZhuBaiwan-oOZZXX/OuonnkiTV-Source/main/tv_source/OuonnkiTV/full-noadult.json';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapCatalog();
    });
  }

  Future<void> _bootstrapCatalog() async {
    final controller = context.read<VideoController>();
    final resolvedUrl = await VideoModule.resolveWorkingCatalogUrl();
    final catalogUrl = resolvedUrl ?? VideoModule.preferredCatalogUrl ?? _fallbackCatalogUrl;

    if (!mounted) return;
    await controller.initSources(catalogUrl);
  }

  Future<void> _refresh(VideoController controller) async {
    if (controller.currentSource == null) {
      await _bootstrapCatalog();
      return;
    }
    await controller.fetchVideoList(isRefresh: true, force: true);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VideoController>();
    final source = controller.currentSource;
    final screenWidth = MediaQuery.of(context).size.width; 

    return Scaffold(
      appBar: AppBar(
        title: Text(
          source == null
              ? VideoModule.catalogName
              : '${VideoModule.catalogName} · ${source.name}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          // 1. 原来的单源搜索（本站搜索）
          IconButton(
            tooltip: '本站搜索',
            icon: const Icon(Icons.search_rounded),
            onPressed: source == null
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VideoSearchPage(currentSource: source),
                      ),
                    );
                  },
          ),
          
          // 2. ✨ 新加的：全网聚合搜索入口！(用一个带地球的搜索图标区分)
          IconButton(
            tooltip: '全网多源搜索',
            icon: const Icon(Icons.travel_explore),
            onPressed: controller.sources.isEmpty
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        // 直接跳转到你之前创建的聚合搜索页
                        builder: (_) => const AggregateSearchPage(),
                      ),
                    );
                  },
          ),
          
          // 3. 原来的切源按钮
          IconButton(
            tooltip: '切换数据源',
            icon: const Icon(Icons.source_rounded),
            onPressed: controller.sources.isEmpty
                ? null
                : () => _showSourcePicker(context, controller),
          ),
        ],
      ),
      body: controller.isLoading && controller.videoList.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _refresh(controller),
              child: controller.videoList.isEmpty
                  ? ListView(
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
                            source == null
                                ? '正在加载视频目录...'
                                : '当前源没有可展示的视频',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    )
                  : GridView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        // 宽屏(网页/平板)显示 6 列，手机显示 3 列，自动适配
                        crossAxisCount: screenWidth > 600 ? 6 : 3,
                        // 调整比例让高度变大，给文字留足空间，彻底告别溢出报错
                        childAspectRatio: 0.55,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: controller.videoList.length,
                      itemBuilder: (context, index) {
                        final video = controller.videoList[index];
                        return _buildVideoCard(context, controller, video);
                      },
                    ),
            ),
    );
  }

  Widget _buildVideoCard(
    BuildContext context,
    VideoController controller,
    VodItem video,
  ) {
    final source = controller.currentSource;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 使用 Expanded 让图片自动填充满除了文字之外的所有剩余高度
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
              title: Text(s.name),
              subtitle: Text(s.url, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: selected ? const Icon(Icons.check_rounded) : null,
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