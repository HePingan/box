import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_back_button.dart';
import 'package:box/design_system/widgets/app_cards.dart';
import 'package:box/design_system/widgets/app_page_scaffold.dart';

import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../services/video_api_service.dart';
import 'search/search_empty_state.dart';
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

  List<VodItem> _results = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  String? _errorMessage;
  int _searchGeneration = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
          SliverToBoxAdapter(child: _buildSearchBox()),
          if (_hasSearched || _isLoading)
            SliverToBoxAdapter(child: _buildResultSummary()),
          SliverFillRemaining(
            hasScrollBody: _hasScrollableBody,
            child: _isLoading
                ? const _VideoSearchLoading()
                : !_hasSearched
                ? const SearchEmptyState(
                    message: '输入片名，在当前源内快速搜索',
                    icon: Icons.manage_search_rounded,
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

  Widget _buildSearchBox() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7ECF5)),
        boxShadow: AppTokens.shadowSm(color: AppTokens.primaryBlue),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: AppTokens.primaryBlue),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '搜索片名 / 关键词',
                border: InputBorder.none,
                isDense: true,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _performSearch(),
            ),
          ),
          IconButton(
            tooltip: '清空',
            icon: const Icon(Icons.close_rounded),
            onPressed: _clearSearch,
          ),
          FilledButton.icon(
            onPressed: _performSearch,
            icon: const Icon(Icons.manage_search_rounded, size: 18),
            label: const Text('搜索'),
          ),
        ],
      ),
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
