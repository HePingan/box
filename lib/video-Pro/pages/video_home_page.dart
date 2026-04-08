import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controller/history_controller.dart';
import '../controller/video_controller.dart';
import '../models/video_source.dart';
import '../models/video_category.dart';
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

  final Map<String, Future<String?>> _coverFutureCache = {};

  // 🛑 【核心护城河】：全局敏感词黑名单库
  static const List<String> _nsfwKeywords = [
    '伦理', '三级', '写真', '热舞', '福利', 
    '激情', '成人', '两性', '情色', '午夜', 
    '限制级', '禁片', 'VIP',"擦边"
  ];

  // 🛑 鉴定文本是否为安全绿色内容
  bool _isSafeContent(String? text) {
    if (text == null || text.trim().isEmpty) return true;
    for (final kw in _nsfwKeywords) {
      if (text.contains(kw)) return false; // 命中敏感词，判定为不安全
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapCatalogIfNeeded();
    });
  }

  Future<void> _bootstrapCatalogIfNeeded({bool force = false}) async {
    final controller = context.read<VideoController>();
    if (!force && (controller.sources.isNotEmpty || controller.videoList.isNotEmpty)) {
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
    await Navigator.push(context, MaterialPageRoute(builder: (_) => VideoSearchPage(currentSource: source)));
  }

  Future<void> _openAggregateSearch() async {
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AggregateSearchPage()));
  }

  Future<String?> _coverUrlFor(dynamic video, VideoSource source) {
    final vodId = _readInt(video, const ['vodId', 'vod_id', 'id']);
    final cacheKey = '${source.id}_${source.url}_${source.detailUrl}_$vodId';
    final cached = _coverFutureCache[cacheKey];
    if (cached != null) return cached;
    final future = _loadCoverUrl(video, source);
    _coverFutureCache[cacheKey] = future;
    return future;
  }

  Future<String?> _loadCoverUrl(dynamic video, VideoSource source) async {
    final direct = _resolveImageUrl(
      _readText(video, const ['vodPic', 'vod_pic', 'pic', 'cover', 'image', 'img', 'thumb', 'poster', 'vod_img']),
      source,
    );
    if (direct != null && direct.isNotEmpty) return direct;

    final vodId = _readInt(video, const ['vodId', 'vod_id', 'id']);
    if (vodId <= 0) return null;

    try {
      final detailBaseUrl = source.detailUrl.trim().isNotEmpty ? source.detailUrl : source.url;
      final detail = await VideoApiService.fetchDetail(detailBaseUrl, vodId);
      if (detail == null) return null;
      final detailCover = _resolveImageUrl(detail.vodPic, source);
      if (detailCover != null && detailCover.isNotEmpty) return detailCover;
      return null;
    } catch (e) {
      return null;
    }
  }

  String? _resolveImageUrl(String? rawUrl, VideoSource source) {
    if (rawUrl == null) return null;
    var url = rawUrl.trim().replaceAll('\\', '');
    if (url.isEmpty) return null;
    if (url.startsWith('//')) return 'https:$url';
    final parsed = Uri.tryParse(url);
    if (parsed != null && parsed.hasScheme) return url;

    final baseUrls = <String>[source.detailUrl.trim(), source.url.trim()];
    for (final base in baseUrls) {
      if (base.isEmpty) continue;
      final baseUri = Uri.tryParse(base);
      if (baseUri == null || !baseUri.hasScheme) continue;
      try {
        return baseUri.resolve(url).toString();
      } catch (_) {}
    }
    return url;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VideoController>();
    final source = controller.currentSource;
    final screenWidth = MediaQuery.of(context).size.width;

    // 🛑 在渲染 UI 前，强行过滤掉所有黑名单影片（防止在“全部影片”里混入成人视频）
    final safeVideoList = controller.videoList.where((video) {
        final title = _readText(video, const ['vodName', 'vod_name', 'name', 'title']);
        return _isSafeContent(video.typeName) && _isSafeContent(title);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 50,
        actions: [
          IconButton(tooltip: '当前源搜索', onPressed: source == null ? null : _openCurrentSourceSearch, icon: const Icon(Icons.search_rounded)),
          IconButton(tooltip: '聚合搜索', onPressed: _openAggregateSearch, icon: const Icon(Icons.public_rounded)),
          IconButton(tooltip: '刷新', onPressed: _reloadCurrentSource, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: NotificationListener<ScrollUpdateNotification>(
        onNotification: (ScrollUpdateNotification notification) {
          if (notification.metrics.pixels >= notification.metrics.maxScrollExtent - 200) {
            controller.loadMore(); 
          }
          return false;
        },
        child: RefreshIndicator(
          onRefresh: _reloadCurrentSource,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Container(color: Colors.white, child: _buildHeader(context, controller, source)),
              ),
              SliverToBoxAdapter(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildQuickAccessGrid(context, controller, screenWidth),
                ),
              ),

              if (widget.showHistory && context.select((HistoryController c) => c.historyList.isNotEmpty))
                const SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.fromLTRB(12, 12, 12, 0), child: HistoryQuickView()),
                ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 16.0, bottom: 4.0),
                  child: _buildCompleteCategoryBar(context, controller),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 12, 8),
                  child: Row(
                    children: [
                      Icon(Icons.video_camera_back_rounded, size: 20, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        source == null ? '视频推荐' : source.name,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      SizedBox(
                        height: 32,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                          onPressed: controller.sources.isEmpty ? null : () => _showSourcePicker(context, controller),
                          icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                          label: const Text('换源', style: TextStyle(fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 使用上面过滤完毕的 safeVideoList 替代 controller.videoList 进行展示
              if (controller.isLoading && safeVideoList.isEmpty)
                const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
              else if (safeVideoList.isEmpty)
                SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState(context, controller))
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final video = safeVideoList[index]; // 🛑 核心替换
                        final currentSource = source;
                        final vodId = _readInt(video, const ['vodId', 'vod_id', 'id']);
                        final title = _readText(video, const ['vodName', 'vod_name', 'name', 'title']) ?? '未命名';
                        final remarks = _readText(video, const ['vodRemarks', 'vod_remarks', 'remarks', 'remark']);

                        return _VideoCard(
                          title: title,
                          remarks: remarks,
                          coverUrlFuture: currentSource == null ? null : _coverUrlFor(video, currentSource),
                          onTap: currentSource == null || vodId <= 0
                              ? null
                              : () => Navigator.push(context, MaterialPageRoute(builder: (_) => VideoDetailPage(source: currentSource, vodId: vodId))),
                        );
                      },
                      childCount: safeVideoList.length,
                    ),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: screenWidth > 800 ? 6 : (screenWidth > 500 ? 4 : 3),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.55,
                    ),
                  ),
                ),
              
              SliverToBoxAdapter(
                child: _buildBottomLoader(controller),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✨ 在渲染滑动胶囊时，提前过滤掉所有脏分类
  Widget _buildCompleteCategoryBar(BuildContext context, VideoController controller) {
    if (controller.categories.isEmpty) return const SizedBox.shrink();

    // 🛑 强力过滤：屏蔽成人分类
    final safeCategories = controller.categories.where((cat) => _isSafeContent(cat.typeName)).toList();
    if (safeCategories.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text("分类筛选", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
              const SizedBox(width: 8),
              Text("如果上方快捷入口无影片，请在此选择精确子分类", style: TextStyle(fontSize: 11, color: Colors.redAccent.shade200)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 38,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: safeCategories.length + 1, // 🛑 使用安全库的长度
            itemBuilder: (context, index) {
              final isAll = index == 0;
              final catName = isAll ? '全部' : safeCategories[index - 1].typeName;
              final catId = isAll ? null : safeCategories[index - 1].typeId;
              final isSelected = controller.currentTypeId == catId;

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => controller.setCategory(catId),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
                        width: 1,
                      )
                    ),
                    child: Center(
                      child: Text(
                        catName,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBottomLoader(VideoController controller) {
    if (controller.videoList.isEmpty) return const SizedBox.shrink();
    if (!controller.hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text("—— 已经到底啦 ——", style: TextStyle(color: Colors.grey, fontSize: 13))),
      );
    }
    if (controller.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    return const SizedBox(height: 48); 
  }

  Widget _buildQuickAccessGrid(BuildContext context, VideoController controller, double screenWidth) {
    if (controller.categories.isEmpty && controller.currentSource != null) {
      return const SizedBox.shrink();
    }

    int? getMappedTypeId(List<String> exactMatch, List<String> fuzzyMatch) {
      for (var word in exactMatch) {
         try { return controller.categories.firstWhere((c) => c.typeName == word).typeId; } catch (_) {}
      }
      for (var word in fuzzyMatch) {
         try { return controller.categories.firstWhere((c) => c.typeName.contains(word)).typeId; } catch (_) {}
      }
      return null;
    }

    final List<Map<String, dynamic>> menuItems = [
      {
        "title": "全部影片", "icon": Icons.auto_awesome, "typeId": null,
        "colors": [const Color(0xFF90A4AE), const Color(0xFF607D8B)]
      },
      {
        "title": "电影找片", "icon": Icons.movie_creation_outlined, 
        "typeId": getMappedTypeId(["电影"], ["电影", "片"]),
        "colors": [const Color(0xFFFFB74D), const Color(0xFFFF9800)]
      },
      {
        "title": "热播追剧", "icon": Icons.live_tv_rounded, 
        "typeId": getMappedTypeId(["连续剧", "国产剧", "电视剧"], ["剧", "剧集"]),
        "colors": [const Color(0xFF64B5F6), const Color(0xFF2196F3)]
      },
      {
        "title": "动漫次元", "icon": Icons.animation_rounded, 
        "typeId": getMappedTypeId(["动漫", "动画片"], ["漫", "动画"]),
        "colors": [const Color(0xFF81C784), const Color(0xFF4CAF50)]
      },
      {
        "title": "综艺大观", "icon": Icons.mic_external_on_rounded, 
        "typeId": getMappedTypeId(["综艺"], ["综艺"]),
        "colors": [const Color(0xFFF06292), const Color(0xFFE91E63)]
      },
      {
         "title": "爽文短剧", "icon": Icons.video_library_rounded, 
         "typeId": getMappedTypeId(["短剧", "微网剧"], ["短剧"]),
         "colors": [const Color(0xFF7986CB), const Color(0xFF3F51B5)]
      },
    ];

    int crossAxisCount;
    double aspectRatio;
    
    if (screenWidth > 1000) { crossAxisCount = 6; aspectRatio = 2.5; } 
    else if (screenWidth > 600) { crossAxisCount = 3; aspectRatio = 2.8; } 
    else { crossAxisCount = 2; aspectRatio = 2.4; }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text("快捷入口", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
              const SizedBox(width: 8),
              Text("系统猜测的常用大类", style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
          ),
          const SizedBox(height: 10),
          GridView.builder(
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: menuItems.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: aspectRatio,
              crossAxisSpacing: 10, 
              mainAxisSpacing: 10,
            ),
            itemBuilder: (context, index) {
              final item = menuItems[index];
              final bool isSelected = controller.currentTypeId == item['typeId'];

              return GestureDetector(
                onTap: () => controller.setCategory(item['typeId']),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(colors: item['colors'], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    border: isSelected ? Border.all(color: Colors.black87, width: 2) : Border.all(color: Colors.transparent, width: 2),
                    boxShadow: isSelected ? [BoxShadow(color: (item['colors'][1] as Color).withOpacity(0.5), blurRadius: 8, offset: const Offset(0, 4))] : [],
                  ),
                  foregroundDecoration: isSelected ? null : BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.25), shape: BoxShape.circle),
                        child: Icon(item['icon'], color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 8),
                      Text(item['title'], style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold, letterSpacing: 1.2))
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, VideoController controller, VideoSource? source) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8), 
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), 
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(Icons.hub_rounded, color: Colors.blueAccent.withOpacity(0.8), size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("OuonnkiTV 聚合引擎", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                Text(
                  source == null ? '加载中...' : '已接入 ${controller.sources.length} 个片源核心，提供绿色净化服务',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, VideoController controller) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 60),
        Icon(Icons.inbox_rounded, size: 64, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Center(child: Text(controller.currentSource == null ? '暂无可用视频源' : '站长没有往这个分类里放视频喔~\n请尝试在上方滑动选择其他实体分类', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade500))),
        const SizedBox(height: 16),
        Center(child: ElevatedButton.icon(onPressed: _reloadCurrentSource, icon: const Icon(Icons.refresh_rounded), label: const Text('刷新重试'))),
      ],
    );
  }

  void _showSourcePicker(BuildContext context, VideoController controller) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) {
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: controller.sources.length,
          separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
          itemBuilder: (context, index) {
            final s = controller.sources[index];
            final selected = s.id == controller.currentSource?.id;
            return ListTile(
              leading: Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked, color: selected ? Colors.blue : Colors.grey),
              title: Text(s.name, style: TextStyle(fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
              subtitle: Text(s.url, maxLines: 1, overflow: TextOverflow.ellipsis),
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
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
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
    if (item is Map) return item[key];
    try {
      switch (key) {
        case 'vodId': return item.vodId;
        case 'vod_id': return item.vodId;
        case 'id':  return item.id;
        case 'vodName': return item.vodName;
        case 'vod_name': return item.vodName;
        case 'name': return item.name;
        case 'title': return item.title;
        case 'vodPic': return item.vodPic;
        case 'vod_pic': return item.vodPic;
        case 'pic': return item.pic;
        case 'cover': return item.cover;
        case 'image': return item.image;
        case 'img': return item.img;
        case 'thumb': return item.thumb;
        case 'poster': return item.poster;
        case 'vod_img': return item.vodImg;
        case 'vodRemarks': return item.vodRemarks;
        case 'vod_remarks': return item.vodRemarks;
        case 'remarks': return item.remarks;
        case 'remark': return item.remark;
        default: return null;
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

  const _VideoCard({required this.title, required this.remarks, required this.coverUrlFuture, required this.onTap});

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
                borderRadius: BorderRadius.circular(6), 
                child: FutureBuilder<String?>(
                  future: coverUrlFuture,
                  builder: (context, snapshot) {
                    final imageUrl = snapshot.data?.trim();
                    if (imageUrl == null || imageUrl.isEmpty) return _buildPlaceholder();
                    return Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(color: Colors.grey.shade200, alignment: Alignment.center, child: const CircularProgressIndicator(strokeWidth: 2));
                      },
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
          Text(remarks ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() => Container(color: Colors.grey.shade200, alignment: Alignment.center, child: Icon(Icons.movie_outlined, size: 28, color: Colors.grey.shade400));
}