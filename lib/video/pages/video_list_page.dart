import 'dart:async';

import 'package:flutter/material.dart';

import '../core/composite_video_source.dart';
import '../core/licensed_catalog_video_source.dart';
import '../core/models.dart';
import '../core/search_history_service.dart';
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

  // 防抖时长：用户停止输入 400ms 后自动触发搜索
  static const Duration _debounceDuration = Duration(milliseconds: 400);

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _searchFocusNode = FocusNode();
  
  // 如果 SearchHistoryService 是同步实例，直接获取；如果是异步初始化的，请确保外部已初始化
  final _historyService = SearchHistoryService.instance;

  final List<VideoItem> _items = [];

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _page = 1;
  String _keyword = '';

  // 防抖 Timer
  Timer? _debounceTimer;

  // 请求取消令牌：每次新搜索递增，旧请求回调发现令牌不匹配则静默丢弃
  int _searchToken = 0;

  // 搜索建议面板是否显示
  bool _showSuggestions = false;
  List<String> _suggestions = [];

  // 已加载的搜索历史
  List<String> _searchHistory = [];

  // ───────────────────────── 生命周期 ─────────────────────────

  @override
  void initState() {
    super.initState();
    _keyword = widget.initialKeyword?.trim() ?? '';
    _searchController.text = _keyword;

    _scrollController.addListener(_onScroll);
    _searchFocusNode.addListener(_onFocusChange);
    _searchController.addListener(_onSearchTextChanged);

    // 加载搜索历史
    _historyService.load().then((list) {
      if (mounted) setState(() => _searchHistory = List.of(list));
    });

    _reload();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchFocusNode.removeListener(_onFocusChange);
    _searchFocusNode.dispose();
    _searchController.removeListener(_onSearchTextChanged);
    _searchController.dispose();
    super.dispose();
  }

  // ───────────────────────── 防抖搜索 & 输入框处理 ─────────────────────────

  void _onSearchTextChanged() {
    final text = _searchController.text;
    setState(() {
      _suggestions = _historyService.suggest(text);
    });

    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      final newKw = _searchController.text.trim();
      if (newKw == _keyword) return;
      _keyword = newKw;
      _doSearch();
    });
  }

  void _onFocusChange() {
    if (_searchFocusNode.hasFocus) {
      setState(() {
        _showSuggestions = true;
        _suggestions = _historyService.suggest(_searchController.text);
      });
    } else {
      // 稍微延迟，让点击建议项的事件能先触发
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) setState(() => _showSuggestions = false);
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_loading || _loadingMore || !_hasMore) return;
    if (_scrollController.position.extentAfter < 300) {
      _loadMore();
    }
  }

  // ───────────────────────── 数据加载逻辑 ─────────────────────────

  Stream<List<VideoItem>> _requestPageStream(int page) {
    final keyword = _keyword.trim();
    final repo = VideoModule.repository;
    final src = repo.source;

    if (keyword.isNotEmpty) {
      if (src is CompositeVideoSource) return src.searchVideosStream(keyword, page: page);
      if (src is LicensedCatalogVideoSource) return src.searchVideosStream(keyword, page: page);
      return Stream.fromFuture(repo.searchVideos(keyword, page: page));
    }

    final path = widget.category != null ? widget.category!.query : '1';
    if (src is CompositeVideoSource) return src.fetchByPathStream(path, page: page);
    if (src is LicensedCatalogVideoSource) return src.fetchByPathStream(path, page: page);
    return Stream.fromFuture(repo.fetchByPath(path, page: page));
  }

  String _itemIdentity(VideoItem item) {
    return '${item.providerKey}|${item.id}|${item.detailUrl}';
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
      _hasMore = true;
      _page = 1;
      _keyword = _searchController.text.trim();
    });

    await _loadPage(reset: true);
  }

  Future<void> _loadPage({required bool reset}) async {
    // 生成本次请求的令牌，用于过期取消检测
    final token = ++_searchToken;

    if (!reset) {
      setState(() {
        _loadingMore = true;
      });
    }

    final pageToLoad = _page;
    final existingItems = List<VideoItem>.from(reset ? [] : _items);
    final existingKeys = existingItems.map(_itemIdentity).toSet();

    try {
      final stream = _requestPageStream(pageToLoad);
      bool receivedFirst = false;
      int newlyAddedCount = 0; // 记录本页真实新增的数量，用于判断 hasMore

      await for (final results in stream) {
        if (!mounted || token != _searchToken) return; // 令牌失效，安静退出

        final newDistinct = results.where((e) => !existingKeys.contains(_itemIdentity(e))).toList();

        if (newDistinct.isNotEmpty) {
          existingKeys.addAll(newDistinct.map(_itemIdentity));
          newlyAddedCount += newDistinct.length;

          setState(() {
            _error = null;
            if (reset && !receivedFirst) {
               _items.clear(); // 真正来了数据才清盘，避免闪白
            }
            if (reset && _items.isEmpty) {
              _items.addAll(existingItems);
            }
            _items.addAll(newDistinct); 
            
            // 只有当真正拿到了数据，UI 才会从大转圈立刻切换为列表！保持原版优秀体验
            if (_items.isNotEmpty) {
               _loading = false;
               receivedFirst = true;
            }
          });
        }
      }

      if (!mounted || token != _searchToken) return;

      setState(() {
        _loading = false;
        _loadingMore = false;
        _page = pageToLoad + 1;
        
        // 判断是否到底了
        if (!receivedFirst) {
          _hasMore = false; // 所有源都搜尽没给数据
        } else {
          _hasMore = newlyAddedCount >= _pageSize; // 标准分页判断
        }
      });
      
    } catch (e) {
      if (!mounted || token != _searchToken) return;
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
    // 记录搜索词到历史
    if (_keyword.trim().isNotEmpty) {
      _historyService.add(_keyword.trim()).then((_) {
        if (mounted) {
          setState(() {
            _searchHistory = List.of(_historyService.history);
          });
        }
      });
    }
    // 关闭建议面板
    _searchFocusNode.unfocus();
    setState(() => _showSuggestions = false);
    _reload();
  }

  void _applySuggestion(String keyword) {
    _debounceTimer?.cancel();
    _searchController.text = keyword;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: keyword.length),
    );
    _keyword = keyword;
    _searchFocusNode.unfocus();
    setState(() => _showSuggestions = false);
    _doSearch();
  }

  Future<void> _removeHistory(String keyword) async {
    await _historyService.remove(keyword);
    if (mounted) {
      setState(() {
        _searchHistory = List.of(_historyService.history);
        _suggestions = _historyService.suggest(_searchController.text);
      });
    }
  }

  Future<void> _clearAllHistory() async {
    await _historyService.clear();
    if (mounted) {
      setState(() {
        _searchHistory = [];
        _suggestions = [];
      });
    }
  }

  void _openDetail(VideoItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoDetailPage(item: item),
      ),
    );
  }

  // ───────────────────────── UI 组件 ──────────────────────────

  Widget _buildCover(VideoItem item) {
    if (item.cover.isEmpty) {
      return _placeholder();
    }
    return Image.network(
      item.cover,
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

  String _metaText(VideoItem item) {
    final parts = <String>[
      if (item.category.trim().isNotEmpty) item.category.trim(),
      if (item.yearText.trim().isNotEmpty) item.yearText.trim(),
      if (item.area.trim().isNotEmpty) item.area.trim(),
    ];
    return parts.join(' · ');
  }

  Widget _sourceBadge(String text) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _aggregateBadge(VideoItem item) {
    if (!item.isAggregated) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF6FF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '聚合 ${item.mergedSourceCount} 源',
        style: const TextStyle(
          fontSize: 10,
          color: Color(0xFF1976D2),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // 恢复原版优秀的 ItemCard UI，避免 Expanded 带来的排版溢出灾难
  Widget _buildItemCard(VideoItem item) {
    final description = item.intro.isNotEmpty
        ? item.intro
        : item.remark.isNotEmpty
            ? item.remark
            : item.subtitle;

    final meta = _metaText(item);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openDetail(item),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF0F2F5)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08000000),
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildCover(item),
                      Positioned(
                        left: 8,
                        top: 8,
                        child: _sourceBadge(item.sourceName),
                      ),
                      Positioned(
                        right: 8,
                        top: 8,
                        child: _aggregateBadge(item),
                      ),
                      if (item.remark.trim().isNotEmpty)
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 8,
                          child: Align(
                            alignment: Alignment.bottomLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.45),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                item.remark,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (meta.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    meta,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                      height: 1.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (description.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
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
          '没有找到匹配内容',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.grey[700],
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '可以换个关键词再试试，或尝试清空缓存',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(strokeWidth: 3.5),
          ),
          const SizedBox(height: 24),
          const Text(
            '正在并发现网全搜...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4A5568),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '速度起飞，结果马上涌现',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width >= 1200 ? 5 : width >= 900 ? 4 : width >= 650 ? 3 : 2;
        final aspectRatio = crossAxisCount <= 2 ? 0.74 : 0.80;

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
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: aspectRatio,
                ),
              ),
            ),
            SliverToBoxAdapter(child: _buildFooter()),
          ],
        );
      },
    );
  }

  // ─────────────────── 搜索建议/历史面板 ──────────────────────

  Widget _buildSuggestionsPanel() {
    final list = _suggestions;
    final hasHistory = _searchHistory.isNotEmpty;
    final isFiltering = _searchController.text.trim().isNotEmpty;

    if (!isFiltering && !hasHistory) return const SizedBox.shrink();

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 280),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 面板头部
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
              child: Row(
                children: [
                  Icon(
                    isFiltering ? Icons.search : Icons.history,
                    size: 16,
                    color: Colors.grey[500],
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isFiltering ? '搜索建议' : '搜索历史',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (!isFiltering && hasHistory)
                    TextButton(
                      onPressed: _clearAllHistory,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        '清空',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 0.5),
            // 建议列表
            Flexible(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final kw = list[index];
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    leading: Icon(
                      isFiltering ? Icons.search : Icons.history_rounded,
                      size: 18,
                      color: Colors.grey[400],
                    ),
                    title: Text(
                      kw,
                      style: const TextStyle(fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.close, size: 16, color: Colors.grey[400]),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _removeHistory(kw),
                    ),
                    onTap: () => _applySuggestion(kw),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── 构建 Build ────────────────────────────

  @override
  Widget build(BuildContext context) {
    // 优先使用类别标题，如果没有，则判断搜索词
    final title = widget.category?.title ?? 
        (_keyword.isNotEmpty ? '搜索结果' : '影视搜索');
    final description = widget.category?.description ?? 
        '支持多站点搜索与自动聚合，结果会显示来源与聚合状态';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FB),
      appBar: AppBar(
        title: Text(_loading ? title : '$title（${_items.length}）'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索栏 + 建议面板
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                // 搜索框
                TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) {
                    _debounceTimer?.cancel();
                    _keyword = _searchController.text.trim();
                    _doSearch();
                  },
                  decoration: InputDecoration(
                    hintText: '输入电影 / 电视剧 / 动漫 / 综艺关键词',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _debounceTimer?.cancel();
                              _searchController.clear();
                              _keyword = '';
                              setState(() => _suggestions = _historyService.suggest(''));
                              _reload();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF1976D2), width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                
                // 保留原版的副标题描述信息 (如果没有显示建议列表)
                if (!_showSuggestions && description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      description,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ),
                 ],

                // 建议/历史下拉面板
                if (_showSuggestions) ...[
                  const SizedBox(height: 4),
                  _buildSuggestionsPanel(),
                ],
              ],
            ),
          ),
          
          // 内容区
          Expanded(
            child: _loading
                ? _buildLoadingState()
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
                        child: _items.isEmpty
                            ? _buildEmptyState()
                            : _buildGrid(),
                      ),
          ),
        ],
      ),
    );
  }
}