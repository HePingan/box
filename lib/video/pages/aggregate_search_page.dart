import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_back_button.dart';
import 'package:box/design_system/widgets/app_cards.dart';
import 'package:box/design_system/widgets/app_page_scaffold.dart';

import '../controller/video_controller.dart';
import '../models/aggregate_grouped_result.dart';
import '../models/aggregate_result.dart';
import '../services/search_history_repository.dart';
import '../services/video_api_service.dart';
import 'aggregate_search/aggregate_search_group_section.dart';
import 'search/search_empty_state.dart';
import 'search/search_utils.dart';
import 'video_detail_page.dart';

class AggregateSearchPage extends StatefulWidget {
  const AggregateSearchPage({super.key});

  @override
  State<AggregateSearchPage> createState() => _AggregateSearchPageState();
}

class _AggregateSearchPageState extends State<AggregateSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final SearchHistoryRepository _historyRepo = SearchHistoryRepository();

  List<AggregateResult> _results = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  String? _errorMessage;
  int _searchGeneration = 0;
  int _failedSourceCount = 0;

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
    await _performAggregateSearch();
  }

  Future<void> _removeHistory(String keyword) async {
    await _historyRepo.remove(keyword);
    await _refreshHistoryState();
  }

  Future<void> _clearHistory() async {
    await _historyRepo.clear();
    await _refreshHistoryState();
  }

  Future<void> _performAggregateSearch() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;
    final generation = ++_searchGeneration;
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _results = [];
      _errorMessage = null;
      _failedSourceCount = 0;
    });

    try {
      final sources = context
          .read<VideoController>()
          .sources
          .where((source) => source.isAvailable)
          .toList(growable: false);
      if (sources.isEmpty) {
        if (!mounted || generation != _searchGeneration) return;
        setState(() {
          _isLoading = false;
          _errorMessage = '暂无可用视频源';
        });
        return;
      }

      const concurrency = 4;
      var cursor = 0;
      var failed = 0;
      final responses = <List<AggregateResult>>[];

      Future<void> worker() async {
        while (true) {
          final index = cursor++;
          if (index >= sources.length) return;
          final source = sources[index];
          try {
            final items = await VideoApiService.searchVideo(
              source.url,
              keyword,
            ).timeout(const Duration(seconds: 12));
            responses.add(
              items
                  .map((video) => AggregateResult(source: source, video: video))
                  .toList(growable: false),
            );
          } catch (_) {
            failed++;
          }
        }
      }

      await Future.wait(
        List.generate(
          sources.length < concurrency ? sources.length : concurrency,
          (_) => worker(),
        ),
      );
      if (!mounted || generation != _searchGeneration) return;

      final results = responses
          .expand((items) => items)
          .toList(growable: false);
      setState(() {
        _results = results;
        _failedSourceCount = failed;
        _isLoading = false;
        if (failed == sources.length) {
          _errorMessage = '所有视频源暂时不可用，请稍后重试';
        }
      });

      // 命中结果才计入搜索历史/热词，避免记录无效关键词。
      if (results.isNotEmpty) {
        await _historyRepo.record(keyword);
        await _refreshHistoryState();
      }
    } catch (_) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '搜索请求失败，请检查网络后重试';
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

  List<AggregateGroupedResult> _groupedResults() =>
      groupResultsByFilmName(_results);

  void _openDetail(AggregateResult result) {
    if (result.video.vodId <= 0) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            VideoDetailPage(source: result.source, vodId: result.video.vodId),
      ),
    );
  }

  Widget _buildResultList() {
    final groups = _groupedResults();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        16,
        8,
        16,
        AppTokens.pageBottomPadding + 32,
      ),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: groups.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final group = groups[index];
        return AggregateSearchGroupSection(
          group: group,
          coverUrlFor: (result) =>
              loadSearchVideoCover(result.video, result.source),
          onTapVideo: _openDetail,
        );
      },
    );
  }

  Widget _buildHistoryView() {
    final hasRecent = _recentKeywords.isNotEmpty;
    final hasHot = _hotKeywords.isNotEmpty;

    if (!hasRecent && !hasHot) {
      return const SearchEmptyState(
        message: '输入片名，同时搜索全部可用视频源',
        icon: Icons.travel_explore_rounded,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        16,
        8,
        16,
        AppTokens.pageBottomPadding + 32,
      ),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (hasHot) ...[
          _buildHistoryHeader(
            title: '热门搜索',
            icon: Icons.local_fire_department_rounded,
            color: AppTokens.orange,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _hotKeywords.length; i++)
                _buildKeywordChip(
                  label: _hotKeywords[i],
                  leading: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: i < 3 ? AppTokens.orange : AppTokens.textSecondary,
                    ),
                  ),
                  onTap: () => _searchWithKeyword(_hotKeywords[i]),
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        if (hasRecent) ...[
          Row(
            children: [
              Expanded(
                child: _buildHistoryHeader(
                  title: '最近搜索',
                  icon: Icons.history_rounded,
                  color: AppTokens.primaryBlue,
                ),
              ),
              TextButton.icon(
                onPressed: _clearHistory,
                icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                label: const Text('清空'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTokens.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final keyword in _recentKeywords)
                _buildKeywordChip(
                  label: keyword,
                  onTap: () => _searchWithKeyword(keyword),
                  onDeleted: () => _removeHistory(keyword),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildHistoryHeader({
    required String title,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppTokens.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildKeywordChip({
    required String label,
    required VoidCallback onTap,
    Widget? leading,
    VoidCallback? onDeleted,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: EdgeInsets.fromLTRB(12, 8, onDeleted != null ? 6 : 12, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE7ECF5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading, const SizedBox(width: 6)],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.textPrimary,
                ),
              ),
            ),
            if (onDeleted != null) ...[
              const SizedBox(width: 2),
              GestureDetector(
                onTap: onDeleted,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.close_rounded,
                    size: 15,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                ? const _AggregateSearchLoading()
                : !_hasSearched
                ? _buildHistoryView()
                : _errorMessage != null
                ? _buildErrorView()
                : _results.isEmpty
                ? SearchEmptyState(
                    message: '全网未找到相关资源，试试更短片名',
                    actionLabel: '重新搜索',
                    onAction: _performAggregateSearch,
                  )
                : _buildResultList(),
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
      eyebrow: 'AGGREGATE SEARCH',
      title: '聚合搜索',
      subtitle: '多源并发查找 · 按来源分组 · 直达播放详情',
      badge: '全网',
      accentGradient: AppTokens.neonVioletGradient,
      leading: AppBackButton(
        onPressed: () => Navigator.maybePop(context),
        label: '聚合搜索',
      ),
      actions: const [
        AppStatusPill(
          label: '多源',
          icon: Icons.hub_rounded,
          color: AppTokens.violet,
        ),
        AppStatusPill(
          label: '分组',
          icon: Icons.view_column_rounded,
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
        boxShadow: AppTokens.shadowSm(color: AppTokens.violet),
      ),
      child: Row(
        children: [
          const Icon(Icons.travel_explore_rounded, color: AppTokens.violet),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '搜索片名 / 主演',
                border: InputBorder.none,
                isDense: true,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _performAggregateSearch(),
            ),
          ),
          IconButton(
            tooltip: '清空',
            icon: const Icon(Icons.close_rounded),
            onPressed: _clearSearch,
          ),
          FilledButton.icon(
            onPressed: _performAggregateSearch,
            icon: const Icon(Icons.search_rounded, size: 18),
            label: const Text('全网搜'),
          ),
        ],
      ),
    );
  }

  Widget _buildResultSummary() {
    final groups = _groupedResults();
    final sources = <String>{
      for (final r in _results)
        r.source.id.trim().isNotEmpty && r.source.id.trim() != 'null'
            ? r.source.id.trim()
            : (r.source.url.trim().isNotEmpty
                  ? r.source.url.trim()
                  : r.source.name.trim()),
    }.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          AppStatusPill(
            label: _isLoading ? '正在聚合' : '${groups.length} 部影片',
            icon: _isLoading ? Icons.sync_rounded : Icons.movie_filter_rounded,
            color: AppTokens.violet,
          ),
          AppStatusPill(
            label: _isLoading ? '多源并发' : '$sources 个来源',
            icon: Icons.source_rounded,
            color: AppTokens.primaryBlue,
          ),
          if (_failedSourceCount > 0 && !_isLoading)
            AppStatusPill(
              label: '$_failedSourceCount 个源不可用',
              icon: Icons.warning_amber_rounded,
              color: AppTokens.orange,
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
      onAction: _performAggregateSearch,
    );
  }
}

class _AggregateSearchLoading extends StatelessWidget {
  const _AggregateSearchLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(strokeWidth: 2.5),
          SizedBox(height: 14),
          Text(
            '正在多源聚合搜索...',
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
