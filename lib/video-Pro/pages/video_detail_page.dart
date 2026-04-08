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
        _isLoading = false;
        _errorMessage = '加载失败：$e';
      });
    }
  }

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

  List<_PlayLine> _normalizePlayLines(dynamic rawValue) {
    final rawList = rawValue is Iterable ? List<dynamic>.from(rawValue) : <dynamic>[];
    if (rawList.isEmpty) return const [];

    final groupedLines = <_PlayLine>[];

    for (var i = 0; i < rawList.length; i++) {
      final item = rawList[i];
      final nestedEpisodes = _extractNestedEpisodes(item);

      if (nestedEpisodes.isNotEmpty) {
        final episodes = <_PlayEpisode>[];
        for (var j = 0; j < nestedEpisodes.length; j++) {
          final ep = _normalizeEpisode(nestedEpisodes[j], fallbackName: '第${j + 1}集');
          if (ep != null) episodes.add(ep);
        }
        if (episodes.isNotEmpty) {
          groupedLines.add(_PlayLine(name: _extractLineName(item, index: i), episodes: episodes));
        }
      }
    }

    if (groupedLines.isNotEmpty) return groupedLines;

    final flatEpisodes = <_PlayEpisode>[];
    for (var i = 0; i < rawList.length; i++) {
      final ep = _normalizeEpisode(rawList[i], fallbackName: '第${i + 1}集');
      if (ep != null) flatEpisodes.add(ep);
    }

    if (flatEpisodes.isNotEmpty) {
      return <_PlayLine>[_PlayLine(name: '正片', episodes: flatEpisodes)];
    }

    return const [];
  }

  List<dynamic> _extractNestedEpisodes(dynamic item) {
    if (item == null) return const [];
    if (item is Map) {
      for (final key in const ['episodes', 'items', 'playItems', 'playUrls']) {
        final value = item[key];
        if (value is Iterable) return List<dynamic>.from(value);
      }
      return const [];
    }
    for (final key in const ['episodes', 'items', 'playItems', 'playUrls']) {
      final value = _readDynamicProperty(item, key);
      if (value is Iterable) return List<dynamic>.from(value);
    }
    return const [];
  }

  String _extractLineName(dynamic item, {required int index}) {
    final name = _readDynamicText(item, const ['name', 'title', 'sourceName', 'lineName']);
    return name ?? '线路${index + 1}';
  }

  _PlayEpisode? _normalizeEpisode(dynamic item, {required String fallbackName}) {
    if (item == null) return null;
    final name = _readDynamicText(item, const ['name', 'title', 'episodeName']) ?? fallbackName;
    final rawUrl = _readDynamicText(item, const ['url', 'playUrl', 'link', 'href']);
    if (rawUrl == null || rawUrl.trim().isEmpty) return null;
    return _PlayEpisode(name: name, url: _resolvePlayUrl(rawUrl.trim()));
  }

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

  dynamic _readDynamicProperty(dynamic item, String key) {
    try {
      switch (key) {
        case 'name': return item.name;
        case 'title': return item.title;
        case 'sourceName': return item.sourceName;
        case 'lineName': return item.lineName;
        case 'episodes': return item.episodes;
        case 'items': return item.items;
        case 'playItems': return item.playItems;
        case 'playUrls': return item.playUrls;
        case 'url': return item.url;
        case 'playUrl': return item.playUrl;
        case 'link': return item.link;
        case 'href': return item.href;
        case 'episodeName': return item.episodeName;
        default: return null;
      }
    } catch (_) { return null; }
  }

  String? _asText(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }

  _PlaybackSelection _pickDefaultSelection(List<_PlayLine> playLines) {
    if (playLines.isEmpty) return const _PlaybackSelection(lineIndex: 0, episodeIndex: 0, url: null, name: null);
    final lineIndex = playLines.indexWhere((line) => line.episodes.isNotEmpty);
    final safeLineIndex = lineIndex >= 0 ? lineIndex : 0;
    final line = playLines[safeLineIndex];
    if (line.episodes.isEmpty) return const _PlaybackSelection(lineIndex: 0, episodeIndex: 0, url: null, name: null);
    final firstEpisode = line.episodes.first;
    return _PlaybackSelection(lineIndex: safeLineIndex, episodeIndex: 0, url: firstEpisode.url, name: firstEpisode.name);
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
    if (_currentEpisodeUrl == episode.url) return;

    setState(() {
      _selectedLineIndex = safeLineIndex;
      _selectedEpisodeIndex = index;
      _currentEpisodeUrl = episode.url;
      _currentEpisodeName = episode.name;
    });
  }

  // ✨ 核心逻辑：播放上一集
  void _playPreviousEpisode() {
    if (_selectedEpisodeIndex > 0) {
      _selectEpisode(_selectedEpisodeIndex - 1);
    }
  }

  // ✨ 核心逻辑：播放下一集
  void _playNextEpisode() {
    if (_playLines.isEmpty) return;
    final safeLineIndex = _selectedLineIndex.clamp(0, _playLines.length - 1);
    final line = _playLines[safeLineIndex];
    if (_selectedEpisodeIndex < line.episodes.length - 1) {
      _selectEpisode(_selectedEpisodeIndex + 1);
    }
  }

  // 检测是否可以显示“上一集”按钮
  bool _canPlayPrevious() {
    if (_playLines.isEmpty) return false;
    return _selectedEpisodeIndex > 0;
  }

  // 检测是否可以显示“下一集”按钮
  bool _canPlayNext() {
    if (_playLines.isEmpty) return false;
    final safeLineIndex = _selectedLineIndex.clamp(0, _playLines.length - 1);
    return _selectedEpisodeIndex < _playLines[safeLineIndex].episodes.length - 1;
  }

  String _resolvePlayUrl(String rawUrl) {
    var url = rawUrl.trim().replaceAll('\\', '');
    if (url.isEmpty) return url;
    if (url.startsWith('//')) return 'https:$url';
    final uri = Uri.tryParse(url);
    if (uri != null && uri.hasScheme) return url;
    for (final base in [widget.source.detailUrl, widget.source.url]) {
      final baseUri = Uri.tryParse(base.trim());
      if (baseUri == null || !baseUri.hasScheme) continue;
      try { return baseUri.resolve(url).toString(); } catch (_) {}
    }
    return url;
  }

  String? _resolveImageUrl(String? rawUrl) {
    if (rawUrl == null) return null;
    var url = rawUrl.trim().replaceAll('\\', '');
    if (url.isEmpty) return null;
    if (url.startsWith('//')) return 'https:$url';
    final uri = Uri.tryParse(url);
    if (uri != null && uri.hasScheme) return url;
    for (final base in [widget.source.detailUrl, widget.source.url]) {
      final baseUri = Uri.tryParse(base.trim());
      if (baseUri == null || !baseUri.hasScheme) continue;
      try { return baseUri.resolve(url).toString(); } catch (_) {}
    }
    return url;
  }

  int _totalEpisodeCount() {
    return _playLines.fold<int>(0, (sum, line) => sum + line.episodes.length);
  }

  @override
  Widget build(BuildContext context) {
    final title = _fullDetail?.vodName ?? widget.source.name;

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            tooltip: '调试日志',
            onPressed: () {
              Navigator.of(context).pushNamed('/debug-log');
            },
            icon: const Icon(Icons.bug_report_outlined),
          ),
          IconButton(tooltip: '重新加载', onPressed: _isLoading ? null : _loadDetail, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_fullDetail == null
              ? _buildErrorView()
              : Column(
                  children: [
                    // 1. 播放器区域
                    Container(
                      width: double.infinity,
                      color: Colors.black,
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
                                referer: widget.source.detailUrl.trim().isNotEmpty ? widget.source.detailUrl : widget.source.url,
                                showDebugInfo: false, // 关掉左上角的调试黑块
                                // ✨ 注入上下集切换回调
                                onPreviousEpisode: _canPlayPrevious() ? _playPreviousEpisode : null,
                                onNextEpisode: _canPlayNext() ? _playNextEpisode : null,
                              )
                            : const Center(child: Text('无可播放资源', style: TextStyle(color: Colors.white))),
                      ),
                    ),

                    // 2. 下方详情和选集区域
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadDetail,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(12),
                          children: [
                            _buildInfoCard(),
                            const SizedBox(height: 16),
                            if (_playLines.isEmpty)
                              const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('暂无选集数据')))
                            else ...[
                              if (_playLines.length > 1) ...[
                                _buildLineSelector(),
                                const SizedBox(height: 4),
                              ],
                              // ✨ 使用我们专属手搓的展开/排序高级选集组件
                              _buildEpisodeSection(),
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

  Widget _buildEpisodeSection() {
    final safeLineIndex = _playLines.isEmpty ? 0 : _selectedLineIndex.clamp(0, _playLines.length - 1).toInt();
    final episodes = _playLines.isEmpty ? const <_PlayEpisode>[] : _playLines[safeLineIndex].episodes;

    return _ExpandableEpisodeSection(
      episodes: episodes,
      currentIndex: _selectedEpisodeIndex,
      onEpisodeTap: _selectEpisode,
    );
  }

  Widget _buildErrorView() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(Icons.error_outline_rounded, size: 72, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        Center(child: Text(_errorMessage ?? '视频详情加载失败', style: TextStyle(color: Colors.grey.shade700, fontSize: 15), textAlign: TextAlign.center)),
        const SizedBox(height: 16),
        Center(child: ElevatedButton.icon(onPressed: _loadDetail, icon: const Icon(Icons.refresh_rounded), label: const Text('重试'))),
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
        border: Border.all(color: Colors.grey.shade200),
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
                  ? Container(color: Colors.grey.shade100, alignment: Alignment.center, child: Icon(Icons.movie_outlined, size: 36, color: Colors.grey.shade400))
                  : Image.network(
                      coverUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(color: Colors.grey.shade100, alignment: Alignment.center, child: Icon(Icons.movie_outlined, size: 36, color: Colors.grey.shade400)),
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(color: Colors.grey.shade100, alignment: Alignment.center, child: const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)));
                      },
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(detail.vodName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildTag('来源：${widget.source.name}'),
                    if ((detail.typeName ?? '').trim().isNotEmpty) _buildTag('分类：${detail.typeName}'),
                    if ((detail.vodRemarks ?? '').trim().isNotEmpty) _buildTag('更新：${detail.vodRemarks}'),
                    if ((detail.vodTime ?? '').trim().isNotEmpty) _buildTag('时间：${detail.vodTime}'),
                    _buildTag('线路：${_playLines.length}'),
                    _buildTag('集数：$totalEpisodes'),
                  ],
                ),
                const SizedBox(height: 10),
                Text('当前播放：${_currentEpisodeName ?? '未选择'}', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildLineSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('播放线路', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(_playLines.length, (index) {
              final line = _playLines[index];
              final selected = index == _selectedLineIndex;
              return Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 8),
                child: ChoiceChip(
                  label: Text(line.name, style: TextStyle(fontSize: 13, color: selected ? Colors.white : Colors.black87, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
                  selected: selected,
                  selectedColor: Theme.of(context).colorScheme.primary,
                  backgroundColor: Colors.grey.shade100,
                  side: BorderSide.none,
                  showCheckmark: false,
                  onSelected: (_) => _selectLine(index),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

// ==== 数据结构类 ====
class _PlayLine {
  final String name;
  final List<_PlayEpisode> episodes;
  const _PlayLine({required this.name, required this.episodes});
}
class _PlayEpisode {
  final String name;
  final String url;
  const _PlayEpisode({required this.name, required this.url});
}
class _PlaybackSelection {
  final int lineIndex;
  final int episodeIndex;
  final String? url;
  final String? name;
  const _PlaybackSelection({required this.lineIndex, required this.episodeIndex, required this.url, required this.name});
}

// ============================================================================
// ✨ 高级独立组件：支持正倒序、自动折叠展开的选集网格
// ============================================================================
class _ExpandableEpisodeSection extends StatefulWidget {
  final List<_PlayEpisode> episodes;
  final int currentIndex;
  final ValueChanged<int> onEpisodeTap;

  const _ExpandableEpisodeSection({
    required this.episodes,
    required this.currentIndex,
    required this.onEpisodeTap,
  });

  @override
  State<_ExpandableEpisodeSection> createState() => _ExpandableEpisodeSectionState();
}

class _ExpandableEpisodeSectionState extends State<_ExpandableEpisodeSection> {
  bool _isExpanded = false;
  bool _isReversed = false;

  // 当用户切换了不同的线路，重置展开和倒序状态
  @override
  void didUpdateWidget(covariant _ExpandableEpisodeSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.episodes != widget.episodes) {
      _isExpanded = false;
      _isReversed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.episodes.isEmpty) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('当前线路暂无可播放集数')));
    }

    final int total = widget.episodes.length;
    // 默认折叠状态下只展示 12 集
    final int displayCount = _isExpanded ? total : (total > 12 ? 12 : total);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('选集', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            if (total > 1)
              TextButton.icon(
                onPressed: () => setState(() => _isReversed = !_isReversed),
                icon: const Icon(Icons.sort_rounded, size: 16, color: Colors.blueAccent),
                label: Text(_isReversed ? '切为正序' : '切为倒序', style: const TextStyle(fontSize: 13, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              )
          ],
        ),
        const SizedBox(height: 12),
        GridView.builder(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: displayCount,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,     // 一行显示4个集数按钮
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.2, // 药丸形比例
          ),
          itemBuilder: (context, index) {
            // 通过倒序变量计算真实索引
            final realIndex = _isReversed ? total - 1 - index : index;
            final episode = widget.episodes[realIndex];
            final isSelected = realIndex == widget.currentIndex;

            return InkWell(
              onTap: () => widget.onEpisodeTap(realIndex),
              borderRadius: BorderRadius.circular(6),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blueAccent : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  episode.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isSelected ? Colors.white : Colors.black87,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            );
          },
        ),
        // 展开全部集数的按钮
        if (!_isExpanded && total > 12)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 16),
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _isExpanded = true),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              label: const Text('展开全部集数'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
      ],
    );
  }
}