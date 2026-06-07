import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controller/video_detail_controller.dart';
import '../models/video_source.dart';
import '../widgets/video_play_container.dart';
import 'detail/detail_info_card.dart';
import 'detail/detail_models.dart';
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

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VideoDetailController>();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
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
        final horizontal = constraints.maxWidth < 430 ? 12.0 : 16.0;
        final title = detail.vodName.trim().isNotEmpty
            ? detail.vodName.trim()
            : controller.source.name;

        return RefreshIndicator(
          onRefresh: () async {
            await Future.sync(controller.loadDetail);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 28),
            children: [
              Center(
                child: SizedBox(
                  width: contentWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildCompactMediaHeader(
                        controller: controller,
                        coverUrl: coverUrl,
                        title: title,
                        totalEpisodes: totalEpisodes,
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontal,
                          10,
                          horizontal,
                          0,
                        ),
                        child: _buildPlayerShell(controller, detail),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: horizontal),
                        child: controller.playLines.isEmpty
                            ? _buildEmptyEpisodePanel()
                            : _buildPlaybackPanel(
                                controller: controller,
                                totalEpisodes: totalEpisodes,
                              ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: horizontal),
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
                      const SizedBox(height: 36),
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

  Widget _buildPlayerShell(VideoDetailController controller, dynamic detail) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF080A1F),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF020617).withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
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
                episodeName: controller.currentEpisodeName ?? '正片',
                initialPosition: controller.getEffectiveInitialPosition(),
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
            : const AspectRatio(
                aspectRatio: 16 / 9,
                child: ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: Text(
                      '无可播放资源',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildPlaybackPanel({
    required VideoDetailController controller,
    required int totalEpisodes,
  }) {
    final episodes =
        controller.playLines[controller.selectedLineIndex].episodes;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7ECF5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF111827).withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFE08A), Color(0xFFFB923C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Color(0xFF111827),
                  size: 24,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '播放面板 · 播放器优先版',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${controller.currentEpisodeName ?? '待选集'} · ${controller.source.name} · $totalEpisodes 集',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 38,
                height: 38,
                child: IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    padding: EdgeInsets.zero,
                    backgroundColor: const Color(0xFFF1F5F9),
                    foregroundColor: const Color(0xFF475569),
                  ),
                  onPressed: controller.isLoading
                      ? null
                      : controller.loadDetail,
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                ),
              ),
            ],
          ),
          if (controller.playLines.length > 1) ...[
            const SizedBox(height: 12),
            _buildPanelLabel(Icons.hub_rounded, '线路'),
            const SizedBox(height: 8),
            _buildLineChips(
              playLines: controller.playLines,
              selectedIndex: controller.selectedLineIndex,
              onSelected: controller.selectLine,
            ),
          ],
          const SizedBox(height: 12),
          _buildPanelLabel(Icons.grid_view_rounded, '剧集'),
          const SizedBox(height: 8),
          _buildEpisodeChips(
            episodes: episodes,
            currentIndex: controller.selectedEpisodeIndex,
            onEpisodeTap: controller.selectEpisode,
          ),
        ],
      ),
    );
  }

  Widget _buildPanelLabel(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF6D28D9)),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            color: Color(0xFF334155),
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _buildLineChips({
    required List<DetailPlayLine> playLines,
    required int selectedIndex,
    required ValueChanged<int> onSelected,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: List.generate(playLines.length, (index) {
          final line = playLines[index];
          final selected = index == selectedIndex;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _PlaybackChip(
              label: line.name,
              selected: selected,
              onTap: () => onSelected(index),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildEpisodeChips({
    required List<DetailPlayEpisode> episodes,
    required int currentIndex,
    required ValueChanged<int> onEpisodeTap,
  }) {
    if (episodes.isEmpty) {
      return const Text(
        '当前线路暂无可播放集数',
        style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: List.generate(episodes.length, (index) {
          final episode = episodes[index];
          final selected = index == currentIndex;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _PlaybackChip(
              label: episode.name,
              selected: selected,
              onTap: () => onEpisodeTap(index),
              minWidth: 76,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildEmptyEpisodePanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7ECF5)),
      ),
      child: const Center(
        child: Text(
          '暂无选集数据',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildCompactMediaHeader({
    required VideoDetailController controller,
    required String? coverUrl,
    required String title,
    required int totalEpisodes,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF080A1F), Color(0xFF4C1D95), Color(0xFF7C2D12)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6D28D9).withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _HeroIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: () => Navigator.maybePop(context),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE08A).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFFFFE08A).withValues(alpha: 0.24),
                    ),
                  ),
                  child: const Text(
                    '播放器优先版',
                    style: TextStyle(
                      color: Color(0xFFFFE08A),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _HeroIconButton(
                  icon: Icons.refresh_rounded,
                  onTap: controller.isLoading ? null : controller.loadDetail,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (coverUrl != null && coverUrl.trim().isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: Image.network(
                      coverUrl,
                      width: 58,
                      height: 82,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          height: 1.10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${controller.source.name} · $totalEpisodes 集 · ${controller.playLines.length} 线路',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
            style: TextStyle(color: Colors.grey.shade700, fontSize: 15),
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

class _PlaybackChip extends StatelessWidget {
  const _PlaybackChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.minWidth,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double? minWidth;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: BoxConstraints(minWidth: minWidth ?? 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFFFFE08A), Color(0xFFFB923C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: selected ? null : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? Colors.transparent : const Color(0xFFE7ECF5),
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? const Color(0xFF111827) : const Color(0xFF475569),
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _HeroIconButton extends StatelessWidget {
  const _HeroIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}
