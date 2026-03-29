import 'package:flutter/material.dart';

import '../core/models.dart';
import '../video_module.dart';
import 'video_detail_page.dart';

class VideoListPage extends StatefulWidget {
  const VideoListPage({
    super.key,
    this.category,
    this.initialKeyword,
  });

  final VideoCategory? category;
  final String? initialKeyword;

  @override
  State<VideoListPage> createState() => _VideoListPageState();
}

class _VideoListPageState extends State<VideoListPage> {
  static const int _pageSize = 20;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<VideoItem> _items = [];

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _page = 1;
  String _keyword = '';

  @override
  void initState() {
    super.initState();
    _keyword = widget.initialKeyword?.trim() ?? '';
    _searchController.text = _keyword;
    _scrollController.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_loading || _loadingMore || !_hasMore) return;

    if (_scrollController.position.extentAfter < 300) {
      _loadMore();
    }
  }

  Future<List<VideoItem>> _requestPage(int page) {
    final keyword = _keyword.trim();

    if (keyword.isNotEmpty) {
      return VideoModule.repository.searchVideos(keyword, page: page);
    }

    if (widget.category != null) {
      return VideoModule.repository.fetchByPath(widget.category!.query, page: page);
    }

    return VideoModule.repository.fetchByPath('classic film', page: page);
  }

  int _appendDistinct(List<VideoItem> incoming) {
    final existing = _items.map((e) => e.id).toSet();
    var added = 0;

    for (final item in incoming) {
      if (item.id.isEmpty) continue;
      if (existing.add(item.id)) {
        _items.add(item);
        added++;
      }
    }
    return added;
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
      _hasMore = true;
      _page = 1;
      _items.clear();
      _keyword = _searchController.text.trim();
    });

    await _loadPage(reset: true);
  }

  Future<void> _loadPage({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _loadingMore = false;
        _error = null;
      });
    } else {
      setState(() {
        _loadingMore = true;
      });
    }

    final pageToLoad = _page;

    try {
      final results = await _requestPage(pageToLoad);
      if (!mounted) return;

      if (reset) _items.clear();

      final added = _appendDistinct(results);

      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = null;
        _page = pageToLoad + 1;

        if (results.isEmpty || added == 0 || results.length < _pageSize) {
          _hasMore = false;
        } else {
          _hasMore = true;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = e.toString();
        if (reset) _items.clear();
        _hasMore = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    await _loadPage(reset: false);
  }

  void _doSearch() {
    _reload();
  }

  void _openDetail(VideoItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoDetailPage(item: item),
      ),
    );
  }

  Widget _buildCover(VideoItem item) {
    if (item.coverUrl.isEmpty) {
      return _placeholder();
    }
    return Image.network(
      item.coverUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFFE9ECEF),
      child: Center(
        child: Icon(Icons.movie_outlined, color: Colors.grey[500], size: 40),
      ),
    );
  }

  Widget _buildItemCard(VideoItem item) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetail(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: _buildCover(item),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: Text(
                item.title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                item.yearText.isNotEmpty ? '${item.category} · ${item.yearText}' : item.category,
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                item.intro,
                style: TextStyle(fontSize: 11, color: Colors.grey[600], height: 1.3),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: OutlinedButton(
            onPressed: _loadMore,
            child: const Text('加载更多'),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text(
          '已经到底了',
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 110),
        Icon(Icons.movie_filter_outlined, size: 52, color: Colors.grey[400]),
        const SizedBox(height: 12),
        Text(
          '没有找到内容',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.grey[700],
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '可以换个关键词再试试',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildGrid() {
    return CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildItemCard(_items[index]),
              childCount: _items.length,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.68,
            ),
          ),
        ),
        SliverToBoxAdapter(child: _buildFooter()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.category?.title ?? '影视搜索';
    final description = widget.category?.description ?? '搜索公共版权影视内容（合法免费）';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _doSearch(),
                  decoration: InputDecoration(
                    hintText: '输入电影 / 纪录片 / 电视剧关键词',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    description,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: _reload,
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _reload,
                        child: _items.isEmpty ? _buildEmptyState() : _buildGrid(),
                      ),
          ),
        ],
      ),
    );
  }
}