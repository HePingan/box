import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:box/design_system/widgets/app_page_scaffold.dart';

import '../controller/favorites_controller.dart';
import '../controller/history_controller.dart';
import '../controller/video_detail_controller.dart';
import '../controller/video_download_controller.dart';
import '../models/video_source.dart';
import '../widgets/download/video_download_bottom_sheet.dart';
import '../widgets/video_play_container.dart';
import 'detail/detail_info_card.dart';
import 'detail/detail_models.dart';
import 'detail/episode_label.dart';
import 'detail/watched_episodes.dart';
import '../../design_system/app_tokens.dart';
import '../../design_system/widgets/app_back_button.dart';
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

  /// 仅测试用：注入详情数据源（抓图/布局用例不必打真实采集接口）。
  /// 线上所有调用点都不传，走 [VideoApiService.fetchDetail]。
  final DetailFetcher? detailFetcher;

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
    this.detailFetcher,
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
        detailFetcher: detailFetcher,
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
  // 剧集面板本地视图状态：分段(-1=跟随当前集)、展开全部、倒序。
  static const int _episodeSegmentSize = 50;
  int _episodeSegment = -1;
  bool _episodesExpanded = false;
  bool _episodesReversed = false;

  /// 播放器是否收起（收起后变成一个窄条，把空间让给选集）。
  ///
  /// 为什么是"视觉收起"而不是"销毁播放器"：
  /// `VideoPlayContainer` 的 state 里握着解码器与播放进度，销毁再建会
  /// 中断当前播放（用户只是想翻选集，不是想停）。所以这里只缩高度，
  /// **widget 树里的位置和 key 都不变**，state 与音频都不受影响。
  bool _playerCollapsed = false;

  /// 下方 Tab：0 = 选集，1 = 影片资料。
  ///
  /// 默认选集：进详情页的第一件事几乎都是"从第几集开始看"。
  /// 资料是选片时才关心的东西，放在第二个 Tab 里不占版面。
  int _panelTab = 0;

  /// ## 为什么这里**没有** controller 监听（第六轮去重）
  ///
  /// 原先有一个 `_attachControllerListener`，只干一件事：把 `resumeMessage`
  /// 弹成 SnackBar 并立刻 `consumeResumeMessage()`。但同一个字段同时被
  /// 选集卡顶部的黄色提示条读取 —— 实测 `initialPosition > 0` 时同一句
  /// 「已为你恢复到上次播放位置：00:43」会**同时**出现两遍（SnackBar 一次、
  /// 卡内提示条一次）。
  ///
  /// 去掉 SnackBar 那条通道后，监听器本身也没有别的职责了：
  /// 页面是 `context.watch<VideoDetailController>()` 在重建，不需要再手工
  /// 订阅。SnackBar 通道只剩 `_noticeVia`（换线路 / 起播过慢这类瞬时事件）。
  ///
  /// 顺带保住一个行为：`resumeMessage` 现在**只由用户点关闭时消费**，
  /// 所以那条提示条会一直留在卡里，不会两秒后自己消失。

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
                        detail: detail,
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontal,
                          AppTokens.spaceSm,
                          horizontal,
                          0,
                        ),
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: _playerCollapsed
                              // 收起态：保留播放器（不销毁、不换 key），
                              // 只把它压成 0 高 + 不可见 —— 音频继续，选集腾出空间。
                              // Offstage 会同时让它不参与布局与命中测试。
                              ? Stack(
                                  children: [
                                    Offstage(
                                      offstage: true,
                                      child: _buildPlayerShell(
                                        controller,
                                        detail,
                                      ),
                                    ),
                                    _buildCollapsedPlayerBar(controller),
                                  ],
                                )
                              // 展开态只放播放器本体：收起入口已挪到下方
                              // 「线路」那条工具行里（见 _buildPlayerToolsRow），
                              // 不再单独占一行 40dp 的空白。
                              : _buildPlayerShell(controller, detail),
                        ),
                      ),
                      // 播放器工具行：线路（>1 条时）+ 收起播放器。
                      //
                      // 为什么把「收起播放器」并进这一行：它原先独占一行、靠右
                      // 一个文字按钮，上下各一段留白 —— 一屏顶部因此多出约 40dp
                      // 的空白，而它要服务的动作（让位给选集）与线路同属
                      // 「播放器旁边的操作」。并成一行后顶部少一行、视觉更整。
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontal,
                          AppTokens.spaceSm,
                          horizontal,
                          0,
                        ),
                        child: _buildPlayerToolsRow(controller),
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

  /// 播放器收起后的迷你条。
  ///
  /// 只保留「当前在播什么 + 展开」两件事：用户收起播放器是为了**看选集**，
  /// 不是要在一条窄条里继续操作播放（那有横屏全屏可用）。
  Widget _buildCollapsedPlayerBar(VideoDetailController controller) {
    final episode = controller.currentEpisodeName?.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTokens.cardBorder),
      ),
      child: Row(
        children: [
          // 与「收起」按钮同一对图标方向：上面那个是 ⌃ 收起，这里是 ⌄ 展开。
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: AppTokens.softPanel(const Color(0xFFFB923C)),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              size: 17,
              color: Color(0xFFEA580C),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              episode == null || episode.isEmpty
                  ? '正在播放'
                  : '正在播放 · $episode',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppTokens.textPrimary,
              ),
            ),
          ),
          _CollapsedPlayerToggle(
            collapsed: true,
            onTap: () => setState(() => _playerCollapsed = false),
          ),
        ],
      ),
    );
  }
  /// 播放器下方那条紧凑的工具行：线路（>1 条时）+ 收起播放器。
  ///
  /// 为什么合并成一行：
  /// * 「线路」是**播放动作**（这条卡了换一条），必须贴着播放器；
  /// * 「收起播放器」是**给选集让位**，同属"播放器旁边"的操作。
  /// 原先两者各占一行、中间还各有一段留白，一屏顶部为此多出约 40dp。
  /// 现在一行放完：线路在左、收起在右，右侧用短分隔线隔开，读起来是
  /// 「换线路 | 收起」两个并列动作，而不是两段互不相干的排版。
  ///
  /// 只有一条线路时左侧不画标签，收起按钮仍靠右 —— 不做成"整行居中"，
  /// 免得收起入口在页面上跳来跳去（换线路时它得待在原地）。
  ///
  /// **收起态不再画这个开关**：收起后播放器位置换成了迷你条，那里已有
  /// 一个「展开」。同一屏出现「展开」+「收起播放器」两个反向开关，
  /// 而且下面那个点了没有任何反应（播放器已经收起了）—— 这是真机截图
  /// 里能直接看出来的矛盾，所以收起态整行只保留线路。
  Widget _buildPlayerToolsRow(VideoDetailController controller) {
    final hasLines = controller.playLines.length > 1;
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          if (hasLines) Expanded(child: _buildLineStrip(controller)),
          if (!hasLines) const Spacer(),
          if (!_playerCollapsed) ...[
            if (hasLines) ...[
              const SizedBox(width: 8),
              Container(width: 1, height: 14, color: AppTokens.divider),
              const SizedBox(width: 4),
            ],
            _CollapsedPlayerToggle(
              collapsed: false,
              onTap: () => setState(() => _playerCollapsed = true),
            ),
          ],
        ],
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

  /// 算出「这部片里哪些集真的看过」，供剧集格子打标记。
  ///
  /// 数据源是全局的 [HistoryController]。用 `watch` 而不是 `read`：
  /// 用户从播放器返回、进度刚落库时，历史会 notify 一次，标记随即刷新 ——
  /// 不用退出重进才更新。
  ///
  /// 判定逻辑本身在 `detail/watched_episodes.dart`（纯函数，有 14 条用例）。
  /// 这里只负责取数 + 传给网格，UI 不做任何猜测。
  Set<String> _watchedKeysFor(VideoDetailController controller) {
    final history = context.watch<HistoryController>();
    return watchedEpisodeKeys(
      history.historyList,
      vodId: controller.vodId.toString(),
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
          // ② 与「影片资料」「剧情简介」共用同一个标题件
          // （原先这里是纯文字 14/w800，另两处是 15/w900 + 橙竖条，
          // 同一屏两种标题风格）。
          //
          // 第六轮（去重）：标题下原本还有一行「当前线路 24 集」，而下方工具行
          // 写着「共 24 集」、页面头部写着「全 24 集」—— 同一个数字一屏三遍，
          // 且三处必然相等（都取自当前线路的 episodes.length）。
          // 现在只留「共 N 集」（它和"正序"同一行，是有用的工具栏），
          // 这一段整块删掉，卡片因此少一行约 20dp。
          //
          // ① 这里原先还有个刷新按钮，和顶部导航的刷新是同一个动作
          // （都调 controller.loadDetail）—— 同一屏两个入口，也已删除。
          const AppSectionTitle('选集'),
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
              watchedKeys: _watchedKeysFor(controller),
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
    Set<String> watchedKeys = const <String>{},
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
                      // 当前集优先：既是当前集又看过时按"当前集"画
                      // （只保留一种强调，见 _EpisodeCell 的说明）。
                      watched: isEpisodeWatched(
                        watchedKeys,
                        episodes[index].url,
                      ),
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

  /// 顶部信息卡：返回 + 片名 + 右侧动作组，第二行给「片源 · 集数 · 画质」。
  ///
  /// 这一版重排解决的是**层级**问题（照真机截图逐格量的，不是凭印象）：
  ///
  /// * 原先四个 46dp 的浅灰方块并排 —— 返回、追剧、刷新、下载长得一模一样。
  ///   可返回是「离开这一页」，另外三个是「操作这一页」，两者不该用同一块砖。
  ///   现在返回降级成**无底色箭头**（与全站 [AppBackButton] 一致），三个动作
  ///   收进一个浅底胶囊 + 细分隔线里：视觉上是一组工具，而不是三块砖。
  /// * 原先的副标题只有「量子资源」四个字，孤零零挂在标题左下，既不像资料行
  ///   也不像标题。现在补成「片源 · 全 N 集 · 画质」，没有信息就不画那个点。
  /// * 标题与副标题改用同一个纵向 Column 排列，左边缘天然对齐 —— 原先靠
  ///   `EdgeInsets.only(left: 44)` 硬凑 44dp，改一次按钮尺寸就会错位。
  Widget _buildCompactMediaHeader({
    required VideoDetailController controller,
    required String title,
    dynamic detail,
  }) {
    final meta = _buildHeaderMeta(controller, detail);

    return Container(
      // 稳定 key：抓图/版面用例按它取这块卡的真实矩形，不靠猜祖先链。
      key: const ValueKey<String>('video-detail-header'),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(8, 6, 10, 8),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTokens.cardBorder),
        boxShadow: AppTokens.shadowSm(),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // 返回：只有箭头，落在卡片底色上（不套方块）。
            AppBackButton(onPressed: () => Navigator.maybePop(context)),
            const SizedBox(width: 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTokens.textPrimary,
                      fontSize: 17,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTokens.textSecondary,
                        fontSize: 11.5,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _HeaderActionBar(
              children: [
                _HeaderAction(
                  icon: controller.isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  tooltip: controller.isFavorite ? '取消追剧' : '加入追剧',
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
                _HeaderAction(
                  icon: Icons.refresh_rounded,
                  tooltip: '刷新详情',
                  onTap: controller.isLoading ? null : controller.loadDetail,
                ),
                _HeaderAction(
                  icon: Icons.file_download_rounded,
                  tooltip: '下载选集',
                  onTap: controller.playLines.isEmpty || controller.isLoading
                      ? null
                      : () => _openDownloadSheet(context, controller),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 头部副标题：片源 · 集数 · 画质。
  ///
  /// 取舍：
  /// * 集数按**当前线路**算（各线路集数并不总相等），单片时不写「全 1 集」——
  ///   那是句废话；
  /// * 片源名是数据里的原样（可能带 `🎬` 这类装饰符），这里不加工，交给目录；
  /// * 画质备注若已经写着「更新至24集」这类集数信息就不再重复，长备注也不引。
  String _buildHeaderMeta(VideoDetailController controller, dynamic detail) {
    final parts = <String>[];

    final sourceName = controller.source.name.trim();
    if (sourceName.isNotEmpty) parts.add(sourceName);

    final lines = controller.playLines;
    if (lines.isNotEmpty) {
      final index = controller.selectedLineIndex.clamp(0, lines.length - 1);
      final count = lines[index].episodes.length;
      if (count > 1) parts.add('全 $count 集');
    }

    final remarks = (detail.vodRemarks as String?)?.trim() ?? '';
    if (remarks.isNotEmpty && remarks.length <= 10 && !remarks.contains('集')) {
      parts.add(remarks);
    }

    return parts.join(' · ');
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

/// 播放器的「收起 / 展开」开关。
///
/// 收进播放器工具行的右端，与线路并列 —— 它俩是同一类动作：
/// 一个换播放源、一个给选集让位，都是"播放器旁边"的事。
///
/// 视觉上刻意做小（24dp 图标 + 12 号字，无底色）：它是**辅助动作**，
/// 不值得和线路 chip 抢注意力，更不该像原来那样单独占一整行。
class _CollapsedPlayerToggle extends StatelessWidget {
  const _CollapsedPlayerToggle({required this.collapsed, required this.onTap});

  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTokens.radiusChip),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              collapsed ? '展开' : '收起播放器',
              style: TextStyle(
                color: AppTokens.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              collapsed
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_up_rounded,
              size: 16,
              color: AppTokens.textTertiary,
            ),
          ],
        ),
      ),
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
/// 剧集网格单元：正方形、自适应宽度，选中时橙色描边 + 淡底。
///
/// ## 三种状态（视觉层级必须分得开）
///
/// | 状态 | 表现 | 为什么 |
/// |---|---|---|
/// | 当前正在播 | **橙色描边 1.5 + 橙色淡底** | 全页唯一的强调色只留给它 |
/// | 看过 | 浅底 + 序号左侧一个小圆点 | 淡到不抢戏，但扫一眼能看出进度 |
/// | 没看过 | 灰底 + 浅描边（默认） | — |
///
/// 「看过」刻意**不用**橙色、也不用边框：一旦和当前集同色，用户就分不清
/// 哪个是"上次看到这"、哪个是"现在放这"。用一颗 4dp 的灰绿小点足够，
/// 且它在深色档下也有对比（走 token，不写死）。
class _EpisodeCell extends StatelessWidget {
  const _EpisodeCell({
    required this.label,
    required this.selected,
    required this.onTap,
    this.watched = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// 这一集是否真的看过（进度 ≥ 1 分钟，见 `watched_episodes.dart`）。
  /// 当前集优先：既是当前集又看过时按"当前集"画，只保留一种强调。
  final bool watched;

  @override
  Widget build(BuildContext context) {
    // 集名是片源原样给的，长度不可控。旧实现把整个名字塞进一行再截断，
    // 于是「第04集 高清」会变成「第04…」—— 用户看不出这是第几集，
    // 而"点第几集"正是他唯一在做的事。
    //
    // 现在拆成两行：序号（大、永远完整）+ 其余文字（小、次要、可省略）。
    final parts = parseEpisodeLabel(label);
    final showWatched = watched && !selected;

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
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 看过的小圆点：放在序号**左侧**，不挤压序号本身
                // （序号是这个格子唯一必须完整显示的东西）。
                if (showWatched) ...[
                  Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.only(right: 3, top: 2),
                    decoration: BoxDecoration(
                      color: AppTokens.success.withValues(alpha: 0.85),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
                Flexible(
                  child: Text(
                    // 抽不到序号就显示原名（不猜一个编号出来）
                    parts.number ?? label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      // 看过的集把字重降一档：它已经"完成"了，
                      // 不该和待看的新集一样抢注意力。
                      color: selected
                          ? const Color(0xFFB45309)
                          : (showWatched
                                ? AppTokens.textSecondary
                                : AppTokens.textPrimary),
                      fontSize: parts.hasNumber ? 15 : 12,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                ),
              ],
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

/// 头部右侧的「一组动作」：浅底胶囊 + 细分隔线。
///
/// 为什么不是三个独立的方块：方块天生读作「三个并列的入口」，而这三个动作
/// 共用同一个上下文（都是对这部片操作）。包进一个胶囊后是一组工具，
/// 与左侧的返回箭头在层级上分开 —— 返回是离开，这几个是操作。
///
/// 分隔线用 `surface` 色调的 1px 竖线（比描边更淡）：胶囊底色是
/// `surfaceMuted`，再压一层描边会显得像素级的脏。
class _HeaderActionBar extends StatelessWidget {
  const _HeaderActionBar({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTokens.radiusInner),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 16,
                color: AppTokens.cardBorder,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// 动作组里的一个图标按钮（36×36，触摸热区靠 [Material] + [InkWell] 撑）。
///
/// 尺寸说明：原先 40×40 的方块在 4 个并排时占掉 46dp/个（含间距 6），
/// 一行 190dp；现在缩到 36dp 且不需要每个外面再留间距，整组约 110dp，
/// 标题可用的宽度因此多出约 80dp —— 长片名（「天才，女友」这类）不再一进去就截断。
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.highlight = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = highlight
        ? const Color(0xFFEA580C)
        : (enabled ? AppTokens.textSecondary : AppTokens.textTertiary);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusInner),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            icon,
            size: 19,
            color: highlight ? color : color.withValues(alpha: enabled ? 1 : 0.45),
          ),
        ),
      ),
    );
  }
}

