import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_back_button.dart';
import 'package:box/design_system/widgets/app_cards.dart';
import 'package:box/design_system/widgets/app_page_scaffold.dart';

import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../services/search_history_repository.dart';
import '../services/video_api_service.dart';
import 'search/search_empty_state.dart';
import 'search/search_history_view.dart';
import 'search/search_input_bar.dart';
import 'search/search_result_card.dart';
import 'search/search_utils.dart';
import 'video_detail_page.dart';

class VideoSearchPage extends StatefulWidget {
  final VideoSource currentSource;

  const VideoSearchPage({super.key, required this.currentSource});

  @override
  State<VideoSearchPage> createState() => _VideoSearchPageState();
}

class _VideoSearchPageState extends State<VideoSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  // 源内搜索用独立历史 box，与聚合搜索互不污染。
  final SearchHistoryRepository _historyRepo = SearchHistoryRepository(
    boxName: 'video_source_search_history_box',
  );

  List<VodItem> _results = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  String? _errorMessage;
  int _searchGeneration = 0;

  List<String> _recentKeywords = const [];
  List<String> _hotKeywords = const [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    await _historyRepo.init();
    if (!mounted) return;
    setState(() {
      _recentKeywords = _historyRepo.recentKeywords();
      _hotKeywords = _historyRepo.hotKeywords();
    });
  }

  Future<void> _refreshHistoryState() async {
    if (!mounted) return;
    setState(() {
      _recentKeywords = _historyRepo.recentKeywords();
      _hotKeywords = _historyRepo.hotKeywords();
    });
  }

  Future<void> _searchWithKeyword(String keyword) async {
    _searchController.text = keyword;
    await _performSearch();
  }

  Future<void> _removeHistory(String keyword) async {
    await _historyRepo.remove(keyword);
    await _refreshHistoryState();
  }

  Future<void> _clearHistory() async {
    await _historyRepo.clear();
    await _refreshHistoryState();
  }

  Future<void> _performSearch() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;

    final generation = ++_searchGeneration;
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _errorMessage = null;
      _results = [];
    });

    try {
      final res = await VideoApiService.searchVideo(
        widget.currentSource.url,
        keyword,
      );

      if (!mounted || generation != _searchGeneration) return;

      setState(() {
        _results = res;
        _isLoading = false;
      });

      // 命中结果才记历史，避免记录无效关键词。
      if (res.isNotEmpty) {
        await _historyRepo.record(keyword);
        await _refreshHistoryState();
      }
    } catch (e) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = [];
        _isLoading = false;
        _errorMessage = '搜索失败：$e';
      });
    }
  }

  void _clearSearch() {
    _searchGeneration++;
    _searchController.clear();
    setState(() {
      _results = [];
      _hasSearched = false;
      _errorMessage = null;
    });
  }

  void _openDetail(VodItem video) {
    if (video.vodId <= 0) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            VideoDetailPage(source: widget.currentSource, vodId: video.vodId),
      ),
    );
  }

  String _titleFor(VodItem video) {
    final title = video.vodName.trim();
    return title.isNotEmpty ? title : '未命名';
  }

  String? _subtitleFor(VodItem video) {
    final remarks = video.vodRemarks?.trim();
    if (remarks != null && remarks.isNotEmpty) return remarks;
    final typeName = video.typeName?.trim();
    return (typeName != null && typeName.isNotEmpty) ? typeName : null;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return AppPageScaffold(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildHero()),
          SliverToBoxAdapter(
            child: SearchInputBar(
              controller: _searchController,
              hintText: '搜索片名 / 关键词',
              onSubmit: _performSearch,
              onClear: _clearSearch,
              accentColor: AppTokens.primaryBlue,
              leadingIcon: Icons.search_rounded,
              actionIcon: Icons.manage_search_rounded,
              actionLabel: '搜索',
            ),
          ),
          if (_hasSearched || _isLoading)
            SliverToBoxAdapter(child: _buildResultSummary()),
          SliverFillRemaining(
            hasScrollBody: _hasScrollableBody,
            child: _isLoading
                ? const _VideoSearchLoading()
                : !_hasSearched
                ? SearchHistoryView(
                    recentKeywords: _recentKeywords,
                    hotKeywords: _hotKeywords,
                    onTapKeyword: _searchWithKeyword,
                    onRemoveRecent: _removeHistory,
                    onClearRecent: _clearHistory,
                    emptyMessage: '输入片名，在当前源内快速搜索',
                    emptyIcon: Icons.manage_search_rounded,
                  )
                : _errorMessage != null
                ? _buildErrorView()
                : _results.isEmpty
                ? SearchEmptyState(
                    message: '未找到相关视频，换个关键词试试',
                    actionLabel: '重新搜索',
                    onAction: _performSearch,
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      16,
                      8,
                      16,
                      AppTokens.pageBottomPadding + 32,
                    ),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: screenWidth > 600 ? 6 : 3,
                      childAspectRatio: 0.55,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final video = _results[index];
                      return SearchResultCard(
                        title: _titleFor(video),
                        subtitle: _subtitleFor(video),
                        coverUrl: loadSearchVideoCover(
                          video,
                          widget.currentSource,
                        ),
                        onTap: () => _openDetail(video),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  bool get _hasScrollableBody =>
      !_isLoading &&
      _hasSearched &&
      _errorMessage == null &&
      _results.isNotEmpty;

  Widget _buildHero() {
    return AppLightHeroCard(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      eyebrow: 'SOURCE SEARCH',
      title: '源内搜索',
      subtitle: '${widget.currentSource.name} · 轻量结果卡片 · 直达播放详情',
      badge: '视频',
      accentGradient: AppTokens.blueGradient,
      leading: AppBackButton(
        onPressed: () => Navigator.maybePop(context),
        label: '源内搜索',
      ),
      actions: const [
        AppStatusPill(
          label: '当前源',
          icon: Icons.source_rounded,
          color: AppTokens.primaryBlue,
        ),
      ],
    );
  }

  Widget _buildResultSummary() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          AppStatusPill(
            label: _isLoading ? '正在搜索' : '${_results.length} 个结果',
            icon: _isLoading ? Icons.sync_rounded : Icons.movie_filter_rounded,
            color: AppTokens.violet,
          ),
          AppStatusPill(
            label: widget.currentSource.name,
            icon: Icons.source_rounded,
            color: AppTokens.primaryBlue,
          ),
          if (_searchController.text.trim().isNotEmpty)
            AppStatusPill(
              label: _searchController.text.trim(),
              icon: Icons.tag_rounded,
              color: AppTokens.orange,
            ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return SearchEmptyState(
      message: _errorMessage ?? '搜索失败',
      icon: Icons.error_outline_rounded,
      actionLabel: '重试',
      onAction: _performSearch,
    );
  }
}

class _VideoSearchLoading extends StatelessWidget {
  const _VideoSearchLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(strokeWidth: 2.5),
          SizedBox(height: 14),
          Text(
            '正在搜索当前视频源...',
            style: TextStyle(
              color: AppTokens.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
