import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controller/video_controller.dart';
import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../services/video_api_service.dart';
import 'video_detail_page.dart';

class AggregateSearchPage extends StatefulWidget {
  const AggregateSearchPage({super.key});

  @override
  State<AggregateSearchPage> createState() => _AggregateSearchPageState();
}

class _AggregateResult {
  final VideoSource source;
  final List<VodItem> items;
  _AggregateResult(this.source, this.items);
}

class _AggregateSearchPageState extends State<AggregateSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  List<_AggregateResult> _results = [];
  bool _isLoading = false;
  bool _hasSearched = false;

  Future<void> _performAggregateSearch() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _results = [];
    });

    final sources = context.read<VideoController>().sources;
    if (sources.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    // 并发请求所有源进行搜索
    final futures = sources.map((source) async {
      final items = await VideoApiService.searchVideo(source.url, keyword);
      if (items.isNotEmpty) {
        return _AggregateResult(source, items);
      }
      return null;
    });

    final List<_AggregateResult?> responses = await Future.wait(futures);
    
    if (mounted) {
      setState(() {
        _results = responses.whereType<_AggregateResult>().toList();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '全网多源聚合搜索...',
            border: InputBorder.none,
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _performAggregateSearch(),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: _performAggregateSearch),
        ],
      ),
      body: _isLoading
          ? const Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在全网搜寻，请稍候...')
              ],
            ))
          : (!_hasSearched)
              ? Center(child: Text('输入影片名称，回车全网搜索', style: TextStyle(color: Colors.grey.shade500)))
              : _results.isEmpty
                  ? Center(child: Text('全网未找到相关资源', style: TextStyle(color: Colors.grey.shade500)))
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final res = _results[index];
                        return _buildSourceSection(res.source, res.items);
                      },
                    ),
    );
  }

  Widget _buildSourceSection(VideoSource source, List<VodItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.grey.shade100,
          child: Row(
            children: [
              const Icon(Icons.source_rounded, size: 18),
              const SizedBox(width: 8),
              Text(source.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              Text('共 ${items.length} 个结果', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        SizedBox(
          height: 160,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, idx) {
              final video = items[idx];
              return InkWell(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => VideoDetailPage(source: source, vodId: video.vodId)));
                },
                child: SizedBox(
                  width: 90,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                          alignment: Alignment.center,
                          child: const Icon(Icons.movie_outlined, color: Colors.grey),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(video.vodName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}