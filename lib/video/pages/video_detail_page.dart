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
import 'detail/episode_label.dart';
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

  /// 下方 Tab：0 = 选集，1 = 影片资料。
  ///
  /// 默认选集：进详情页的第一件事几乎都是"从第几集开始看"。
  /// 资料是选片时才关心的东西，放在第二个 Tab 里不占版面。
  int _panelTab = 0;

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
                      // 线路选择紧贴播放器下方。
                      //
                      // 为什么放这里而不是塞进「选集」Tab 里：换线路是**播放动作**
                      // （这条卡了换一条），和"选第几集"是两件事。
                      // 塞在选集卡里时要先展开 Tab、再往下找，多两步。
                      if (controller.playLines.length > 1)
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            horizontal,
                            10,
                            horizontal,
                            0,
                          ),
                          child: _buildLineStrip(controller),
                        ),
                      // ③ 区块间距统一到 spaceMd(12)：原来是 10/10/12/36 各写各的。
                      const SizedBox(height: AppTokens.spaceMd),
                      // 选集与资料改成 Tab 切换。
                      //
                      // 为什么：原来两个卡片**竖向堆叠**，28 集的网格展开后
                      // 资料卡被推到屏幕外两三屏 —— 想看"导演是谁"要往下翻很久，
                      // 而选集又要翻上去。两者本来就是"看剧时关心"与"选片时关心"
                      // 两种场景，不该同时铺满一屏。
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: horizontal),
                        child: _buildTabbedPanels(controller: controller, detail: detail),
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

  /// 播放器下方那条紧凑的线路选择器。
  ///
  /// 与详情卡里的「线路」行不同：这里是**单行 pill + 左侧小标签**，
  /// 贴在播放器下面不占版面 —— 换线路是播放中的高频动作。
  Widget _buildLineStrip(VideoDetailController controller) {
    return Row(
      children: [
        Text(
          '线路',
          style: TextStyle(
            color: AppTokens.textTertiary,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: controller.playLines.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final line = controller.playLines[index];
                return _PlaybackChip(
                  label: lineDisplayName(line.name, index),
                  subLabel: lineSubName(line.name),
                  selected: index == controller.selectedLineIndex,
                  unreachable: controller.isLineRecentlyUnreachable(index),
                  onTap: () => controller.selectLine(index),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// 选集 / 资料 两个面板的 Tab 切换外壳。
  ///
  /// 为什么不做成"两个卡片竖排"：28 集的网格展开后会把资料卡推到两三屏之外，
  /// 而这两块内容服务的是两种不同时机（看剧 vs 选片），同时铺满只会互相挤。
  Widget _buildTabbedPanels({
    required VideoDetailController controller,
    required dynamic detail,
  }) {
    const tabs = <String>['选集', '影片资料'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 分段控件：贴合卡片圆角，选中态用主色淡底（不用纯色块 —— 那是按钮的语言）
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppTokens.surfaceMuted,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTokens.cardBorder),
          ),
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _panelTab = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _panelTab == i
                            ? AppTokens.surface
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: _panelTab == i
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF0F172A)
                                      .withValues(alpha: 0.06),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        tabs[i],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: _panelTab == i
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: _panelTab == i
                              ? AppTokens.textPrimary
                              : AppTokens.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.spaceMd),
        if (_panelTab == 0)
          controller.playLines.isEmpty
              ? _buildEmptyEpisodePanel()
              : _buildPlaybackPanel(controller: controller)
        else
          DetailInfoCard(detail: detail, source: controller.source),
      ],
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
                      // 原先写「正在播放 · 第01集」，而网格里第 01 集本来就是
                      // 橙色高亮 —— 同一件事说了两遍。这里换成用户真的想知道、
                      // 而页面上又没别处写的信息：这条线路有多少集。
                      Text(
                        '当前线路 ${episodes.length} 集',
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
          const SizedBox(height: AppTokens.spaceMd),
          // 剧集在前、线路在后。
          //
          // 为什么换顺序：线路通常 2-4 条、用户选定后基本不再改；剧集有 20-40 集
          // 且每次都要点。原来线路那条带渐变填充的大胶囊压在剧集上方，
          // **次要信息抢了主要信息的位置**。
          //
          // 两行仍共用 _LabeledRow（内容左边缘对齐）—— 这条是上一轮修过的，
          // video_detail_layout_test 锁着，不能因为换顺序就丢。
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
        // A1：等宽宫格。按容器宽度算列数，每格等宽居中，
        // 避免集名长短导致的参差右边界。
        //
        // 2026-10-18：目标宽度 62 → 56，让常见手机宽度落在 **5 列**
        // （4 列时每屏只排 24 集，28 集的剧要展开一次才能看全）。
        // 5 列 × 约 56dp 仍能放下「序号 15px + 集名 9px」两行。
        LayoutBuilder(
          builder: (context, constraints) {
            // 网格缩在标签列右边（可用宽度少 38px），窄屏下限 3 列。
            const spacing = 8.0;
            final columns = ((constraints.maxWidth + spacing) / (56 + spacing))
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
              // 文案改成「展开剩余 N 集」：原先写「展开全部 (28)」，
              // 而收起时只显示 24 集 —— 同一屏「共 28 集」「展开全部 (28)」
              // 两个 28 并列，用户会疑惑"现在到底看到几集"。
              label: _episodesExpanded
                  ? '收起'
                  : '展开剩余 ${indices.length - visibleIndices.length} 集',
              onTap: () =>
                  setState(() => _episodesExpanded = !_episodesExpanded),
            ),
          ),
        ],
      ],
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
    this.subLabel = '',
    this.unreachable = false,
  });

  final String label;

  /// 副注：线路名是站点技术名时，这里放原名（`lzm3u8`），主显示是「线路 N」。
  final String subLabel;

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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          // 选中态从「渐变填充」降级为「描边 + 淡底」。
          //
          // 为什么：渐变那个橙色是全页最重的视觉元素，而线路只有 2-4 条、
          // 选定后基本不再改 —— 它抢了下方 28 个剧集格子的注意力。
          // 现在全页的"橙色强调"只留给当前正在看的那一集。
          // 当前集的淡底用 token 而不是写死 0xFFFFF5E6：
          // 深色档下写死的近白色会变成一块发亮的浅底（护栏当场抓到）。
          // softPanel() 会把强调色按当前明暗取 alpha，两档都协调。
          color: selected
              ? AppTokens.softPanel(const Color(0xFFFB923C))
              : AppTokens.surfaceMuted,
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          border: Border.all(
            color: selected
                ? const Color(0xFFFB923C)
                : (unreachable
                      ? AppTokens.warning.withValues(alpha: 0.35) // 淡橙：与「上次没取到流」呼应
                      : AppTokens.cardBorder),
            width: selected ? 1.5 : 1,
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
                    ? const Color(0xFFB45309)
                    : (unreachable
                          ? AppTokens.textTertiary
                          : AppTokens.textSecondary),
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            // 技术名作副注：既保留"这条是 lzm3u8"的信息，又不让它占主位。
            if (subLabel.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                subLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppTokens.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (unreachable) ...[
              const SizedBox(width: 5),
              const Icon(
                Icons.wifi_off_rounded,
                size: 13,
                color: Color(0xFFFB923C),
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
    // 集名是片源原样给的，长度不可控。旧实现把整个名字塞进一行再截断，
    // 于是「第04集 高清」会变成「第04…」—— 用户看不出这是第几集，
    // 而"点第几集"正是他唯一在做的事。
    //
    // 现在拆成两行：序号（大、永远完整）+ 其余文字（小、次要、可省略）。
    final parts = parseEpisodeLabel(label);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        // 宽度由外部等宽网格的 SizedBox 决定，这里只管内边距。
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          // 选中态用「描边 + 淡底」而不是渐变填充：
          // 渐变填充视觉太重，会和上方线路 chip 的选中态撞在一起，
          // 而这一屏真正需要强调的只有"当前这一集"。
          color: selected
              ? AppTokens.softPanel(const Color(0xFFFB923C))
              : AppTokens.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFFFB923C) : AppTokens.cardBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              // 抽不到序号就显示原名（不猜一个编号出来）
              parts.number ?? label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? const Color(0xFFB45309) : AppTokens.textPrimary,
                fontSize: parts.hasNumber ? 15 : 12,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
            ),
            if (parts.hasNumber && parts.rest.isNotEmpty) ...[
              const SizedBox(height: 1),
              Text(
                parts.rest,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTokens.textTertiary,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
            ],
          ],
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
          : AppTokens.surfaceMuted,
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
