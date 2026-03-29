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

class _VideoDetailBundle {
  final VideoDetail detail;
  final VideoPlaybackProgress? progress;

  const _VideoDetailBundle({
    required this.detail,
    required this.progress,
  });
}

class _VideoDetailPageState extends State<VideoDetailPage> {
  late Future<_VideoDetailBundle> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadBundle();
  }

  Future<_VideoDetailBundle> _loadBundle() async {
    final detail = await VideoModule.repository.fetchDetail(item: widget.item);
    final progress = await VideoModule.repository.getProgress(detail.item.id);
    return _VideoDetailBundle(detail: detail, progress: progress);
  }

  void _reload() {
    setState(() {
      _future = _loadBundle();
    });
  }

  void _openPlayer(VideoDetail detail, int episodeIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerPage(
          detail: detail,
          initialEpisodeIndex: episodeIndex,
        ),
      ),
    ).then((_) => _reload());
  }

  void _continuePlaying(VideoDetail detail, VideoPlaybackProgress progress) {
    if (detail.episodes.isEmpty) return;
    final index = progress.episodeIndex.clamp(0, detail.episodes.length - 1).toInt();
    _openPlayer(detail, index);
  }

  String _formatDuration(double seconds) {
    if (seconds <= 0) return '--:--';
    final d = Duration(milliseconds: (seconds * 1000).round());
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);

    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildCover(String url) {
    if (url.isEmpty) return _placeholder();
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFFE9ECEF),
      child: Center(
        child: Icon(Icons.movie_outlined, size: 44, color: Colors.grey[500]),
      ),
    );
  }

  Widget _chip(String text, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: Colors.blueGrey),
            const SizedBox(width: 6),
          ],
          Text(text, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildProgressCard(VideoDetail detail, VideoPlaybackProgress progress) {
    if (detail.episodes.isEmpty) return const SizedBox.shrink();

    final index = progress.episodeIndex.clamp(0, detail.episodes.length - 1).toInt();
    final episodeTitle = detail.episodes[index].title;

    return Card(
      elevation: 0,
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: Colors.blue.shade100,
              child: Icon(Icons.history, color: Colors.blue.shade700),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '上次播放',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '第 ${index + 1} 集 · $episodeTitle\n'
                    '进度 ${_formatDuration(progress.positionSeconds)} / ${_formatDuration(progress.durationSeconds)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.blueGrey[700],
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _continuePlaying(detail, progress),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('继续播放'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEpisodeTile(
    VideoDetail detail,
    int index,
    VideoEpisode episode,
    VideoPlaybackProgress? progress,
  ) {
    final isCurrent = progress != null && progress.episodeIndex == index;

    return Card(
      elevation: 0,
      color: isCurrent ? Colors.blue.shade50 : const Color(0xFFF8F9FA),
      child: ListTile(
        onTap: () => _openPlayer(detail, index),
        leading: CircleAvatar(
          backgroundColor: isCurrent ? Colors.blue.shade100 : Colors.grey.shade200,
          child: Icon(
            isCurrent ? Icons.play_circle_fill : Icons.play_arrow,
            color: isCurrent ? Colors.blue.shade700 : Colors.grey.shade700,
          ),
        ),
        title: Text(
          episode.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [
            if (episode.durationText.isNotEmpty) episode.durationText,
            if (isCurrent) '最近播放',
          ].join(' · '),
        ),
        trailing: isCurrent
            ? const Icon(Icons.check_circle, color: Colors.green)
            : const Icon(Icons.chevron_right),
      ),
    );
  }

  Widget _sectionTitle(String title, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (subtitle != null) ...[
            const SizedBox(width: 10),
            Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<_VideoDetailBundle>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(snapshot.error.toString(), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _reload,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            );
          }

          final detail = snapshot.data!.detail;
          final progress = snapshot.data!.progress;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    height: 160,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _buildCover(detail.item.coverUrl),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          detail.item.title,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          detail.creator.isNotEmpty ? detail.creator : '未知导演 / 作者',
                          style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (detail.item.sourceName.isNotEmpty)
                              _chip(detail.item.sourceName, icon: Icons.source),
                            if (detail.item.category.isNotEmpty)
                              _chip(detail.item.category, icon: Icons.folder_outlined),
                            if (detail.item.yearText.isNotEmpty)
                              _chip(detail.item.yearText, icon: Icons.event_outlined),
                          ],
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: detail.episodes.isEmpty ? null : () => _openPlayer(detail, 0),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('立即播放'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              if (progress != null && detail.episodes.isNotEmpty)
                _buildProgressCard(detail, progress),

              const SizedBox(height: 16),
              _sectionTitle('简介'),
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    detail.description.isNotEmpty ? detail.description : '暂无简介',
                    style: const TextStyle(height: 1.6, fontSize: 14),
                  ),
                ),
              ),

              const SizedBox(height: 16),
              _sectionTitle('标签', subtitle: detail.tags.isEmpty ? '暂无标签' : '${detail.tags.length} 个标签'),
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: detail.tags.isEmpty
                        ? [Text('暂无标签', style: TextStyle(color: Colors.grey[600]))]
                        : detail.tags.map((e) => _chip(e, icon: Icons.tag_outlined)).toList(),
                  ),
                ),
              ),

              const SizedBox(height: 16),
              _sectionTitle('选集', subtitle: '${detail.episodes.length} 个片源'),
              if (detail.episodes.isEmpty)
                Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('未找到可播放片源', style: TextStyle(color: Colors.grey[600])),
                  ),
                )
              else
                Column(
                  children: [
                    for (var i = 0; i < detail.episodes.length; i++)
                      _buildEpisodeTile(detail, i, detail.episodes[i], progress),
                  ],
                ),

              const SizedBox(height: 16),
              _sectionTitle('来源'),
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    detail.sourceUrl.isNotEmpty ? detail.sourceUrl : detail.item.detailUrl,
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}