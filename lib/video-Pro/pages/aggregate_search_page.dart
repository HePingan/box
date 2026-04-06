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

  /// 封面缓存：同一个 source + vodId 只请求一次
  final Map<String, Future<String?>> _coverFutureCache = {};

  List<_AggregateResult> _results = [];
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

      final futures = sources.map<Future<_AggregateResult?>>((source) async {
        try {
          final items = await VideoApiService.searchVideo(source.url, keyword);
          if (items.isNotEmpty) {
            return _AggregateResult(source, items);
          }
          return null;
        } catch (e) {
          debugPrint('聚合搜索失败: ${source.name} -> $e');
          return null;
        }
      }).toList();

      final responses = await Future.wait(futures);

      if (!mounted) return;

      setState(() {
        _results = responses.whereType<_AggregateResult>().toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _results = [];
        _errorMessage = '搜索失败：$e';
      });
    }
  }

  Future<String?> _coverUrlFor(VodItem video, VideoSource source) {
    final cacheKey = '${source.id}_${source.url}_${source.detailUrl}_${video.vodId}';

    final cached = _coverFutureCache[cacheKey];
    if (cached != null) return cached;

    final future = _loadCoverUrl(video, source);
    _coverFutureCache[cacheKey] = future;
    return future;
  }

  Future<String?> _loadCoverUrl(VodItem video, VideoSource source) async {
    // 1) 优先用结果列表里的封面
    final direct = _resolveImageUrl(source, video.vodPic);
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    // 2) 列表没有封面，去详情接口补
    if (video.vodId <= 0) return null;

    try {
      final detailBaseUrl =
          source.detailUrl.trim().isNotEmpty ? source.detailUrl : source.url;

      final detail = await VideoApiService.fetchDetail(
        detailBaseUrl,
        video.vodId,
      );

      if (detail == null) return null;

      final detailCover = _resolveImageUrl(source, detail.vodPic);
      if (detailCover != null && detailCover.isNotEmpty) {
        return detailCover;
      }

      return null;
    } catch (e) {
      debugPrint('聚合搜索封面加载失败: ${video.vodName} -> $e');
      return null;
    }
  }

  String? _resolveImageUrl(VideoSource source, String? rawUrl) {
    if (rawUrl == null) return null;

    var url = rawUrl.trim().replaceAll('\\', '');
    if (url.isEmpty) return null;

    // 协议相对地址：//img.xxx.com/a.jpg
    if (url.startsWith('//')) {
      return 'https:$url';
    }

    // 已经是绝对地址
    final parsed = Uri.tryParse(url);
    if (parsed != null && parsed.hasScheme) {
      return url;
    }

    // 相对路径：尝试用详情页 / 源地址补全
    final baseUrls = <String>[
      source.detailUrl.trim(),
      source.url.trim(),
    ];

    for (final base in baseUrls) {
      if (base.isEmpty) continue;

      final baseUri = Uri.tryParse(base);
      if (baseUri == null || !baseUri.hasScheme) continue;

      try {
        return baseUri.resolve(url).toString();
      } catch (_) {
        // 继续尝试下一个 base
      }
    }

    // 兜底：原样返回
    return url;
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
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _performAggregateSearch,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在全网搜寻，请稍候...'),
                ],
              ),
            )
          : !_hasSearched
              ? Center(
                  child: Text(
                    '输入影片名称，回车全网搜索',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                )
              : _errorMessage != null
                  ? _buildErrorView()
                  : _results.isEmpty
                      ? Center(
                          child: Text(
                            '全网未找到相关资源',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _results.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final res = _results[index];
                            return _buildSourceSection(res.source, res.items);
                          },
                        ),
    );
  }

  Widget _buildErrorView() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(
          Icons.error_outline_rounded,
          size: 72,
          color: Colors.grey.shade400,
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            _errorMessage ?? '搜索失败',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 15,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton.icon(
            onPressed: _performAggregateSearch,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重试'),
          ),
        ),
      ],
    );
  }

  Widget _buildSourceSection(VideoSource source, List<VodItem> items) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                const Icon(Icons.source_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    source.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '共 ${items.length} 个结果',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 210,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, idx) {
                final video = items[idx];
                return _AggregateVideoCard(
                  source: source,
                  video: video,
                  coverUrlFuture: _coverUrlFor(video, source),
                  onTap: video.vodId <= 0
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => VideoDetailPage(
                                source: source,
                                vodId: video.vodId,
                              ),
                            ),
                          );
                        },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AggregateVideoCard extends StatelessWidget {
  final VideoSource source;
  final VodItem video;
  final Future<String?>? coverUrlFuture;
  final VoidCallback? onTap;

  const _AggregateVideoCard({
    required this.source,
    required this.video,
    required this.coverUrlFuture,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 96,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: FutureBuilder<String?>(
                    future: coverUrlFuture,
                    builder: (context, snapshot) {
                      final imageUrl = snapshot.data?.trim();

                      if (imageUrl == null || imageUrl.isEmpty) {
                        return _buildPlaceholder();
                      }

                      return Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          debugPrint('聚合搜索封面加载失败: ${video.vodName} -> $imageUrl');
                          return _buildPlaceholder();
                        },
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            color: Colors.grey.shade200,
                            alignment: Alignment.center,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              video.vodName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              video.vodRemarks ?? source.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: Icon(
        Icons.movie_outlined,
        size: 30,
        color: Colors.grey.shade600,
      ),
    );
  }
}