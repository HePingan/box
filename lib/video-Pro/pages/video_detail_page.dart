import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../pages/debug_log_page.dart';
import '../../utils/app_logger.dart';
import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../services/video_api_service.dart';
import '../widgets/video_play_container.dart';

class VideoDetailPage extends StatefulWidget {
  final VideoSource source;
  final int vodId;

  /// 历史续播：目标集数 URL
  final String? initialEpisodeUrl;

  /// 历史续播：目标播放位置（毫秒）
  final int initialPosition;

  const VideoDetailPage({
    super.key,
    required this.source,
    required this.vodId,
    this.initialEpisodeUrl,
    this.initialPosition = 0,
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

  bool _resumeApplied = false;
  bool _resumeHintShown = false;

  int get _vodIdInt => widget.vodId;

  @override
  void initState() {
    super.initState();
    _log('页面初始化，vodId=${widget.vodId}, source=${widget.source.name}');
    _loadDetail();
  }

  void _log(String message, {String tag = 'DETAIL'}) {
    AppLogger.instance.log(message, tag: tag);
  }

  void _logError(Object error, [StackTrace? stackTrace]) {
    AppLogger.instance.logError(error, stackTrace, 'DETAIL_ERROR');
  }

  Future<void> _openDebugLogPage() async {
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const DebugLogPage(),
      ),
    );
  }

  Future<void> _loadDetail() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final detailUrl = widget.source.detailUrl.trim().isNotEmpty
        ? widget.source.detailUrl
        : widget.source.url;

    _log(
      '开始加载详情，vodId=${widget.vodId}, detailUrl=$detailUrl, sourceUrl=${widget.source.url}',
    );

    try {
      final detail = await VideoApiService.fetchDetail(detailUrl, _vodIdInt);

      if (!mounted) return;

      if (detail == null) {
        _log('详情接口返回空数据，vodId=${widget.vodId}');
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
      final defaultSelection = _pickDefaultSelection(
        playLines,
        initialEpisodeUrl: widget.initialEpisodeUrl,
      );

      _log(
        '详情加载成功，线路数=${playLines.length}，默认线路=${defaultSelection.lineIndex}，默认集数=${defaultSelection.episodeIndex}',
      );

      setState(() {
        _fullDetail = detail;
        _playLines = playLines;
        _selectedLineIndex = defaultSelection.lineIndex;
        _selectedEpisodeIndex = defaultSelection.episodeIndex;
        _currentEpisodeUrl = defaultSelection.url;
        _currentEpisodeName = defaultSelection.name;
        _isLoading = false;
        _errorMessage = null;
        _resumeApplied = false;
        _resumeHintShown = false;
      });

      _maybeShowResumeHint();
    } catch (e, st) {
      _logError(e, st);

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '加载失败：$e';
      });
    }
  }

  void _maybeShowResumeHint() {
    final initialUrl = widget.initialEpisodeUrl?.trim();
    if (_resumeHintShown) return;
    if (widget.initialPosition <= 0) return;
    if (initialUrl == null || initialUrl.isEmpty) return;
    if (_currentEpisodeUrl == null) return;

    if (_sameUrl(_currentEpisodeUrl!, initialUrl)) {
      _resumeHintShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '已为你恢复到上次播放位置：${_formatPosition(widget.initialPosition)}',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      });
    }
  }

  String _formatPosition(int millis) {
    final totalSeconds = (millis / 1000).round();
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;

    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  dynamic _extractRawPlayUrls(VodItem detail) {
    try {
      final parsed = detail.parsePlayUrls;
      if (parsed != null) return parsed;
    } catch (_) {}

    try {
      final raw = detail.playUrls;
      if (raw != null) return raw;
    } catch (_) {}

    try {
      final raw = detail.vodPlayUrl;
      if (raw != null && raw.toString().trim().isNotEmpty) {
        return raw.toString();
      }
    } catch (_) {}

    return const [];
  }

  List<_PlayLine> _normalizePlayLines(dynamic rawValue) {
    if (rawValue == null) return const [];

    if (rawValue is String) {
      return _parsePlayUrlString(rawValue);
    }

    if (rawValue is Iterable) {
      final rawList = List<dynamic>.from(rawValue);
      if (rawList.isEmpty) return const [];

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
            if (ep != null) episodes.add(ep);
          }

          if (episodes.isNotEmpty) {
            groupedLines.add(
              _PlayLine(
                name: _extractLineName(item, index: i),
                episodes: episodes,
              ),
            );
            continue;
          }
        }

        if (item is String) {
          final parsedFromString = _parsePlayUrlString(item);
          if (parsedFromString.isNotEmpty) {
            groupedLines.addAll(parsedFromString);
            continue;
          }
        }

        final asLine = _normalizeSingleLineItem(item, index: i);
        if (asLine != null) {
          groupedLines.add(asLine);
        }
      }

      if (groupedLines.isNotEmpty) return groupedLines;

      final flatEpisodes = <_PlayEpisode>[];
      for (var i = 0; i < rawList.length; i++) {
        final ep = _normalizeEpisode(rawList[i], fallbackName: '第${i + 1}集');
        if (ep != null) flatEpisodes.add(ep);
      }

      if (flatEpisodes.isNotEmpty) {
        return <_PlayLine>[
          _PlayLine(name: '正片', episodes: flatEpisodes),
        ];
      }

      return const [];
    }

    if (rawValue is Map) {
      final map = Map<String, dynamic>.from(rawValue);
      final lines = <_PlayLine>[];

      for (final entry in map.entries) {
        final lineName = entry.key.toString().trim().isEmpty
            ? '线路${lines.length + 1}'
            : entry.key.toString();

        final value = entry.value;
        if (value is Iterable) {
          final episodes = <_PlayEpisode>[];
          for (var i = 0; i < value.length; i++) {
            final ep = _normalizeEpisode(
              value.elementAt(i),
              fallbackName: '第${i + 1}集',
            );
            if (ep != null) episodes.add(ep);
          }

          if (episodes.isNotEmpty) {
            lines.add(_PlayLine(name: lineName, episodes: episodes));
          }
        } else if (value is String) {
          final parsed = _parsePlayUrlString(lineName + r'$$$' + value);
          if (parsed.isNotEmpty) lines.addAll(parsed);
        }
      }

      return lines;
    }

    return const [];
  }

  List<_PlayLine> _parsePlayUrlString(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const [];

    final chunks = text
        .split(RegExp(r'\s*[#\n]\s*'))
        .where((e) => e.trim().isNotEmpty)
        .toList();

    if (chunks.isEmpty) return const [];

    final lines = <_PlayLine>[];

    for (final chunk in chunks) {
      final parts = chunk.split(r'$$$');

      if (parts.length >= 2) {
        final lineName = parts.first.trim().isEmpty
            ? '线路${lines.length + 1}'
            : parts.first.trim();

        final episodePart = parts.sublist(1).join(r'$$$').trim();
        final episodes = _parseEpisodePart(episodePart);

        if (episodes.isNotEmpty) {
          lines.add(_PlayLine(name: lineName, episodes: episodes));
        }
      } else {
        final episodes = _parseEpisodePart(chunk);
        if (episodes.isNotEmpty) {
          lines.add(
            _PlayLine(
              name: lines.isEmpty ? '正片' : '线路${lines.length + 1}',
              episodes: episodes,
            ),
          );
        }
      }
    }

    return lines;
  }

  List<_PlayEpisode> _parseEpisodePart(String part) {
    final text = part.trim();
    if (text.isEmpty) return const [];

    final segments = text
        .split(RegExp(r'\s*#\s*'))
        .where((e) => e.trim().isNotEmpty)
        .toList();

    final episodes = <_PlayEpisode>[];

    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i].trim();

      String? name;
      String? url;

      if (seg.contains('\$')) {
        final idx = seg.indexOf('\$');
        name = seg.substring(0, idx).trim();
        url = seg.substring(idx + 1).trim();
      } else if (seg.contains('|')) {
        final idx = seg.indexOf('|');
        name = seg.substring(0, idx).trim();
        url = seg.substring(idx + 1).trim();
      } else if (seg.contains(',')) {
        final idx = seg.indexOf(',');
        name = seg.substring(0, idx).trim();
        url = seg.substring(idx + 1).trim();
      }

      if (url == null || url.isEmpty) continue;

      episodes.add(
        _PlayEpisode(
          name: (name == null || name.isEmpty) ? '第${i + 1}集' : name,
          url: _resolvePlayUrl(url),
        ),
      );
    }

    return episodes;
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

  _PlayLine? _normalizeSingleLineItem(dynamic item, {required int index}) {
    final lineName = _extractLineName(item, index: index);
    final urlText = _readDynamicText(item, const ['url', 'playUrl', 'link', 'href']);

    if (urlText == null || urlText.trim().isEmpty) {
      return null;
    }

    final episodeName =
        _readDynamicText(item, const ['name', 'title', 'episodeName']) ??
            '第1集';

    return _PlayLine(
      name: lineName,
      episodes: [
        _PlayEpisode(
          name: episodeName,
          url: _resolvePlayUrl(urlText),
        ),
      ],
    );
  }

  String _extractLineName(dynamic item, {required int index}) {
    final name = _readDynamicText(
      item,
      const ['name', 'title', 'sourceName', 'lineName'],
    );
    return name ?? '线路${index + 1}';
  }

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

    final rawUrl = _readDynamicText(item, const ['url', 'playUrl', 'link', 'href']);
    if (rawUrl == null || rawUrl.trim().isEmpty) return null;

    return _PlayEpisode(
      name: name,
      url: _resolvePlayUrl(rawUrl.trim()),
    );
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

  String _resolvePlayUrl(String rawUrl) {
    var url = rawUrl.trim().replaceAll('\\', '');
    if (url.isEmpty) return url;

    if (url.startsWith('//')) return 'https:$url';

    final uri = Uri.tryParse(url);
    if (uri != null && uri.hasScheme) return url;

    for (final base in [widget.source.detailUrl, widget.source.url]) {
      final baseUri = Uri.tryParse(base.trim());
      if (baseUri == null || !baseUri.hasScheme) continue;
      try {
        return baseUri.resolve(url).toString();
      } catch (_) {}
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
      try {
        return baseUri.resolve(url).toString();
      } catch (_) {}
    }

    return url;
  }

  bool _sameUrl(String a, String b) {
    final left = _canonicalUrl(a);
    final right = _canonicalUrl(b);
    if (left == right) return true;

    final leftUri = Uri.tryParse(left);
    final rightUri = Uri.tryParse(right);
    if (leftUri != null &&
        rightUri != null &&
        leftUri.path == rightUri.path) {
      return true;
    }

    return false;
  }

  String _canonicalUrl(String rawUrl) {
    final resolved = _resolvePlayUrl(rawUrl).trim();
    if (resolved.isEmpty) return resolved;

    final uri = Uri.tryParse(resolved);
    if (uri == null) return resolved;

    return uri.replace(fragment: '').toString();
  }

  _PlaybackSelection _pickDefaultSelection(
    List<_PlayLine> playLines, {
    String? initialEpisodeUrl,
  }) {
    if (playLines.isEmpty) {
      return const _PlaybackSelection(
        lineIndex: 0,
        episodeIndex: 0,
        url: null,
        name: null,
      );
    }

    if (initialEpisodeUrl != null && initialEpisodeUrl.trim().isNotEmpty) {
      final target = initialEpisodeUrl.trim();
      for (var li = 0; li < playLines.length; li++) {
        final line = playLines[li];
        for (var ei = 0; ei < line.episodes.length; ei++) {
          final ep = line.episodes[ei];
          if (_sameUrl(ep.url, target)) {
            return _PlaybackSelection(
              lineIndex: li,
              episodeIndex: ei,
              url: ep.url,
              name: ep.name,
            );
          }
        }
      }
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
      _resumeApplied = true;
    });

    _log('切换线路：${line.name}，首集：${firstEpisode.name}');
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
      _resumeApplied = true;
    });

    _log('切换集数：${episode.name} -> ${episode.url}');
  }

  void _playPreviousEpisode() {
    if (_selectedEpisodeIndex > 0) {
      _selectEpisode(_selectedEpisodeIndex - 1);
    }
  }

  void _playNextEpisode() {
    if (_playLines.isEmpty) return;

    final safeLineIndex = _selectedLineIndex.clamp(0, _playLines.length - 1);
    final line = _playLines[safeLineIndex];

    if (_selectedEpisodeIndex < line.episodes.length - 1) {
      _selectEpisode(_selectedEpisodeIndex + 1);
    }
  }

  bool _canPlayPrevious() {
    if (_playLines.isEmpty) return false;
    return _selectedEpisodeIndex > 0;
  }

  bool _canPlayNext() {
    if (_playLines.isEmpty) return false;
    final safeLineIndex = _selectedLineIndex.clamp(0, _playLines.length - 1);
    return _selectedEpisodeIndex < _playLines[safeLineIndex].episodes.length - 1;
  }

  int _effectiveInitialPosition() {
    final initialUrl = widget.initialEpisodeUrl?.trim();
    if (_resumeApplied) return 0;
    if (initialUrl == null || initialUrl.isEmpty) return 0;
    if (_currentEpisodeUrl == null) return 0;

    return _sameUrl(_currentEpisodeUrl!, initialUrl) ? widget.initialPosition : 0;
  }

  int _totalEpisodeCount() {
    return _playLines.fold<int>(0, (sum, line) => sum + line.episodes.length);
  }

  String _text(dynamic value) {
    if (value == null) return '';
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return '';
    return text;
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
            onPressed: _openDebugLogPage,
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
          : (_fullDetail == null ? _buildErrorView() : _buildDetailView()),
    );
  }

  Widget _buildDetailView() {
    final detail = _fullDetail!;
    final coverUrl = _resolveImageUrl(detail.vodPic);
    final totalEpisodes = _totalEpisodeCount();

    return Column(
      children: [
        Container(
          width: double.infinity,
          color: Colors.black,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: _currentEpisodeUrl != null
                ? VideoPlayContainer(
                    key: ValueKey<String>(
  '${_currentEpisodeUrl!}_${_selectedLineIndex}_${_selectedEpisodeIndex}',
),
                    url: _currentEpisodeUrl!,
                    title: detail.vodName,
                    vodId: widget.vodId.toString(),
                    vodPic: detail.vodPic ?? '',
                    sourceId: widget.source.id,
                    sourceName: widget.source.name,
                    episodeName: _currentEpisodeName ?? '正片',
                    initialPosition: _effectiveInitialPosition(),
                    referer: widget.source.detailUrl.trim().isNotEmpty
                        ? widget.source.detailUrl
                        : widget.source.url,
                    showDebugInfo: false,
                    onPreviousEpisode:
                        _canPlayPrevious() ? _playPreviousEpisode : null,
                    onNextEpisode: _canPlayNext() ? _playNextEpisode : null,
                  )
                : const Center(
                    child: Text(
                      '无可播放资源',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadDetail,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              children: [
                _buildInfoCard(detail, coverUrl, totalEpisodes),
                const SizedBox(height: 16),
                if (_playLines.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('暂无选集数据')),
                  )
                else ...[
                  if (_playLines.length > 1) ...[
                    _buildLineSelector(),
                    const SizedBox(height: 4),
                  ],
                  _buildEpisodeSection(),
                ],
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(Icons.error_outline_rounded, size: 72, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        Center(
          child: Text(
            _errorMessage ?? '视频详情加载失败',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 15),
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
        const SizedBox(height: 16),
        Center(
          child: TextButton.icon(
            onPressed: _openDebugLogPage,
            icon: const Icon(Icons.bug_report_outlined),
            label: const Text('查看调试日志'),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(
    VodItem detail,
    String? coverUrl,
    int totalEpisodes,
  ) {
    final tags = <String>[
      '来源：${widget.source.name}',
      if (_text(detail.typeName).isNotEmpty) '分类：${_text(detail.typeName)}',
      if (_text(detail.vodRemarks).isNotEmpty) '更新：${_text(detail.vodRemarks)}',
      if (_text(detail.vodTime).isNotEmpty) '时间：${_text(detail.vodTime)}',
      if (_text(detail.vodYear).isNotEmpty) '年份：${_text(detail.vodYear)}',
      if (_text(detail.vodArea).isNotEmpty) '地区：${_text(detail.vodArea)}',
      if (_text(detail.vodLang).isNotEmpty) '语言：${_text(detail.vodLang)}',
      if (_text(detail.vodDirector).isNotEmpty) '导演：${_text(detail.vodDirector)}',
      if (_text(detail.vodActor).isNotEmpty) '主演：${_text(detail.vodActor)}',
      '线路：${_playLines.length}',
      '集数：$totalEpisodes',
    ];

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
                  ? Container(
                      color: Colors.grey.shade100,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.movie_outlined,
                        size: 36,
                        color: Colors.grey.shade400,
                      ),
                    )
                  : Image.network(
                      coverUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.grey.shade100,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.movie_outlined,
                          size: 36,
                          color: Colors.grey.shade400,
                        ),
                      ),
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          color: Colors.grey.shade100,
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
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in tags) _buildTag(tag),
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
                if (_text(detail.vodContent).isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    _text(detail.vodContent),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
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
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildLineSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '播放线路',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
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
                  label: Text(
                    line.name,
                    style: TextStyle(
                      fontSize: 13,
                      color: selected ? Colors.white : Colors.black87,
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
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

  Widget _buildEpisodeSection() {
    final safeLineIndex = _playLines.isEmpty
        ? 0
        : _selectedLineIndex.clamp(0, _playLines.length - 1).toInt();

    final episodes = _playLines.isEmpty
        ? const <_PlayEpisode>[]
        : _playLines[safeLineIndex].episodes;

    return _ExpandableEpisodeSection(
      episodes: episodes,
      currentIndex: _selectedEpisodeIndex,
      onEpisodeTap: _selectEpisode,
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
  State<_ExpandableEpisodeSection> createState() =>
      _ExpandableEpisodeSectionState();
}

class _ExpandableEpisodeSectionState extends State<_ExpandableEpisodeSection> {
  bool _isExpanded = false;
  bool _isReversed = false;

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
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('当前线路暂无可播放集数')),
      );
    }

    final total = widget.episodes.length;
    final displayCount = _isExpanded ? total : (total > 12 ? 12 : total);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '选集',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (total > 1)
              TextButton.icon(
                onPressed: () => setState(() => _isReversed = !_isReversed),
                icon: const Icon(
                  Icons.sort_rounded,
                  size: 16,
                  color: Colors.blueAccent,
                ),
                label: Text(
                  _isReversed ? '切为正序' : '切为倒序',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.blueAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.builder(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: displayCount,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.2,
          ),
          itemBuilder: (context, index) {
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
      ],
    );
  }
}