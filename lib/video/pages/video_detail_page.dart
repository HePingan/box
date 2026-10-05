import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:box/design_system/widgets/app_page_scaffold.dart';

import '../controller/favorites_controller.dart';
import '../controller/video_detail_controller.dart';
import '../controller/video_download_controller.dart';
import '../models/video_source.dart';
import '../widgets/download/video_download_bottom_sheet.dart';
import '../widgets/video_play_container.dart';
import 'detail/detail_info_card.dart';
import 'detail/detail_models.dart';
import '../../design_system/app_tokens.dart';
import '../../design_system/widgets/app_section_title.dart';

class VideoDetailPage extends StatelessWidget {
  final VideoSource source;
  final int vodId;
  final String? initialEpisodeUrl;
  final int initialPosition;
  final String? localPath;
  final bool isOfflinePlayback;
  final String? episodeName;

  /// 跨源续播：原片源那集的剧集名（`HD中字` / `第03集`）。
  /// 换了片源后地址必然不同，只能按剧集名把用户带回同一集。
  final String? initialEpisodeName;
  final int localFileExpectedBytes;

  const VideoDetailPage({
    super.key,
    required this.source,
    required this.vodId,
    this.initialEpisodeUrl,
    this.initialPosition = 0,
    this.localPath,
    this.isOfflinePlayback = false,
    this.episodeName,
    this.initialEpisodeName,
    this.localFileExpectedBytes = 0,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => VideoDetailController(
        source: source,
        vodId: vodId,
        initialEpisodeUrl: initialEpisodeUrl,
        initialPosition: initialPosition,
        localPath: localPath,
        isOfflinePlayback: isOfflinePlayback,
        episodeName: episodeName,
        initialEpisodeName: initialEpisodeName,
        localFileExpectedBytes: localFileExpectedBytes,
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

  // 剧集面板本地视图状态：分段(-1=跟随当前集)、展开全部、倒序。
  static const int _episodeSegmentSize = 50;
  int _episodeSegment = -1;
  bool _episodesExpanded = false;
  bool _episodesReversed = false;

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

    return AppPageScaffold(
      child: controller.isLoading
          ? _buildLoadingView()
          : (controller.fullDetail == null
                ? _buildErrorView(controller)
                : _buildDetailView(controller)),
    );
  }

  Widget _buildDetailView(VideoDetailController controller) {
    final detail = controller.fullDetail!;

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
                        title: title,
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontal,
                          AppTokens.spaceMd,
                          horizontal,
                          0,
                        ),
                        child: _buildPlayerShell(controller, detail),
                      ),
                      // ③ 区块间距统一到 spaceMd(12)：原来是 10/10/12/36 各写各的。
                      const SizedBox(height: AppTokens.spaceMd),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: horizontal),
                        child: controller.playLines.isEmpty
                            ? _buildEmptyEpisodePanel()
                            : _buildPlaybackPanel(controller: controller),
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: horizontal),
                        child: DetailInfoCard(
                          detail: detail,
                          source: controller.source,
                        ),
                      ),
                      const SizedBox(height: AppTokens.space2xl),
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

  /// ⑤ 起播可见化：把播放器想说的话（换线路 / 起播过慢）变成一条提示。
  /// 页面是 StatelessWidget，所以在这里把 messenger 抓稳；取不到就静默跳过，
  /// 绝不因为一句提示影响播放。
  void Function(String message)? _noticeVia(BuildContext context) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return null;
    return (message) {
      messenger
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
    };
  }

  Widget _buildPlayerShell(VideoDetailController controller, dynamic detail) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF080A1F),
        // ⑦ 圆角统一到 20（原先播放器 22 / 内层 18 / 卡片 20 三套）；
        // 阴影只留给播放器 —— 它是这一屏的主体，卡片一律扁平描边。
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF020617).withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child:
            controller.currentEpisodeUrl != null ||
                (controller.isOfflinePlayback &&
                    controller.currentLocalPath != null)
            ? VideoPlayContainer(
                key: ValueKey<String>(
                  controller.isOfflinePlayback
                      ? 'offline_${controller.currentLocalPath}'
                      : '${controller.currentEpisodeUrl!}_${controller.selectedLineIndex}_${controller.selectedEpisodeIndex}',
                ),
                url: controller.currentEpisodeUrl ?? '',
                title: detail.vodName,
                vodId: controller.vodId.toString(),
                vodPic: detail.vodPic ?? '',
                sourceId: controller.source.id,
                sourceName: controller.source.name,
                episodeName: controller.currentEpisodeName ?? '正片',
                initialPosition: controller.getEffectiveInitialPosition(),
                localPath: controller.currentLocalPath,
                localFileExpectedBytes: controller.expectedLocalFileBytes,
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
                onFallbackLine:
                    controller.findFallbackLineIndex(
                          excludingLineIndex: controller.selectedLineIndex,
                        ) ==
                        null
                    ? null
                    : () {
                        final fallback = controller.findFallbackLineIndex(
                          excludingLineIndex: controller.selectedLineIndex,
                        );
                        if (fallback != null) {
                          controller.selectFallbackLine(fallback);
                        }
                      },
                // ③ 下一集的地址：播放时顺手预热，切集/自动续播就不用再等解析。
                nextEpisodeUrl: controller.nextEpisodeRawUrl,
                // ⑤ 起播可见化：换线路 / 起播过慢时把原因说一句。
                onNotice: _noticeVia(context),
                // ② 起播成功 → 清掉这条线路的「上次没取到流」标记。
                onPlaybackStarted: () =>
                    unawaited(controller.markCurrentLineStarted()),
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

  Widget _buildPlaybackPanel({required VideoDetailController controller}) {
    final episodes =
        controller.playLines[controller.selectedLineIndex].episodes;

    final isSingleEpisode = episodes.length == 1;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        12,
        isSingleEpisode ? 8 : 12,
        12,
        // ⑤ 卡底 9→8：截图里两行贴得紧、卡底反而空，把差值匀一点。
        isSingleEpisode ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(20),
        // B5：扁平次级卡，无阴影，只用浅描边，视觉主体让给上方播放器。
        border: Border.all(color: AppTokens.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A3：历史进度断点轻提示条——上次播放位置 + 百分比，可关闭。
          if (controller.resumeMessage != null && !isSingleEpisode) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE08A).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.history_rounded,
                    size: 14,
                    color: Color(0xFF92400E),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      controller.resumeMessage!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF92400E),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => controller.consumeResumeMessage(),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: Color(0xFF92400E),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ② 与「影片资料」「剧情简介」共用同一个标题件
                    // （原先这里是纯文字 14/w800，另两处是 15/w900 + 橙竖条，
                    // 同一屏两种标题风格）。
                    const AppSectionTitle('选集'),
                    // ① 单片时不再重复：下方那个橙色剧集胶囊本身就是「正在播放」，
                    // 标题下面再写一遍「正在播放 · HD中字」纯属重复。
                    if (!isSingleEpisode) ...[
                      const SizedBox(height: 3),
                      // A3：副标题降级——更小字号、更弱字重与颜色，
                      // 只作轻提示，不与「选集」大标题抢层级。
                      Text(
                        controller.currentEpisodeName == null
                            ? '待选集'
                            : '正在播放 · ${controller.currentEpisodeName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTokens.textTertiary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // ① 原先这里还有一个刷新按钮，和顶部导航的刷新是同一个动作
              // （都调 controller.loadDetail）—— 同一屏两个入口，删掉这个。
            ],
          ),
          if (controller.playLines.length > 1) ...[
            const SizedBox(height: AppTokens.spaceMd),
            // ② 线路 / 剧集两行共用同一个左侧标签列（_LabeledRow），
            // 两行内容左边缘因此对齐 —— 原来是「线路」行有图标+文字、
            // 剧集行直接铺满，起点差约 54px，看着错位。
            // chip 仍可横向滚动，长线路名不会挤压或换行。
            _LabeledRow(
              label: '线路',
              child: _buildLineChips(
                playLines: controller.playLines,
                selectedIndex: controller.selectedLineIndex,
                onSelected: controller.selectLine,
                isUnreachable: controller.isLineRecentlyUnreachable,
              ),
            ),
          ],
          const SizedBox(height: AppTokens.spaceMd),
          _LabeledRow(
            label: '剧集',
            topPadding: 6,
            child: _buildEpisodeSection(
              episodes: episodes,
              currentIndex: controller.selectedEpisodeIndex,
              onEpisodeTap: controller.selectEpisode,
            ),
          ),
        ],
      ),
    );
  }

  void _syncEpisodeViewport(int currentIndex, int segmentCount) {
    final targetSegment = currentIndex ~/ _episodeSegmentSize;
    final safeSegment = targetSegment.clamp(0, segmentCount - 1).toInt();
    if (_episodeSegment == safeSegment) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _episodeSegment == safeSegment) return;
      setState(() {
        _episodeSegment = safeSegment;
        _episodesExpanded = false;
      });
    });
  }

  /// 剧集区：标签行(含正倒序 + 展开/收起) + 长剧集分段跳转 + 自适应网格。
  Widget _buildEpisodeSection({
    required List<DetailPlayEpisode> episodes,
    required int currentIndex,
    required ValueChanged<int> onEpisodeTap,
  }) {
    if (episodes.isEmpty) {
      // A2：标准空态——图标 + 说明，与整卡空态风格统一。
      return _buildEpisodeEmptyState('当前线路暂无可播放集数');
    }

    final total = episodes.length;
    final isSingleEpisode = total == 1;
    final segmentCount = (total / _episodeSegmentSize).ceil();
    final hasSegments = segmentCount > 1;

    // B1：外部“上一集/下一集”导致当前集跨段时，面板自动跟随到所在分段。
    // 通过 post-frame 更新，避免在 build 阶段触发 setState。
    _syncEpisodeViewport(currentIndex, segmentCount);

    // 当前生效分段：-1 表示跟随当前播放集。
    final activeSegment = _episodeSegment >= 0 && _episodeSegment < segmentCount
        ? _episodeSegment
        : (currentIndex ~/ _episodeSegmentSize);

    final segStart = activeSegment * _episodeSegmentSize;
    final segEnd = (segStart + _episodeSegmentSize).clamp(0, total);

    // 该分段内的索引序列，按正倒序排列。
    final indices = <int>[for (var i = segStart; i < segEnd; i++) i];
    if (_episodesReversed) {
      indices.sort((a, b) => b.compareTo(a));
    }

    // 收起时只展示有限数量，避免长剧集撑爆页面。
    const collapsedLimit = 24;
    final needCollapse = indices.length > collapsedLimit;
    final visibleIndices = (!_episodesExpanded && needCollapse)
        ? indices.take(collapsedLimit).toList()
        : indices;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ②「剧集」二字已由外层 _LabeledRow 统一给出，这里只留计数与排序/展开这类工具，
        // 保证与上一行的线路 chip 同起点。
        Row(
          children: [
            if (!isSingleEpisode)
              Text(
                '共 $total 集',
                style: TextStyle(
                  color: AppTokens.textTertiary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            const Spacer(),
            if (!isSingleEpisode)
              _EpisodeToolButton(
                icon: _episodesReversed
                    ? Icons.south_rounded
                    : Icons.north_rounded,
                label: _episodesReversed ? '倒序' : '正序',
                onTap: () =>
                    setState(() => _episodesReversed = !_episodesReversed),
              ),
          ],
        ),
        if (hasSegments) ...[
          // B1：长剧集分段当前位置标签——当分段数 > 2 时显示。
          if (segmentCount > 2) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.location_on_rounded,
                  size: 14,
                  color: Color(0xFFFB923C),
                ),
                const SizedBox(width: 4),
                Text(
                  '当前位置：第 ${currentIndex + 1} 集',
                  style: const TextStyle(
                    color: Color(0xFFFB923C),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 4),
          ],
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: List.generate(segmentCount, (seg) {
                final start = seg * _episodeSegmentSize + 1;
                final end = ((seg + 1) * _episodeSegmentSize).clamp(0, total);
                final selected = seg == activeSegment;
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: _SegmentTab(
                    label: '$start-$end',
                    selected: selected,
                    onTap: () => setState(() {
                      _episodeSegment = seg;
                      _episodesExpanded = false;
                    }),
                  ),
                );
              }),
            ),
          ),
        ],
        SizedBox(height: isSingleEpisode ? 0 : 10),
        // A1：等宽宫格。按容器宽度算列数（每格目标约 72px），
        // 每格等宽居中，避免集名长短导致的参差右边界。
        LayoutBuilder(
          builder: (context, constraints) {
            // ② 网格现在缩在标签列右边（可用宽度少 38px），
            // 格子目标宽度 72 → 62、列数下限 4 → 3，窄屏也还是整齐的等宽宫格。
            const spacing = 8.0;
            final columns = ((constraints.maxWidth + spacing) / (62 + spacing))
                .floor()
                .clamp(3, 8);
            final cellWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final index in visibleIndices)
                  SizedBox(
                    width: cellWidth,
                    child: _EpisodeCell(
                      label: episodes[index].name,
                      selected: index == currentIndex,
                      onTap: () => onEpisodeTap(index),
                    ),
                  ),
              ],
            );
          },
        ),
        if (needCollapse) ...[
          const SizedBox(height: 10),
          Center(
            child: _EpisodeToolButton(
              icon: _episodesExpanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              label: _episodesExpanded ? '收起' : '展开全部 (${indices.length})',
              onTap: () =>
                  setState(() => _episodesExpanded = !_episodesExpanded),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLineChips({
    required List<DetailPlayLine> playLines,
    required int selectedIndex,
    required ValueChanged<int> onSelected,
    required bool Function(int index) isUnreachable,
  }) {
    return SizedBox(
      // ③ 行高 42 → 34：只有两三条线路时，原来那行显得空荡，
      // 现在与下方剧集胶囊的高度基本齐平，两行看着是一个整体。
      height: 34,
      child: SingleChildScrollView(
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
                // ② 前置标注：这条线最近取不到流（默认也不会选它），
                // 免得用户点进去先卡一次、再被自动换线。
                unreachable: isUnreachable(index),
                onTap: () => onSelected(index),
              ),
            );
          }),
        ),
      ),
    );
  }

  /// A2：剧集区标准空态——居中图标 + 说明文字，供内联空态与整卡空态复用。
  Widget _buildEpisodeEmptyState(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_rounded, size: 40, color: Color(0xFFCBD5E1)),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTokens.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyEpisodePanel() {
    // A2：整卡空态复用统一的图标+说明空态。
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTokens.cardBorder),
      ),
      child: _buildEpisodeEmptyState('暂无选集数据'),
    );
  }

  Widget _buildCompactMediaHeader({
    required VideoDetailController controller,
    required String title,
  }) {
    // 清新版：白底轻卡，浅边框 + 弱阴影，与首页统一；去掉深色三段渐变与内部版本角标。
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTokens.cardBorder),
        boxShadow: AppTokens.shadowSm(),
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
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTokens.textPrimary,
                      fontSize: 17,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _HeroIconButton(
                  icon: controller.isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  highlight: controller.isFavorite,
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final favorites = context.read<FavoritesController>();
                    await controller.toggleFavorite();
                    await favorites.load();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          controller.isFavorite ? '已加入追剧' : '已取消追剧',
                        ),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 6),
                _HeroIconButton(
                  icon: Icons.refresh_rounded,
                  onTap: controller.isLoading ? null : controller.loadDetail,
                ),
                const SizedBox(width: 6),
                _HeroIconButton(
                  icon: Icons.file_download_rounded,
                  onTap: controller.playLines.isEmpty || controller.isLoading
                      ? null
                      : () => _openDownloadSheet(context, controller),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.only(left: 44),
              child: Text(
                // ⑥ 线路数也不在这里写了：正下方选集卡里就列着两条线路，
                // 这里再报一次「2 线路」还是同一件事说两遍；集数与线路数都交给选集卡。
                controller.source.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppTokens.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // B6：加载态——居中转圈 + 提示，替掉裸 CircularProgressIndicator。
  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(strokeWidth: 2.6),
          ),
          SizedBox(height: 14),
          Text(
            '加载中…',
            style: TextStyle(
              color: AppTokens.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // B6：错误态对齐扁平卡片风格——浅描边卡内居中图标 + 文案 + 重试。
  void _openDownloadSheet(
    BuildContext context,
    VideoDetailController controller,
  ) async {
    // ModalBottomSheet 会进入 Navigator 的新 Route，builder 的 context 不会继承
    // VideoDetailPage 内部创建的 VideoDetailController / VideoDownloadController。
    // 显式向新 Route 透传当前实例，否则下载选集弹窗的 _load() / _enqueueSelected()
    // 会 ProviderNotFound 后永久停在 loading。
    final detailController = context.read<VideoDetailController>();
    final downloadController = context.read<VideoDownloadController>();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MultiProvider(
        providers: [
          ChangeNotifierProvider<VideoDetailController>.value(
            value: detailController,
          ),
          ChangeNotifierProvider<VideoDownloadController>.value(
            value: downloadController,
          ),
        ],
        child: const VideoDownloadBottomSheet(),
      ),
    );
  }

  Widget _buildErrorView(VideoDetailController controller) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 120, 12, 12),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
          decoration: BoxDecoration(
            color: AppTokens.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTokens.cardBorder),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 56,
                color: Color(0xFFCBD5E1),
              ),
              const SizedBox(height: 14),
              Text(
                controller.errorMessage ?? '视频详情加载失败',
                style: TextStyle(
                  color: AppTokens.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              _EpisodeToolButton(
                icon: Icons.refresh_rounded,
                label: '重试',
                onTap: controller.loadDetail,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// ② 统一的「左侧标签列 + 右侧内容」行。
///
/// 线路行与剧集行都用它，两行内容因此从同一个 x 起点开始 —— 此前线路行是
/// [图标 + 「线路」 + chip]，剧集行直接铺满整宽，两行起点差约 54px，看着错位。
/// 标签固定 38px 宽、比内容略小的字号，只做归类提示，不与 chip 抢层级。
class _LabeledRow extends StatelessWidget {
  const _LabeledRow({
    required this.label,
    required this.child,
    this.topPadding = 9,
  });

  final String label;
  final Widget child;

  /// 让标签视觉上和右侧第一行内容（chip / 胶囊）对齐，而不是贴着行顶。
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 38,
          child: Padding(
            padding: EdgeInsets.only(top: topPadding),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTokens.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _PlaybackChip extends StatelessWidget {
  const _PlaybackChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.unreachable = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// ② 这条线最近取不到流（按源 + 线路名聚合的本地记忆，6 小时有效）。
  /// 仍然可点：标记只是「前置告知 + 默认不选」，不是禁用。
  final bool unreachable;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFFFFE08A), Color(0xFFFB923C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: selected ? null : AppTokens.surfaceMuted,
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          border: Border.all(
            color: selected
                ? Colors.transparent
                : (unreachable
                      ? const Color(0xFFFDE7C8) // 淡橙：与「上次没取到流」呼应
                      : const Color(0xFFE7ECF5)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                // 标了「上次没取到流」的线路名字弱化一档（仍可读、仍可点）。
                color: selected
                    ? AppTokens.inkDark
                    : (unreachable
                          ? AppTokens.textTertiary
                          : AppTokens.textSecondary),
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (unreachable) ...[
              const SizedBox(width: 5),
              Icon(
                Icons.wifi_off_rounded,
                size: 13,
                color: selected
                    ? AppTokens.inkDark.withValues(alpha: 0.75)
                    : const Color(0xFFFB923C),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// B4：剧集分段器——下划线 tab 样式，选中态底部金橙下划线、无填充，
/// 与线路的金橙药丸 chip 明确区分，消除「选线路 / 跳分段」的语义混淆。
class _SegmentTab extends StatelessWidget {
  const _SegmentTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? const Color(0xFFFB923C) : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppTokens.textSecondary : AppTokens.textTertiary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// 剧集网格单元：正方形、自适应宽度，选中时金橙渐变。
class _EpisodeCell extends StatelessWidget {
  const _EpisodeCell({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        // A1：宽度由外部等宽网格的 SizedBox 决定，这里只管高度内边距。
        padding: EdgeInsets.symmetric(
          horizontal: 8,
          vertical: selected ? 8 : 7,
        ),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFFFFE08A), Color(0xFFFB923C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: selected ? null : AppTokens.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Colors.transparent : AppTokens.cardBorder,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? AppTokens.inkDark : AppTokens.textSecondary,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// 剧集工具按钮：正倒序 / 展开收起，浅色轻量。
class _EpisodeToolButton extends StatelessWidget {
  const _EpisodeToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // B5：放大点击热区——更大内边距 + 浅背景胶囊，长列表频繁操作更好点。
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTokens.surfaceMuted,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppTokens.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: AppTokens.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroIconButton extends StatelessWidget {
  const _HeroIconButton({
    required this.icon,
    required this.onTap,
    this.highlight = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    // 清新版：浅色主题按钮；追剧高亮改走金橙（原先的玫红与旁边两个灰按钮
    // 不是一个体系，一粉一灰看着跳）。
    return Material(
      color: highlight
          ? const Color(0xFFFB923C).withValues(alpha: 0.16)
          : const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            color: highlight
                ? const Color(0xFFEA580C)
                : AppTokens.textSecondary,
            size: 20,
          ),
        ),
      ),
    );
  }
}
