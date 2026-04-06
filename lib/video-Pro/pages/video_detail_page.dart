import 'package:flutter/material.dart';

import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../services/video_api_service.dart';
import '../widgets/video_play_container.dart';

class VideoDetailPage extends StatefulWidget {
  final VideoSource source;
  final int vodId;

  const VideoDetailPage({
    super.key,
    required this.source,
    required this.vodId,
  });

  @override
  State<VideoDetailPage> createState() => _VideoDetailPageState();
}

class _VideoDetailPageState extends State<VideoDetailPage> {
  VodItem? _fullDetail;
  List<_PlayLine> _playLines = const [];

  bool _isLoading = true;
  String? _errorMessage;

  int _selectedLineIndex = 0;
  int _selectedEpisodeIndex = 0;

  String? _currentEpisodeUrl;
  String? _currentEpisodeName;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final detailUrl = widget.source.detailUrl.trim().isNotEmpty
          ? widget.source.detailUrl
          : widget.source.url;

      final detail = await VideoApiService.fetchDetail(
        detailUrl,
        widget.vodId,
      );

      if (!mounted) return;

      if (detail == null) {
        setState(() {
          _fullDetail = null;
          _playLines = const [];
          _selectedLineIndex = 0;
          _selectedEpisodeIndex = 0;
          _currentEpisodeUrl = null;
          _currentEpisodeName = null;
          _isLoading = false;
          _errorMessage = '视频详情加载失败';
        });
        return;
      }

      final rawPlayUrls = _extractRawPlayUrls(detail);
      final playLines = _normalizePlayLines(rawPlayUrls);
      final defaultSelection = _pickDefaultSelection(playLines);

      setState(() {
        _fullDetail = detail;
        _playLines = playLines;
        _selectedLineIndex = defaultSelection.lineIndex;
        _selectedEpisodeIndex = defaultSelection.episodeIndex;
        _currentEpisodeUrl = defaultSelection.url;
        _currentEpisodeName = defaultSelection.name;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fullDetail = null;
        _playLines = const [];
        _selectedLineIndex = 0;
        _selectedEpisodeIndex = 0;
        _currentEpisodeUrl = null;
        _currentEpisodeName = null;
        _isLoading = false;
        _errorMessage = '加载失败：$e';
      });
    }
  }

  /// 兼容：
  /// 1. 你现在的 VodItem.parsePlayUrls -> List<PlaySourceGroup>
  /// 2. 老版本 -> List<Map<String, String>>
  dynamic _extractRawPlayUrls(VodItem detail) {
    try {
      return detail.parsePlayUrls;
    } catch (_) {
      try {
        return detail.playUrls;
      } catch (_) {
        return const [];
      }
    }
  }

  /// 把各种 parsePlayUrls 形式统一转成：
  /// [ _PlayLine(name: '线路1', episodes: [...]), ... ]
  List<_PlayLine> _normalizePlayLines(dynamic rawValue) {
    final rawList =
        rawValue is Iterable ? List<dynamic>.from(rawValue) : <dynamic>[];
    if (rawList.isEmpty) return const [];

    // 如果元素里有“分组结构”，就按分组处理
    final groupedLines = <_PlayLine>[];

    for (var i = 0; i < rawList.length; i++) {
      final item = rawList[i];
      final nestedEpisodes = _extractNestedEpisodes(item);

      if (nestedEpisodes.isNotEmpty) {
        final episodes = <_PlayEpisode>[];

        for (var j = 0; j < nestedEpisodes.length; j++) {
          final ep = _normalizeEpisode(
            nestedEpisodes[j],
            fallbackName: '第${j + 1}集',
          );
          if (ep != null) {
            episodes.add(ep);
          }
        }

        if (episodes.isNotEmpty) {
          groupedLines.add(
            _PlayLine(
              name: _extractLineName(item, index: i),
              episodes: episodes,
            ),
          );
        }
      }
    }

    if (groupedLines.isNotEmpty) {
      return groupedLines;
    }

    // 如果没有分组结构，就把整个列表当成单线路“正片”处理
    final flatEpisodes = <_PlayEpisode>[];
    for (var i = 0; i < rawList.length; i++) {
      final ep = _normalizeEpisode(
        rawList[i],
        fallbackName: '第${i + 1}集',
      );
      if (ep != null) {
        flatEpisodes.add(ep);
      }
    }

    if (flatEpisodes.isNotEmpty) {
      return <_PlayLine>[
        _PlayLine(name: '正片', episodes: flatEpisodes),
      ];
    }

    return const [];
  }

  /// 抽取某个线路里的 episodes/items/playItems/playUrls
  List<dynamic> _extractNestedEpisodes(dynamic item) {
    if (item == null) return const [];

    if (item is Map) {
      for (final key in const ['episodes', 'items', 'playItems', 'playUrls']) {
        final value = item[key];
        if (value is Iterable) {
          return List<dynamic>.from(value);
        }
      }
      return const [];
    }

    for (final key in const ['episodes', 'items', 'playItems', 'playUrls']) {
      final value = _readDynamicProperty(item, key);
      if (value is Iterable) {
        return List<dynamic>.from(value);
      }
    }

    return const [];
  }

  /// 抽取线路名称
  String _extractLineName(dynamic item, {required int index}) {
    final name = _readDynamicText(
      item,
      const ['name', 'title', 'sourceName', 'lineName'],
    );
    return name ?? '线路${index + 1}';
  }

  /// 抽取单个播放条目并标准化
  _PlayEpisode? _normalizeEpisode(
    dynamic item, {
    required String fallbackName,
  }) {
    if (item == null) return null;

    final name = _readDynamicText(
          item,
          const ['name', 'title', 'episodeName'],
        ) ??
        fallbackName;

    final rawUrl = _readDynamicText(
      item,
      const ['url', 'playUrl', 'link', 'href'],
    );

    if (rawUrl == null || rawUrl.trim().isEmpty) {
      return null;
    }

    final resolvedUrl = _resolvePlayUrl(rawUrl.trim());

    return _PlayEpisode(
      name: name,
      url: resolvedUrl,
    );
  }

  /// 从 Map 或动态对象中读取文本字段
  String? _readDynamicText(dynamic item, List<String> keys) {
    if (item == null) return null;

    if (item is Map) {
      for (final key in keys) {
        final value = item[key];
        final text = _asText(value);
        if (text != null) return text;
      }
      return null;
    }

    for (final key in keys) {
      final value = _readDynamicProperty(item, key);
      final text = _asText(value);
      if (text != null) return text;
    }

    return null;
  }

  /// 从动态对象中读取属性
  dynamic _readDynamicProperty(dynamic item, String key) {
    try {
      switch (key) {
        case 'name':
          return item.name;
        case 'title':
          return item.title;
        case 'sourceName':
          return item.sourceName;
        case 'lineName':
          return item.lineName;

        case 'episodes':
          return item.episodes;
        case 'items':
          return item.items;
        case 'playItems':
          return item.playItems;
        case 'playUrls':
          return item.playUrls;

        case 'url':
          return item.url;
        case 'playUrl':
          return item.playUrl;
        case 'link':
          return item.link;
        case 'href':
          return item.href;

        case 'episodeName':
          return item.episodeName;
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  String? _asText(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }

  /// 默认选中第一条可播放线路的第一集
  _PlaybackSelection _pickDefaultSelection(List<_PlayLine> playLines) {
    if (playLines.isEmpty) {
      return const _PlaybackSelection(
        lineIndex: 0,
        episodeIndex: 0,
        url: null,
        name: null,
      );
    }

    final lineIndex = playLines.indexWhere((line) => line.episodes.isNotEmpty);
    final safeLineIndex = lineIndex >= 0 ? lineIndex : 0;
    final line = playLines[safeLineIndex];

    if (line.episodes.isEmpty) {
      return const _PlaybackSelection(
        lineIndex: 0,
        episodeIndex: 0,
        url: null,
        name: null,
      );
    }

    final firstEpisode = line.episodes.first;
    return _PlaybackSelection(
      lineIndex: safeLineIndex,
      episodeIndex: 0,
      url: firstEpisode.url,
      name: firstEpisode.name,
    );
  }

  void _selectLine(int index) {
    if (index < 0 || index >= _playLines.length) return;

    final line = _playLines[index];
    if (line.episodes.isEmpty) return;

    final firstEpisode = line.episodes.first;

    setState(() {
      _selectedLineIndex = index;
      _selectedEpisodeIndex = 0;
      _currentEpisodeUrl = firstEpisode.url;
      _currentEpisodeName = firstEpisode.name;
    });
  }

  void _selectEpisode(int index) {
    if (_playLines.isEmpty) return;

    final safeLineIndex = _selectedLineIndex.clamp(0, _playLines.length - 1);
    final line = _playLines[safeLineIndex];

    if (index < 0 || index >= line.episodes.length) return;

    final episode = line.episodes[index];

    if (_currentEpisodeUrl == episode.url) {
      return;
    }

    setState(() {
      _selectedLineIndex = safeLineIndex;
      _selectedEpisodeIndex = index;
      _currentEpisodeUrl = episode.url;
      _currentEpisodeName = episode.name;
    });
  }

  String _resolvePlayUrl(String rawUrl) {
    var url = rawUrl.trim().replaceAll('\\', '');
    if (url.isEmpty) return url;

    if (url.startsWith('//')) {
      return 'https:$url';
    }

    final uri = Uri.tryParse(url);
    if (uri != null && uri.hasScheme) {
      return url;
    }

    for (final base in [widget.source.detailUrl, widget.source.url]) {
      final baseUri = Uri.tryParse(base.trim());
      if (baseUri == null || !baseUri.hasScheme) continue;

      try {
        return baseUri.resolve(url).toString();
      } catch (_) {
        // 继续尝试下一个 base
      }
    }

    return url;
  }

  String? _resolveImageUrl(String? rawUrl) {
    if (rawUrl == null) return null;

    var url = rawUrl.trim().replaceAll('\\', '');
    if (url.isEmpty) return null;

    if (url.startsWith('//')) {
      return 'https:$url';
    }

    final uri = Uri.tryParse(url);
    if (uri != null && uri.hasScheme) {
      return url;
    }

    for (final base in [widget.source.detailUrl, widget.source.url]) {
      final baseUri = Uri.tryParse(base.trim());
      if (baseUri == null || !baseUri.hasScheme) continue;

      try {
        return baseUri.resolve(url).toString();
      } catch (_) {
        // 继续尝试下一个 base
      }
    }

    return url;
  }

  int _totalEpisodeCount() {
    return _playLines.fold<int>(
      0,
      (sum, line) => sum + line.episodes.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _fullDetail?.vodName ?? widget.source.name;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            tooltip: '调试日志',
            onPressed: () {
              Navigator.of(context).pushNamed('/debug-log');
            },
            icon: const Icon(Icons.bug_report_outlined),
          ),
          IconButton(
            tooltip: '重新加载',
            onPressed: _isLoading ? null : _loadDetail,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_fullDetail == null
              ? _buildErrorView()
              : Column(
                  children: [
                    // 播放器区域
                    Container(
                      width: double.infinity,
                      color: Colors.black,
                      constraints: BoxConstraints(
                        maxHeight: screenHeight * 0.45,
                      ),
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: _currentEpisodeUrl != null
                              ? VideoPlayContainer(
                                  url: _currentEpisodeUrl!,
                                  title: _fullDetail!.vodName,
                                  vodId: widget.vodId.toString(),
                                  vodPic: _fullDetail?.vodPic ?? '',
                                  sourceId: widget.source.id,
                                  sourceName: widget.source.name,
                                  episodeName: _currentEpisodeName ?? '正片',
                                  referer: widget.source.detailUrl
                                          .trim()
                                          .isNotEmpty
                                      ? widget.source.detailUrl
                                      : widget.source.url,
                                  showDebugInfo: true,
                                )
                              : const Center(
                                  child: Text(
                                    '无可播放资源',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                        ),
                      ),
                    ),

                    // 下方详情和选集区域
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadDetail,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(12),
                          children: [
                            _buildInfoCard(),
                            const SizedBox(height: 16),
                            const Text(
                              '线路 / 选集',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (_playLines.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Center(
                                  child: Text('暂无选集数据'),
                                ),
                              )
                            else ...[
                              if (_playLines.length > 1) ...[
                                _buildLineSelector(),
                                const SizedBox(height: 12),
                              ],
                              _buildEpisodeSelector(),
                            ],
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ),
                  ],
                )),
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
            _errorMessage ?? '视频详情加载失败',
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
            onPressed: _loadDetail,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重试'),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard() {
    final detail = _fullDetail!;
    final coverUrl = _resolveImageUrl(detail.vodPic);
    final totalEpisodes = _totalEpisodeCount();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.shade200,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 92,
              height: 132,
              child: coverUrl == null
                  ? Container(
                      color: Colors.grey.shade300,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.movie_outlined,
                        size: 36,
                        color: Colors.grey.shade600,
                      ),
                    )
                  : Image.network(
                      coverUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey.shade300,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.movie_outlined,
                            size: 36,
                            color: Colors.grey.shade600,
                          ),
                        );
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          color: Colors.grey.shade200,
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.vodName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildTag('来源：${widget.source.name}'),
                    if ((detail.typeName ?? '').trim().isNotEmpty)
                      _buildTag('分类：${detail.typeName}'),
                    if ((detail.vodRemarks ?? '').trim().isNotEmpty)
                      _buildTag('更新：${detail.vodRemarks}'),
                    if ((detail.vodTime ?? '').trim().isNotEmpty)
                      _buildTag('时间：${detail.vodTime}'),
                    _buildTag('线路：${_playLines.length}'),
                    _buildTag('集数：$totalEpisodes'),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '当前播放：${_currentEpisodeName ?? '未选择'}',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildLineSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '播放线路',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(_playLines.length, (index) {
              final line = _playLines[index];
              final selected = index == _selectedLineIndex;

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(
                    line.name,
                    style: TextStyle(
                      fontSize: 13,
                      color: selected
                          ? Colors.white
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  selected: selected,
                  selectedColor: Theme.of(context).colorScheme.primary,
                  backgroundColor:
                      Theme.of(context).colorScheme.primary.withOpacity(0.08),
                  side: BorderSide(
                    color:
                        Theme.of(context).colorScheme.primary.withOpacity(0.2),
                  ),
                  onSelected: (_) => _selectLine(index),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildEpisodeSelector() {
    final safeLineIndex = _playLines.isEmpty
        ? 0
        : _selectedLineIndex
            .clamp(0, _playLines.length - 1)
            .toInt();

    final episodes = _playLines.isEmpty
        ? const <_PlayEpisode>[]
        : _playLines[safeLineIndex].episodes;

    if (episodes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('当前线路暂无可播放集数'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '选集',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(episodes.length, (index) {
            final episode = episodes[index];
            final selected =
                index == _selectedEpisodeIndex && safeLineIndex == _selectedLineIndex;

            return ChoiceChip(
              label: Text(
                episode.name,
                style: TextStyle(
                  fontSize: 13,
                  color: selected
                      ? Colors.white
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
              selected: selected,
              selectedColor: Theme.of(context).colorScheme.primary,
              backgroundColor:
                  Theme.of(context).colorScheme.primary.withOpacity(0.08),
              side: BorderSide(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
              ),
              onSelected: (_) => _selectEpisode(index),
            );
          }),
        ),
      ],
    );
  }
}

class _PlayLine {
  final String name;
  final List<_PlayEpisode> episodes;

  const _PlayLine({
    required this.name,
    required this.episodes,
  });
}

class _PlayEpisode {
  final String name;
  final String url;

  const _PlayEpisode({
    required this.name,
    required this.url,
  });
}

class _PlaybackSelection {
  final int lineIndex;
  final int episodeIndex;
  final String? url;
  final String? name;

  const _PlaybackSelection({
    required this.lineIndex,
    required this.episodeIndex,
    required this.url,
    required this.name,
  });
}