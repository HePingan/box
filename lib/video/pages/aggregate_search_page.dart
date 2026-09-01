import 'package:cached_network_image/cached_network_image.dart';
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
import 'aggregate_search/aggregate_search_video_card.dart'
    show kAggregateCoverDecodeWidth;
import 'search/search_empty_state.dart';
import 'search/search_history_view.dart';
import 'search/search_input_bar.dart';
import 'search/search_utils.dart';
import 'video_detail_page.dart';

class AggregateSearchPage extends StatefulWidget {
  const AggregateSearchPage({super.key, this.prefillKeyword});

  /// 预填搜索关键词(从榜单点击等场景传入)。
  final String? prefillKeyword;

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
  int _completedSourceCount = 0;
  int _totalSourceCount = 0;

  List<String> _recentKeywords = const [];
  List<String> _hotKeywords = const [];

  AggregateSortMode _sortMode = AggregateSortMode.hitCount;
  bool _multiSourceOnly = false;

  @override
  void initState() {
    super.initState();
    if (widget.prefillKeyword != null && widget.prefillKeyword!.isNotEmpty) {
      _searchController.text = widget.prefillKeyword!;
    }
    _loadHistory();
    if (widget.prefillKeyword != null && widget.prefillKeyword!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _searchWithKeyword(widget.prefillKeyword!);
      });
    }
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
      _completedSourceCount = 0;
      _totalSourceCount = 0;
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

      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _totalSourceCount = sources.length;
      });

      const concurrency = 4;
      var cursor = 0;
      var failed = 0;
      var completed = 0;
      final aggregated = <AggregateResult>[];

      Future<void> worker() async {
        while (true) {
          final index = cursor++;
          if (index >= sources.length) return;
          final source = sources[index];
          List<AggregateResult>? sourceResults;
          var sourceFailed = false;
          try {
            // 聚合搜索走快速失败：单源单次尝试、超时收紧到 8s，
            // 由其他源兜底，避免死源被反复重试拖慢整体出结果。
            final items = await VideoApiService.searchVideo(
              source.url,
              keyword,
              fastFail: true,
            );
            sourceResults = items
                .map((video) => AggregateResult(source: source, video: video))
                .toList(growable: false);
          } catch (_) {
            sourceFailed = true;
          }

          // 计数必须先落账：`completed` 是本世代闭包的局部变量，与新世代无关。
          // 若在自增前就 return，本世代剩余 worker 永远凑不满 sources.length，
          // 该世代的收尾分支（含 _isLoading=false）就再也不会执行。
          completed++;
          if (sourceFailed) failed++;

          // 每个源一回来就渲染，体感“秒出结果”，不再干等最慢的源。
          // 世代已过期只跳过 UI 写入，不影响上面的账。
          if (!mounted || generation != _searchGeneration) return;
          if (sourceResults != null && sourceResults.isNotEmpty) {
            aggregated.addAll(sourceResults);
            // 预热该源封面(前 6 张):滑到时已在缓存,体感秒开。
            // 静默预取,失败无副作用(错误封面走占位图)。
            _precacheCovers(sourceResults.take(6));
          }
          setState(() {
            _completedSourceCount = completed;
            _failedSourceCount = failed;
            _results = List<AggregateResult>.unmodifiable(aggregated);
            if (completed == sources.length) {
              _isLoading = false;
              if (failed == sources.length) {
                _errorMessage = '所有视频源暂时不可用，请稍后重试';
              }
            }
          });
        }
      }

      await Future.wait(
        List.generate(
          sources.length < concurrency ? sources.length : concurrency,
          (_) => worker(),
        ),
      );
      if (!mounted || generation != _searchGeneration) return;

      // 命中结果才计入搜索历史/热词，避免记录无效关键词。
      if (aggregated.isNotEmpty) {
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
      // 自增世代已作废在途 worker，它们会在 :171 提前 return，
      // 永远补不齐 `completed == sources.length`——而那是 `_isLoading = false`
      // 的唯一出口。所以取消方必须自己收尾加载态，否则 spinner 永久转圈。
      _isLoading = false;
      _completedSourceCount = 0;
      _failedSourceCount = 0;
      _totalSourceCount = 0;
    });
  }

  /// 仅测试用：驱动「搜索途中清空」这条路径。
  @visibleForTesting
  void clearSearchForTesting() => _clearSearch();

  /// 预热封面:结果一到就把前几张解码进缓存,用户滑到时秒开。
  /// 与卡片同用 200px 解码宽,预取的即最终展示的那份,零重复解码。
  /// 静默进行,单张失败不影响其它(错误封面走占位图)。
  void _precacheCovers(Iterable<AggregateResult> results) {
    if (!mounted) return;
    for (final result in results) {
      final url = loadSearchVideoCover(result.video, result.source);
      if (url == null || url.isEmpty) continue;
      precacheImage(
        CachedNetworkImageProvider(url, maxWidth: kAggregateCoverDecodeWidth),
        context,
      ).catchError((_) {});
    }
  }

  List<AggregateGroupedResult> _groupedResults() => sortAndFilterGroups(
    groupResultsByFilmName(_results),
    mode: _sortMode,
    multiSourceOnly: _multiSourceOnly,
  );

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
    // 头部控制栏占 index 0，其余为结果组。
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        16,
        8,
        16,
        AppTokens.pageBottomPadding + 32,
      ),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: groups.length + 1,
      separatorBuilder: (_, index) =>
          SizedBox(height: index == 0 ? 8 : 12),
      itemBuilder: (context, index) {
        if (index == 0) return _buildSortFilterBar(groups.length);
        final group = groups[index - 1];
        return AggregateSearchGroupSection(
          group: group,
          coverUrlFor: (result) =>
              loadSearchVideoCover(result.video, result.source),
          onTapVideo: _openDetail,
        );
      },
    );
  }

  /// 结果列表顶部的紧凑排序/筛选条。
  Widget _buildSortFilterBar(int visibleCount) {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                for (final mode in AggregateSortMode.values) ...[
                  _buildSortChip(mode),
                  const SizedBox(width: 8),
                ],
                _buildFilterChip(),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$visibleCount 部',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTokens.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildSortChip(AggregateSortMode mode) {
    final selected = _sortMode == mode;
    return _buildPillButton(
      label: mode.label,
      selected: selected,
      onTap: () {
        if (_sortMode == mode) return;
        setState(() => _sortMode = mode);
      },
    );
  }

  Widget _buildFilterChip() {
    return _buildPillButton(
      label: '只看多源',
      selected: _multiSourceOnly,
      icon: _multiSourceOnly
          ? Icons.check_circle_rounded
          : Icons.filter_alt_outlined,
      onTap: () => setState(() => _multiSourceOnly = !_multiSourceOnly),
    );
  }

  Widget _buildPillButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.fromLTRB(icon != null ? 10 : 14, 7, 14, 7),
        decoration: BoxDecoration(
          color: selected ? AppTokens.violet : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppTokens.violet : const Color(0xFFE7ECF5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 15,
                color: selected ? Colors.white : AppTokens.textSecondary,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppTokens.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryView() {
    return SearchHistoryView(
      recentKeywords: _recentKeywords,
      hotKeywords: _hotKeywords,
      onTapKeyword: _searchWithKeyword,
      onRemoveRecent: _removeHistory,
      onClearRecent: _clearHistory,
      emptyMessage: '输入片名，同时搜索全部可用视频源',
      emptyIcon: Icons.travel_explore_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildHero()),
          SliverToBoxAdapter(
            child: SearchInputBar(
              controller: _searchController,
              hintText: '搜索片名 / 主演',
              onSubmit: _performAggregateSearch,
              onClear: _clearSearch,
              accentColor: AppTokens.violet,
              leadingIcon: Icons.travel_explore_rounded,
              actionIcon: Icons.search_rounded,
              actionLabel: '全网搜',
            ),
          ),
          if (_hasSearched || _isLoading)
            SliverToBoxAdapter(child: _buildResultSummary()),
          SliverFillRemaining(
            hasScrollBody: _hasScrollableBody,
            child: !_hasSearched && !_isLoading
                ? _buildHistoryView()
                // 流式渲染：已有结果就先展示列表，即便仍在等待其余源。
                : _results.isNotEmpty
                ? _buildResultList()
                : _isLoading
                ? _AggregateSearchLoading(
                    completed: _completedSourceCount,
                    total: _totalSourceCount,
                  )
                : _errorMessage != null
                ? _buildErrorView()
                : SearchEmptyState(
                    message: '全网未找到相关资源，试试更短片名',
                    actionLabel: '重新搜索',
                    onAction: _performAggregateSearch,
                  ),
          ),
        ],
      ),
    );
  }

  bool get _hasScrollableBody =>
      _hasSearched && _errorMessage == null && _results.isNotEmpty;

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
  const _AggregateSearchLoading({this.completed = 0, this.total = 0});

  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final progressText = total > 0 ? '已搜 $completed/$total 源' : '正在多源聚合搜索...';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(strokeWidth: 2.5),
          const SizedBox(height: 14),
          Text(
            progressText,
            style: const TextStyle(
              color: AppTokens.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
