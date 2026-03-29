import 'package:flutter/material.dart';

import '../../globals.dart';
import '../core/models.dart';
import '../video_module.dart';
import 'video_detail_page.dart';
import 'video_list_page.dart';

class VideoHomePage extends StatelessWidget {
  const VideoHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(child: VideoTabArea()),
    );
  }
}

class VideoTabArea extends StatefulWidget {
  const VideoTabArea({super.key});

  @override
  State<VideoTabArea> createState() => _VideoTabAreaState();
}

class _VideoTabAreaState extends State<VideoTabArea>
    with AutomaticKeepAliveClientMixin, RouteAware {
  final TextEditingController _searchController = TextEditingController();

  List<VideoItem> _recentItems = [];
  bool _loadingRecent = true;
  PageRoute<dynamic>? _route;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute && route != _route) {
      if (_route != null) {
        appRouteObserver.unsubscribe(this);
      }
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    _loadRecent();
  }

  @override
  void dispose() {
    if (_route != null) {
      appRouteObserver.unsubscribe(this);
    }
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    setState(() => _loadingRecent = true);
    try {
      final list = await VideoModule.repository.getRecentItems();
      if (!mounted) return;
      setState(() {
        _recentItems = list;
        _loadingRecent = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRecent = false);
    }
  }

  void _openListByCategory(VideoCategory category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoListPage(category: category),
      ),
    ).then((_) => _loadRecent());
  }

  void _openSearch() {
    final keyword = _searchController.text.trim();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoListPage(
          initialKeyword: keyword.isEmpty ? null : keyword,
        ),
      ),
    ).then((_) => _loadRecent());
  }

  void _openRecent(VideoItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoDetailPage(item: item),
      ),
    ).then((_) => _loadRecent());
  }

  IconData _iconForCategory(String id) {
    switch (id) {
      case 'classic-film':
        return Icons.local_movies_outlined;
      case 'documentary':
        return Icons.travel_explore_outlined;
      case 'tv-series':
        return Icons.live_tv_outlined;
      case 'short-film':
        return Icons.movie_filter_outlined;
      case 'sample':
        return Icons.play_circle_outline;
      default:
        return Icons.video_library_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final categories = VideoModule.repository.source.categories;

    return SingleChildScrollView(
      primary: false,
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildSearchCard(),
            const SizedBox(height: 16),
            _buildCategorySection(categories),
            const SizedBox(height: 16),
            _buildRecentSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const CircleAvatar(
          radius: 22,
          child: Icon(Icons.play_circle_fill_rounded),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '影视播放器',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Text(
                '公共版权视频源 / 免费样例兜底 / 支持进度记忆',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '搜索影视',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _openSearch(),
            decoration: InputDecoration(
              hintText: '输入电影 / 纪录片 / 电视剧关键词',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: const Color(0xFFF6F7F9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _openSearch,
                  icon: const Icon(Icons.search),
                  label: const Text('搜索'),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _loadRecent,
                icon: const Icon(Icons.refresh),
                label: const Text('刷新'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySection(List<VideoCategory> categories) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '精选分类',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (categories.isEmpty)
            const Text('当前没有可用分类，请确认 VideoModule 已配置。')
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: categories.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 2.1,
              ),
              itemBuilder: (context, index) {
                final category = categories[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _openListByCategory(category),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F3F5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          left: 12,
                          top: 12,
                          right: 48,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                category.title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                category.description,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                  height: 1.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: CircleAvatar(
                            backgroundColor: Colors.blue.shade100,
                            child: Icon(
                              _iconForCategory(category.id),
                              color: Colors.blue[700],
                            ),
                          ),
                        ),
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

  Widget _buildRecentSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '最近播放',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (_loadingRecent)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_recentItems.isEmpty)
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFFF6F7F9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.history_outlined, size: 36, color: Colors.grey[400]),
                    const SizedBox(height: 8),
                    Text(
                      '播放过的视频会显示在这里',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: 170,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _recentItems.length,
                itemBuilder: (context, index) {
                  final item = _recentItems[index];
                  return GestureDetector(
                    onTap: () => _openRecent(item),
                    child: SizedBox(
                      width: 110,
                      child: Container(
                        margin: const EdgeInsets.only(right: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: item.coverUrl.isNotEmpty
                                    ? Image.network(
                                        item.coverUrl,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => _coverPlaceholder(),
                                      )
                                    : _coverPlaceholder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              item.title,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.category,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _coverPlaceholder() {
    return Container(
      color: const Color(0xFFE9ECEF),
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          size: 36,
          color: Colors.grey[500],
        ),
      ),
    );
  }
}