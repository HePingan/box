import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controller/video_controller.dart';
import '../models/video_source.dart';
import '../
models/vod_item.dart';
import '../../pages/debug_log_page.dart';
import '../services/video_api_service.dart';
import '../../utils/app_logger.dart';
import '../video_module.dart';
import '../widgets/history_quick_view.dart';
import 'aggregate_search_page.dart';
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
      'https://raw.githubusercontent.com/ZhuBaiwan-oOZZXX/OuonnkiTV-Source/main/tv_source/OuonnkiTV/full-noadult.json';

  /// 缓存“某个源 + 某个视频ID”的封面请求结果，避免重复拉详情
  final Map<String, Future<String?>> _coverFutureCache = {};

  void _openDebugLogPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const DebugLogPage(),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapCatalogIfNeeded();
    });
  }

  /// 首次初始化：如果已经有数据就不重复加载
  Future<void> _bootstrapCatalogIfNeeded({bool force = false}) async {
    final controller = context.read<VideoController>();

    AppLogger.instance.log(
      '_bootstrapCatalogIfNeeded force=$force sources=${controller.sources.length} videos=${controller.videoList.length}',
      tag: 'VIDEO_UI',
    );

    if (!force &&
        (controller.sources.isNotEmpty || controller.videoList.isNotEmpty)) {
      AppLogger.instance.log(
        '_bootstrapCatalogIfNeeded skipped because data already exists',
        tag: 'VIDEO_UI',
      );
      return;
    }

    try {
      AppLogger.instance.log(
        '_bootstrapCatalogIfNeeded resolving catalog url...',
        tag: 'VIDEO_UI',
      );

      final resolvedUrl = await VideoModule.resolveWorkingCatalogUrl();
      final catalogUrl = resolvedUrl ?? _fallbackCatalogUrl;

      AppLogger.instance.log(
        '_bootstrapCatalogIfNeeded resolvedUrl=$resolvedUrl finalUrl=$catalogUrl',
        tag: 'VIDEO_UI',
      );

      if (!mounted) return;

      await controller.initSources(catalogUrl);

      AppLogger.instance.log(
        '_bootstrapCatalogIfNeeded initSources done sources=${controller.sources.length} videos=${controller.videoList.length}',
        tag: 'VIDEO_UI',
      );
    } catch (e, st) {
      AppLogger.instance.logError(e, st, 'VIDEO_UI');
    }
  }

  /// 刷新当前源：优先刷新当前选中的视频源
  Future<void> _reloadCurrentSource() async {
    final controller = context.read<VideoController>();

    AppLogger.instance.log(
      '_reloadCurrentSource currentSource=${controller.currentSource?.name}',
      tag: 'VIDEO_UI',
    );

    try {
      if (controller.currentSource != null) {
        await controller.refreshCurrentSource();
        AppLogger.instance.log(
          '_reloadCurrentSource refreshCurrentSource done',
          tag: 'VIDEO_UI',
        );
        return;
      }

      await _bootstrapCatalogIfNeeded(force: true);
    } catch (e, st) {
      AppLogger.instance.logError(e, st, 'VIDEO_UI');
    }
  }

  Future<String?> _coverUrlFor(VodItem video, VideoSource source) {
    final cacheKey = '${source.id}_${video.vodId}';

    final cachedFuture = _coverFutureCache[cacheKey];
    if (cachedFuture != null) {
      return cachedFuture;
    }

    final future = _loadCoverUrl(video, source);
    _coverFutureCache[cacheKey] = future;
    return future;
  }

  Future<String?> _loadCoverUrl(VodItem video, VideoSource source) async {
    // 1) 先尝试列表里直接带的封面
    final direct = _resolveImageUrl(video.vodPic, source);
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    // 2) 列表没有封面，就去详情页里拿
    try {
      final detailBaseUrl =
          source.detailUrl.trim().isNotEmpty ? source.detailUrl : source.url;

      AppLogger.instance.log(
        '_loadCoverUrl fetch detail source=${source.name} vodId=${video.vodId} baseUrl=$detailBaseUrl',
        tag: 'VIDEO_UI',
      );

      final detail = await VideoApiService.fetchDetail(
        detailBaseUrl,
        video.vodId,
      );

      if (detail == null) {
        AppLogger.instance.log(
          '_loadCoverUrl detail null source=${source.name} vodId=${video.vodId}',
          tag: 'VIDEO_UI',
        );
        return null;
      }

      final detailCover = _resolveImageUrl(detail.vodPic, source);
      if (detailCover != null && detailCover.isNotEmpty) {
        return detailCover;
      }

      return null;
    } catch (e, st) {
      AppLogger.instance.logError(e, st, 'VIDEO_UI');
      debugPrint('加载封面失败: ${video.vodName} -> $e');
      return null;
    }
  }

  String? _resolveImageUrl(String? rawUrl, VideoSource source) {
    if (rawUrl == null) return null;

    var url = rawUrl.trim().replaceAll('\\', '');
    if (url.isEmpty) return null;

    // 协议相对地址：//img.xxx.com/a.jpg
    if (url.startsWith('//')) {
      return 'https:$url';
    }

    // 已经是绝对地址
    final parsed = Uri.tryParse(url);
    if (parsed != null && parsed.hasScheme) {
      return url;
    }

    // 相对路径：尝试用源地址补全
    final bases = <String>[
      source.detailUrl.trim(),
      source.url.trim(),
    ];

    for (final base in bases) {
      if (base.isEmpty) continue;

      final baseUri = Uri.tryParse(base);
      if (baseUri == null || !baseUri.hasScheme) continue;

      try {
        return baseUri.resolve(url).toString();
      } catch (_) {
        // 继续尝试下一个 base
      }
    }

    // 兜底原样返回
    return url;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VideoController>();
    final source = controller.currentSource;
    final screenWidth = MediaQuery.of(context).size.width;

    return RefreshIndicator(
      onRefresh: _reloadCurrentSource,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
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
                  IconButton(
                    tooltip: '刷新当前源',
                    onPressed: _reloadCurrentSource,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
                  IconButton(
                    tooltip: '调试日志',
                    onPressed: _openDebugLogPage,
                    icon: const Icon(Icons.bug_report_outlined, size: 20),
                  ),
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
                    final currentSource = source;

                    return _VideoCard(
                      video: video,
                      source: currentSource,
                      coverUrlFuture: currentSource == null
                          ? null
                          : _coverUrlFor(video, currentSource),
                      onTap: currentSource == null
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => VideoDetailPage(
                                    source: currentSource,
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
                  crossAxisCount: screenWidth > 600 ? 6 : 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.55,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
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
          const SizedBox(width: 8),

          // 右侧操作区：当前源搜索 + 聚合搜索 + 调试日志 + 刷新
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            runSpacing: 4,
            children: [
              IconButton(
                tooltip: '当前源搜索',
                onPressed: source == null
                    ? null
                    : () {
                        if (widget.onSearchTap != null) {
                          widget.onSearchTap!.call();
                          return;
                        }

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => VideoSearchPage(
                              currentSource: source,
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.search_rounded),
              ),
              IconButton(
                tooltip: '聚合搜索',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AggregateSearchPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.public_rounded),
              ),
              IconButton(
                tooltip: '调试日志',
                onPressed: _openDebugLogPage,
                icon: const Icon(Icons.bug_report_outlined),
              ),
              IconButton(
                tooltip: '刷新',
                onPressed: _reloadCurrentSource,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, VideoController controller) {
    final hasSource = controller.currentSource != null;
    final errorText = controller.errorMessage;

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
            hasSource ? '当前源暂无视频数据' : '暂无可用视频源',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 15,
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              errorText,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.red.shade400,
                fontSize: 12,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton.icon(
            onPressed: _reloadCurrentSource,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(hasSource ? '重试当前源' : '重新加载视频源'),
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
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked,
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
  final VideoSource? source;
  final Future<String?>? coverUrlFuture;
  final VoidCallback? onTap;

  const _VideoCard({
    required this.video,
    required this.source,
    required this.coverUrlFuture,
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
          Expanded(
            child: SizedBox(
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: FutureBuilder<String?>(
                  future: coverUrlFuture,
                  builder: (context, snapshot) {
                    final imageUrl = snapshot.data?.trim();

                    if (imageUrl == null || imageUrl.isEmpty) {
                      return _buildPlaceholder();
                    }

                    return Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      errorBuilder: (context, error, stackTrace) {
                        debugPrint('封面加载失败: ${video.vodName} -> $imageUrl');
                        return _buildPlaceholder();
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          color: Colors.grey.shade200,
                          alignment: Alignment.center,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        );
                      },
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

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey.shade300,
      alignment: Alignment.center,
      child: Icon(
        Icons.movie_outlined,
        size: 34,
        color: Colors.grey.shade600,
      ),
    );
  }
}