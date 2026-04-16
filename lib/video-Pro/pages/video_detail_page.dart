import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../pages/debug_log_page.dart';
import '../controller/video_detail_controller.dart';
import '../models/video_source.dart';
import '../widgets/video_play_container.dart';
import 'detail/detail_episode_section.dart';
import 'detail/detail_info_card.dart';
import 'detail/detail_line_selector.dart';
import 'detail/detail_play_parser.dart';

class VideoDetailPage extends StatelessWidget {
  final VideoSource source;
  final int vodId;
  final String? initialEpisodeUrl;
  final int initialPosition;

  const VideoDetailPage({
    super.key,
    required this.source,
    required this.vodId,
    this.initialEpisodeUrl,
    this.initialPosition = 0,
  });

  @override
  Widget build(BuildContext context) {
    // 注入我们刚写的控制器
    return ChangeNotifierProvider(
      create: (_) => VideoDetailController(
        source: source,
        vodId: vodId,
        initialEpisodeUrl: initialEpisodeUrl,
        initialPosition: initialPosition,
      ),
      child: const _VideoDetailView(),
    );
  }
}

class _VideoDetailView extends StatefulWidget {
  const _VideoDetailView();

  @override
  State<_VideoDetailView> createState() => _VideoDetailViewState();
}

class _VideoDetailViewState extends State<_VideoDetailView> {
  
  @override
  void initState() {
    super.initState();
    // 监听消息：历史续播弹窗
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = context.read<VideoDetailController>();
      controller.addListener(() {
        if (controller.resumeMessage != null && mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text(controller.resumeMessage!), duration: const Duration(seconds: 2)),
           );
           controller.consumeResumeMessage(); // 消费消息防止重复弹出
        }
      });
    });
  }

  void _openDebugLogPage() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DebugLogPage()));
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VideoDetailController>();
    final title = controller.fullDetail?.vodName ?? controller.source.name;

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            tooltip: '调试日志',
            onPressed: _openDebugLogPage,
            icon: const Icon(Icons.bug_report_outlined),
          ),
          IconButton(
            tooltip: '重新加载',
            onPressed: controller.isLoading ? null : controller.loadDetail,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: controller.isLoading
          ? const Center(child: CircularProgressIndicator())
          : (controller.fullDetail == null ? _buildErrorView(controller) : _buildDetailView(controller)),
    );
  }
Widget _buildDetailView(VideoDetailController controller) {
  final detail = controller.fullDetail!;
  final coverUrl = DetailPlayParser.resolveImageUrl(
    detail.vodPic,
    source: controller.source,
  );
  final totalEpisodes = controller.playLines.fold<int>(
    0,
    (sum, line) => sum + line.episodes.length,
  );

  return LayoutBuilder(
    builder: (context, constraints) {
      // 桌面端限制内容宽度，手机端保持原宽度
      final contentWidth = constraints.maxWidth >= 1100
          ? 920.0
          : constraints.maxWidth >= 900
              ? 760.0
              : constraints.maxWidth >= 600
                  ? 560.0
                  : constraints.maxWidth;

      return RefreshIndicator(
        onRefresh: controller.loadDetail,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Center(
              child: SizedBox(
                width: contentWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      color: Colors.black,
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: controller.currentEpisodeUrl != null
                            ? VideoPlayContainer(
                                key: ValueKey<String>(
                                  '${controller.currentEpisodeUrl!}_${controller.selectedLineIndex}_${controller.selectedEpisodeIndex}',
                                ),
                                url: controller.currentEpisodeUrl!,
                                title: detail.vodName,
                                vodId: controller.vodId.toString(),
                                vodPic: detail.vodPic ?? '',
                                sourceId: controller.source.id,
                                sourceName: controller.source.name,
                                episodeName:
                                    controller.currentEpisodeName ?? '正片',
                                initialPosition:
                                    controller.getEffectiveInitialPosition(),
                                referer: controller.source.detailUrl.isNotEmpty
                                    ? controller.source.detailUrl
                                    : controller.source.url,
                                showDebugInfo: false,
                                onPreviousEpisode: controller.canPlayPrevious()
                                    ? controller.playPrevious
                                    : null,
                                onNextEpisode: controller.canPlayNext()
                                    ? controller.playNext
                                    : null,
                              )
                            : const Center(
                                child: Text(
                                  '无可播放资源',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: DetailInfoCard(
                        detail: detail,
                        source: controller.source,
                        coverUrl: coverUrl,
                        lineCount: controller.playLines.length,
                        totalEpisodeCount: totalEpisodes,
                        currentEpisodeName:
                            controller.currentEpisodeName ?? '未选择',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: controller.playLines.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(child: Text('暂无选集数据')),
                            )
                          : Column(
                              children: [
                                if (controller.playLines.length > 1) ...[
                                  DetailLineSelector(
                                    playLines: controller.playLines,
                                    selectedIndex: controller.selectedLineIndex,
                                    onSelected: controller.selectLine,
                                  ),
                                  const SizedBox(height: 4),
                                ],
                                DetailEpisodeSection(
                                  episodes: controller.playLines[
                                          controller.selectedLineIndex]
                                      .episodes,
                                  currentIndex: controller.selectedEpisodeIndex,
                                  onEpisodeTap: controller.selectEpisode,
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

  Widget _buildErrorView(VideoDetailController controller) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(Icons.error_outline_rounded, size: 72, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        Center(
          child: Text(
            controller.errorMessage ?? '视频详情加载失败',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 15),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton.icon(
             onPressed: controller.loadDetail,
             icon: const Icon(Icons.refresh_rounded), 
             label: const Text('重试')
          ),
        )
      ],
    );
  }
}