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
  VideoDetailController? _controller;
  VoidCallback? _controllerListener;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _attachControllerListener();
    });
  }

  void _attachControllerListener() {
    if (_controllerListener != null) return;

    final controller = context.read<VideoDetailController>();
    _controller = controller;

    _controllerListener = () {
      if (!mounted) return;

      final message = controller.resumeMessage;
      if (message != null && message.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 2),
          ),
        );
        controller.consumeResumeMessage();
      }
    };

    controller.addListener(_controllerListener!);
  }

  @override
  void dispose() {
    if (_controller != null && _controllerListener != null) {
      _controller!.removeListener(_controllerListener!);
    }
    super.dispose();
  }

  void _openDebugLogPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const DebugLogPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VideoDetailController>();
    final detailTitle = controller.fullDetail?.vodName?.trim();
    final title = (detailTitle != null && detailTitle.isNotEmpty)
        ? detailTitle
        : controller.source.name;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: '调试日志',
            onPressed: _openDebugLogPage,
            icon: const Icon(Icons.bug_report_outlined),
          ),
          IconButton(
            tooltip: '重新加载',
            onPressed: controller.isLoading
                ? null
                : () {
                    controller.loadDetail();
                  },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: controller.isLoading
          ? const Center(child: CircularProgressIndicator())
          : (controller.fullDetail == null
              ? _buildErrorView(controller)
              : _buildDetailView(controller)),
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
        final contentWidth = constraints.maxWidth >= 1100
            ? 920.0
            : constraints.maxWidth >= 900
                ? 760.0
                : constraints.maxWidth >= 600
                    ? 560.0
                    : constraints.maxWidth;

        return RefreshIndicator(
          onRefresh: () async {
            await Future.sync(controller.loadDetail);
          },
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
                                  title: detail.vodName ?? controller.source.name,
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
                                    episodes: controller
                                        .playLines[controller.selectedLineIndex]
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
        Icon(
          Icons.error_outline_rounded,
          size: 72,
          color: Colors.grey.shade400,
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            controller.errorMessage ?? '视频详情加载失败',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 15,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton.icon(
            onPressed: () {
              controller.loadDetail();
            },
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重试'),
          ),
        ),
      ],
    );
  }
}