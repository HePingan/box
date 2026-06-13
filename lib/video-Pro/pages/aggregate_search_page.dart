import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_cards.dart';
import 'package:box/design_system/widgets/app_page_scaffold.dart';

import '../controller/video_controller.dart';
import '../models/aggregate_result.dart';
import '../models/video_source.dart';
import '../services/video_api_service.dart';
import 'aggregate_search/aggregate_search_source_section.dart';
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

  List<AggregateResult> _results = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  String? _errorMessage;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performAggregateSearch() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _results = [];
      _errorMessage = null;
    });

    try {
      final sources = context.read<VideoController>().sources;
      if (sources.isEmpty) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = '暂无可用视频源';
        });
        return;
      }

      final futures = sources.map<Future<List<AggregateResult>>>((
        source,
      ) async {
        try {
          final items = await VideoApiService.searchVideo(source.url, keyword);
          return items
              .map((video) => AggregateResult(source: source, video: video))
              .toList(growable: false);
        } catch (e) {
          return const <AggregateResult>[];
        }
      }).toList();

      final responses = await Future.wait(futures);
      if (!mounted) return;

      setState(() {
        _results = responses.expand((e) => e).toList(growable: false);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '搜索失败：$e';
      });
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _results = [];
      _hasSearched = false;
      _errorMessage = null;
    });
  }

  List<MapEntry<VideoSource, List<AggregateResult>>> _groupResultsBySource() {
    final grouped = <VideoSource, List<AggregateResult>>{};
    for (final result in _results) {
      grouped.putIfAbsent(result.source, () => <AggregateResult>[]).add(result);
    }
    return grouped.entries.toList(growable: false);
  }

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
    final sections = _groupResultsBySource();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        16,
        8,
        16,
        AppTokens.pageBottomPadding + 32,
      ),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: sections.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final entry = sections[index];
        return AggregateSearchSourceSection(
          source: entry.key,
          results: entry.value,
          coverUrlFor: (result) =>
              loadSearchVideoCover(result.video, result.source),
          onTapVideo: _openDetail,
        );
      },
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
                ? const SearchEmptyState(
                    message: '输入片名，同时搜索全部可用视频源',
                    icon: Icons.travel_explore_rounded,
                  )
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
      leading: IconButton.filledTonal(
        onPressed: () => Navigator.maybePop(context),
        icon: const Icon(Icons.arrow_back_rounded),
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
    final sources = _groupResultsBySource().length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          AppStatusPill(
            label: _isLoading ? '正在聚合' : '${_results.length} 个结果',
            icon: _isLoading ? Icons.sync_rounded : Icons.movie_filter_rounded,
            color: AppTokens.violet,
          ),
          AppStatusPill(
            label: _isLoading ? '多源并发' : '$sources 个来源',
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
