import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controller/video_controller.dart';
import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../services/video_api_service.dart';
import '../video_module.dart';
import '../widgets/history_quick_view.dart';
import 'aggregate_search_page.dart';
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
  static const String _fallbackCatalogUrl =
      'https://raw.githubusercontent.com/ZhuBaiwan-oOZZXX/OuonnkiTV-Source/main/tv_source/OuonnkiTV/full-noadult.json';

  /// 缓存封面请求，避免每次重建都重复请求详情接口
  final Map<String, Future<String?>> _coverFutureCache = {};

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
    final catalogUrl = resolvedUrl ?? _fallbackCatalogUrl;

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
        builder: (_) => VideoSearchPage(
          currentSource: source,
        ),
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

  Future<String?> _coverUrlFor(dynamic video, VideoSource source) {
    final vodId = _readInt(video, const ['vodId', 'vod_id', 'id']);

    final cacheKey = '${source.id}_${source.url}_${source.detailUrl}_$vodId';

    final cached = _coverFutureCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final future = _loadCoverUrl(video, source);
    _coverFutureCache[cacheKey] = future;
    return future;
  }

  Future<String?> _loadCoverUrl(dynamic video, VideoSource source) async {
    // 1) 先取列表里的封面
    final direct = _resolveImageUrl(
      _readText(video, const [
        'vodPic',
        'vod_pic',
        'pic',
        'cover',
        'image',
        'img',
        'thumb',
        'poster',
        'vod_img',
      ]),
      source,
    );

    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    // 2) 没有封面就去详情里补
    final vodId = _readInt(video, const ['vodId', 'vod_id', 'id']);
    if (vodId <= 0) return null;

    try {
      final detailBaseUrl =
          source.detailUrl.trim().isNotEmpty ? source.detailUrl : source.url;

      final detail = await VideoApiService.fetchDetail(
        detailBaseUrl,
        vodId,
      );

      if (detail == null) return null;

      final detailCover = _resolveImageUrl(detail.vodPic, source);
      if (detailCover != null && detailCover.isNotEmpty) {
        return detailCover;
      }

      return null;
    } catch (e) {
      debugPrint('首页封面加载失败: $vodId -> $e');
      return null;
    }
  }

  String? _resolveImageUrl(String? rawUrl, VideoSource source) {
    if (rawUrl == null) return null;

    var url = rawUrl.trim().replaceAll('\\', '');
    if (url.isEmpty) return null;

    // 协议相对地址
    if (url.startsWith('//')) {
      return 'https:$url';
    }

    // 已经是绝对地址
    final parsed = Uri.tryParse(url);
    if (parsed != null && parsed.hasScheme) {
      return url;
    }

    // 相对路径：尝试用源地址补全
    final baseUrls = <String>[
      source.detailUrl.trim(),
      source.url.trim(),
    ];

    for (final base in baseUrls) {
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

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
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
          IconButton(
            tooltip: '切源',
            onPressed: controller.sources.isEmpty
                ? null
                : () => _showSourcePicker(context, controller),
            icon: const Icon(Icons.source_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
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

                      final vodId =
                          _readInt(video, const ['vodId', 'vod_id', 'id']);
                      final title = _readText(video, const [
                            'vodName',
                            'vod_name',
                            'name',
                            'title',
                          ]) ??
                          '未命名';
                      final remarks = _readText(video, const [
                        'vodRemarks',
                        'vod_remarks',
                        'remarks',
                        'remark',
                      ]);

                      return _VideoCard(
                        title: title,
                        remarks: remarks,
                        coverUrlFuture: currentSource == null
                            ? null
                            : _coverUrlFor(video, currentSource),
                        onTap: currentSource == null || vodId <= 0
                            ? null
                            : () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => VideoDetailPage(
                                      source: currentSource,
                                      vodId: vodId,
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
          IconButton(
            onPressed: source == null ? null : _openCurrentSourceSearch,
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
            onPressed: _reloadCurrentSource,
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

  String? _readText(dynamic item, List<String> keys) {
    for (final key in keys) {
      final value = _readDynamicProperty(item, key);
      if (value == null) continue;

      final text = value.toString().trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }
    return null;
  }

  int _readInt(dynamic item, List<String> keys) {
    final text = _readText(item, keys);
    if (text == null) return 0;
    return int.tryParse(text) ?? 0;
  }

  dynamic _readDynamicProperty(dynamic item, String key) {
    if (item == null) return null;

    // Map / JSON 数据
    if (item is Map) {
      return item[key];
    }

    // 兼容 VodItem 或其它对象
    try {
      switch (key) {
        case 'vodId':
          return item.vodId;
        case 'vod_id':
          return item.vodId;
        case 'id':
          return item.id;

        case 'vodName':
          return item.vodName;
        case 'vod_name':
          return item.vodName;
        case 'name':
          return item.name;
        case 'title':
          return item.title;

        case 'vodPic':
          return item.vodPic;
        case 'vod_pic':
          return item.vodPic;
        case 'pic':
          return item.pic;
        case 'cover':
          return item.cover;
        case 'image':
          return item.image;
        case 'img':
          return item.img;
        case 'thumb':
          return item.thumb;
        case 'poster':
          return item.poster;
        case 'vod_img':
          return item.vodImg;

        case 'vodRemarks':
          return item.vodRemarks;
        case 'vod_remarks':
          return item.vodRemarks;
        case 'remarks':
          return item.remarks;
        case 'remark':
          return item.remark;

        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }
}

class _VideoCard extends StatelessWidget {
  final String title;
  final String? remarks;
  final Future<String?>? coverUrlFuture;
  final VoidCallback? onTap;

  const _VideoCard({
    required this.title,
    required this.remarks,
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
                        debugPrint('封面加载失败: $title -> $imageUrl');
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
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            remarks ?? '',
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