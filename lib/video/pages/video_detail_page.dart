import 'package:flutter/material.dart';

import '../core/models.dart';
import '../video_module.dart';
import 'video_player_page.dart';

class VideoDetailPage extends StatefulWidget {
  const VideoDetailPage({
    super.key,
    required this.item,
  });

  final VideoItem item;

  @override
  State<VideoDetailPage> createState() => _VideoDetailPageState();
}

class _VideoDetailPageState extends State<VideoDetailPage> {
  VideoDetail? _detail;
  bool _loading = true;
  String? _errorMessage;

  int _selectedSourceIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final detail = await VideoModule.repository.fetchDetail(
        item: widget.item,
        forceRefresh: forceRefresh,
      );

      if (!mounted) return;

      setState(() {
        _detail = detail;
        _loading = false;

        if (detail.playSources.isEmpty) {
          _selectedSourceIndex = 0;
        } else {
          _selectedSourceIndex =
              _selectedSourceIndex.clamp(0, detail.playSources.length - 1).toInt();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.toString();
      });
    }
  }

  VideoPlaySource? get _currentSource {
    final detail = _detail;
    if (detail == null || detail.playSources.isEmpty) return null;

    final index = _selectedSourceIndex.clamp(0, detail.playSources.length - 1).toInt();
    return detail.playSources[index];
  }

  List<VideoEpisode> get _currentEpisodes {
    return _currentSource?.episodes ?? const [];
  }

  ({int sourceIndex, int episodeIndex})? _firstPlayableLocation() {
    final detail = _detail;
    if (detail == null) return null;

    for (var i = 0; i < detail.playSources.length; i++) {
      final episodes = detail.playSources[i].episodes;
      if (episodes.isNotEmpty) {
        return (sourceIndex: i, episodeIndex: 0);
      }
    }
    return null;
  }

  Future<void> _playNow() async {
    final detail = _detail;
    if (detail == null) return;

    final currentEpisodes = _currentEpisodes;
    if (currentEpisodes.isNotEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerPage(
            detail: detail,
            initialSourceIndex: _selectedSourceIndex,
            initialEpisodeIndex: 0,
          ),
        ),
      );
      return;
    }

    final first = _firstPlayableLocation();
    if (first == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前暂无可播放内容')),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerPage(
          detail: detail,
          initialSourceIndex: first.sourceIndex,
          initialEpisodeIndex: first.episodeIndex,
        ),
      ),
    );
  }

  Widget _buildCover(String url) {
    if (url.trim().isEmpty) {
      return Container(
        width: 128,
        height: 180,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F3F5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(
          Icons.movie_creation_outlined,
          size: 44,
          color: Colors.grey,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network(
        url,
        width: 128,
        height: 180,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return Container(
            width: 128,
            height: 180,
            color: const Color(0xFFF1F3F5),
            child: const Icon(
              Icons.broken_image_outlined,
              size: 40,
              color: Colors.grey,
            ),
          );
        },
      ),
    );
  }

  Widget _chip(IconData icon, String text) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(right: 10, bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FB),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF607D8B)),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final detail = _detail!;
    final item = detail.item;
    final cover = detail.cover.isNotEmpty ? detail.cover : item.cover;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCover(cover),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              if (detail.creator.trim().isNotEmpty)
                Text(
                  detail.creator,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
              const SizedBox(height: 18),
              Wrap(
                children: [
                  if (item.sourceName.isNotEmpty)
                    _chip(Icons.video_library_rounded, item.sourceName),
                  if (item.category.isNotEmpty)
                    _chip(Icons.bookmark_border_rounded, item.category),
                  if (item.yearText.isNotEmpty)
                    _chip(Icons.calendar_today_outlined, item.yearText),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF3E69A9),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: _playNow,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text(
                    '立即播放',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title, {String? trailing}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (trailing != null)
          Text(
            trailing,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
      ],
    );
  }

  Widget _buildDescription() {
    final detail = _detail!;
    final text = detail.description.trim().isEmpty ? '暂无剧情简介' : detail.description.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          height: 1.75,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildAggregationInfoCard() {
    final detail = _detail;
    if (detail == null || !detail.item.isAggregated) {
      return const SizedBox.shrink();
    }

    final sourceNames = detail.item.mergedItems
        .map((e) => e.sourceName.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .take(8)
        .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE9FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hub_rounded, color: Color(0xFF2E5FA8), size: 18),
              const SizedBox(width: 8),
              Text(
                '已聚合 ${detail.item.mergedSourceCount} 个站点 · ${detail.playSources.length} 条线路',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2E5FA8),
                ),
              ),
            ],
          ),
          if (sourceNames.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              sourceNames.join(' / '),
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black87,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlaySourceSection() {
    final detail = _detail!;
    final sources = detail.playSources;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          '播放线路',
          trailing: '共 ${sources.length} 条线路',
        ),
        const SizedBox(height: 14),
        if (sources.isEmpty)
          const Text('当前没有可用播放线路')
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: List.generate(sources.length, (index) {
              final source = sources[index];
              final selected = index == _selectedSourceIndex;

              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  setState(() {
                    _selectedSourceIndex = index;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFFEAF2FF) : const Color(0xFFF6F8FB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? const Color(0xFF4A78C2) : Colors.transparent,
                      width: 1.2,
                    ),
                  ),
                  child: Text(
                    '${source.name} (${source.episodeCount})',
                    style: TextStyle(
                      fontSize: 14,
                      color: selected ? const Color(0xFF2E5FA8) : Colors.black87,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              );
            }),
          ),
      ],
    );
  }

  Widget _buildEpisodeSection() {
    final episodes = _currentEpisodes;
    final source = _currentSource;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          '选集',
          trailing: source == null ? null : '${source.name} · 共 ${episodes.length} 集',
        ),
        const SizedBox(height: 14),
        if (episodes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('当前线路暂无可播放集数'),
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: List.generate(episodes.length, (index) {
              final episode = episodes[index];

              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  final detail = _detail;
                  if (detail == null) return;

                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => VideoPlayerPage(
                        detail: detail,
                        initialSourceIndex: _selectedSourceIndex,
                        initialEpisodeIndex: index,
                      ),
                    ),
                  );
                },
                child: Container(
                  width: 108,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F8FA),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    episode.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }),
          ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 42, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(height: 1.5),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => _loadDetail(forceRefresh: true),
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_detail == null) {
      return const Center(child: Text('暂无详情'));
    }

    return RefreshIndicator(
      onRefresh: () => _loadDetail(forceRefresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _buildHeader(),
          const SizedBox(height: 28),
          _sectionTitle('简介'),
          const SizedBox(height: 14),
          _buildDescription(),
          if (_detail?.item.isAggregated == true) ...[
            const SizedBox(height: 18),
            _buildAggregationInfoCard(),
          ],
          const SizedBox(height: 28),
          _buildPlaySourceSection(),
          const SizedBox(height: 28),
          _buildEpisodeSection(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _detail?.item.title ?? widget.item.title;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(title),
        centerTitle: false,
        actions: [
          IconButton(
            onPressed: () => _loadDetail(forceRefresh: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
}