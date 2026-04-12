import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controller/video_controller.dart';
import '../models/aggregate_result.dart';
import '../models/video_source.dart';
import '../services/video_api_service.dart';
import 'search/search_empty_state.dart';
import 'search/search_utils.dart'; // 涉及 loadSearchVideoCover
import 'aggregate_search/aggregate_search_source_section.dart';
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

      final futures = sources.map<Future<List<AggregateResult>>>((source) async {
        try {
          final items = await VideoApiService.searchVideo(source.url, keyword);
          return items.map((video) => AggregateResult(source: source, video: video)).toList(growable: false);
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
        builder: (_) => VideoDetailPage(source: result.source, vodId: result.video.vodId),
      ),
    );
  }

  Widget _buildResultList() {
    final sections = _groupResultsBySource();
    return ListView.separated(
      padding: const EdgeInsets.only(top: 6, bottom: 18),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: sections.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final entry = sections[index];
        return AggregateSearchSourceSection(
          source: entry.key,
          results: entry.value,
          // 🏆 优化：移除外层无用缓存池，直接实时计算返回
          coverUrlFor: (result) => loadSearchVideoCover(result.video, result.source),
          onTapVideo: _openDetail,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(hintText: '全网多源聚合搜索...', border: InputBorder.none),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _performAggregateSearch(),
        ),
        actions: [
          IconButton(tooltip: '搜索', icon: const Icon(Icons.search), onPressed: _performAggregateSearch),
          IconButton(
            tooltip: '清空',
            icon: const Icon(Icons.clear_rounded),
            onPressed: () {
              _searchController.clear();
              setState(() {
                _results = [];
                _hasSearched = false;
                _errorMessage = null;
              });
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(height: 16), Text('正在全网搜寻，请稍候...')]))
          : !_hasSearched
              ? SearchEmptyState(message: '输入影片名称，回车全网搜索', icon: Icons.travel_explore_rounded)
              : _errorMessage != null
                  ? _buildErrorView()
                  : _results.isEmpty
                      ? SearchEmptyState(message: '全网未找到相关资源', actionLabel: '重新搜索', onAction: _performAggregateSearch)
                      : _buildResultList(),
    );
  }

  Widget _buildErrorView() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(Icons.error_outline_rounded, size: 72, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        Center(child: Text(_errorMessage ?? '搜索失败', style: TextStyle(color: Colors.grey.shade700, fontSize: 15), textAlign: TextAlign.center)),
        const SizedBox(height: 16),
        Center(child: ElevatedButton.icon(onPressed: _performAggregateSearch, icon: const Icon(Icons.refresh_rounded), label: const Text('重试'))),
      ],
    );
  }
}