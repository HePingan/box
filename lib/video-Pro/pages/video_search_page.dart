import 'package:flutter/material.dart';

import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../services/video_api_service.dart';
import 'video_detail_page.dart';

class VideoSearchPage extends StatefulWidget {
  final VideoSource currentSource;

  const VideoSearchPage({
    super.key,
    required this.currentSource,
  });

  @override
  State<VideoSearchPage> createState() => _VideoSearchPageState();
}

class _VideoSearchPageState extends State<VideoSearchPage> {
  final TextEditingController _searchController = TextEditingController();

  final Map<String, Future<String?>> _coverFutureCache = {};

  List<VodItem> _results = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  String? _errorMessage;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _errorMessage = null;
    });

    try {
      final res = await VideoApiService.searchVideo(
        widget.currentSource.url,
        keyword,
      );

      if (!mounted) return;

      setState(() {
        _results = res;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _results = [];
        _isLoading = false;
        _errorMessage = '搜索失败：$e';
      });
    }
  }

  Future<String?> _coverUrlFor(dynamic video) {
    final vodId = _readInt(video, const ['vodId', 'vod_id', 'id']);

    final cacheKey =
        '${widget.currentSource.id}_${widget.currentSource.url}_${widget.currentSource.detailUrl}_$vodId';

    final cached = _coverFutureCache[cacheKey];
    if (cached != null) return cached;

    final future = _loadCoverUrl(video);
    _coverFutureCache[cacheKey] = future;
    return future;
  }

  Future<String?> _loadCoverUrl(dynamic video) async {
    // 1) 优先使用搜索结果里自带的封面
    final direct = _resolveImageUrl(
      _readText(video, const [
        'vodPic',
        'vod_pic',
        'pic',
        'cover',
        'image',
        'img',
        'thumb',
        'poster',
        'vod_img',
      ]),
    );

    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    // 2) 如果搜索结果没封面，就去详情页补
    final vodId = _readInt(video, const ['vodId', 'vod_id', 'id']);
    if (vodId <= 0) return null;

    try {
      final detailBaseUrl = widget.currentSource.detailUrl.trim().isNotEmpty
          ? widget.currentSource.detailUrl
          : widget.currentSource.url;

      final detail = await VideoApiService.fetchDetail(
        detailBaseUrl,
        vodId,
      );

      if (detail == null) return null;

      final detailCover = _resolveImageUrl(detail.vodPic);
      if (detailCover != null && detailCover.isNotEmpty) {
        return detailCover;
      }

      return null;
    } catch (e) {
      debugPrint('搜索页封面加载失败: $vodId -> $e');
      return null;
    }
  }

  String? _resolveImageUrl(String? rawUrl) {
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

    // 相对路径：尝试用详情页/源地址补全
    final baseUrls = <String>[
      widget.currentSource.detailUrl.trim(),
      widget.currentSource.url.trim(),
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
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '在 ${widget.currentSource.name} 中搜索...',
            border: InputBorder.none,
            hintStyle: const TextStyle(fontSize: 15),
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _performSearch(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _performSearch,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_hasSearched
              ? Center(
                  child: Text(
                    '输入关键字开始搜索',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                )
              : _errorMessage != null
                  ? _buildErrorView()
                  : _results.isEmpty
                      ? Center(
                          child: Text(
                            '未找到相关视频',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(12),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: screenWidth > 600 ? 6 : 3,
                            childAspectRatio: 0.55,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: _results.length,
                          itemBuilder: (context, index) {
                            final video = _results[index];
                            return _SearchResultCard(
                              title: _readText(video, const [
                                    'vodName',
                                    'vod_name',
                                    'name',
                                    'title',
                                  ]) ??
                                  '未命名',
                              subtitle: _readText(video, const [
                                'vodRemarks',
                                'vod_remarks',
                                'remarks',
                                'remark',
                                'typeName',
                                'type_name',
                              ]),
                              coverUrlFuture: _coverUrlFor(video),
                              onTap: () {
                                final vodId = _readInt(
                                  video,
                                  const ['vodId', 'vod_id', 'id'],
                                );

                                if (vodId <= 0) return;

                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => VideoDetailPage(
                                      source: widget.currentSource,
                                      vodId: vodId,
                                    ),
                                  ),
                                );
                              },
                            );
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
            onPressed: _performSearch,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重试'),
          ),
        ),
      ],
    );
  }

  String? _readText(dynamic item, List<String> keys) {
    for (final key in keys) {
      final value = _readDynamicProperty(item, key);
      if (value == null) continue;

      final text = value.toString().trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }
    return null;
  }

  int _readInt(dynamic item, List<String> keys) {
    final text = _readText(item, keys);
    if (text == null) return 0;
    return int.tryParse(text) ?? 0;
  }

  dynamic _readDynamicProperty(dynamic item, String key) {
    if (item == null) return null;

    // Map / JSON
    if (item is Map) {
      return item[key];
    }

    // 动态对象 / VodItem
    try {
      switch (key) {
        case 'vodId':
          return item.vodId;
        case 'vod_id':
          return item.vodId;
        case 'id':
          return item.id;

        case 'vodName':
          return item.vodName;
        case 'vod_name':
          return item.vodName;
        case 'name':
          return item.name;
        case 'title':
          return item.title;

        case 'vodPic':
          return item.vodPic;
        case 'vod_pic':
          return item.vodPic;
        case 'pic':
          return item.pic;
        case 'cover':
          return item.cover;
        case 'image':
          return item.image;
        case 'img':
          return item.img;
        case 'thumb':
          return item.thumb;
        case 'poster':
          return item.poster;
        case 'vod_img':
          return item.vodImg;

        case 'vodRemarks':
          return item.vodRemarks;
        case 'vod_remarks':
          return item.vodRemarks;
        case 'remarks':
          return item.remarks;
        case 'remark':
          return item.remark;

        case 'typeName':
          return item.typeName;
        case 'type_name':
          return item.typeName;

        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }
}

class _SearchResultCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Future<String?>? coverUrlFuture;
  final VoidCallback? onTap;

  const _SearchResultCard({
    required this.title,
    required this.subtitle,
    required this.coverUrlFuture,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SizedBox(
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
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
                        debugPrint('搜索封面加载失败: $title -> $imageUrl');
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
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey.shade300,
      alignment: Alignment.center,
      child: Icon(
        Icons.movie_outlined,
        size: 34,
        color: Colors.grey.shade600,
      ),
    );
  }
}