import 'package:flutter/material.dart';

import '../../core/models.dart';

class VideoPlayerDetailsView extends StatelessWidget {
  final VideoDetail detail;
  final int currentSourceIndex;
  final int currentEpisodeIndex;
  final VideoPlaybackProgress? savedProgress;
  final ValueChanged<int> onSwitchSource;
  final ValueChanged<int> onSwitchEpisode;

  const VideoPlayerDetailsView({
    super.key,
    required this.detail,
    required this.currentSourceIndex,
    required this.currentEpisodeIndex,
    this.savedProgress,
    required this.onSwitchSource,
    required this.onSwitchEpisode,
  });

  VideoPlaySource? get _currentSource {
    final sources = detail.playSources;
    if (sources.isEmpty) return null;
    final index = currentSourceIndex.clamp(0, sources.length - 1).toInt();
    return sources[index];
  }

  List<VideoEpisode> get _currentEpisodes {
    return _currentSource?.episodes ?? const [];
  }

  @override
  Widget build(BuildContext context) {
    final item = detail.item;
    final currentSource = _currentSource;
    final episodes = _currentEpisodes;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (item.sourceName.isNotEmpty) PlayerChip(text: item.sourceName),
              if (item.yearText.isNotEmpty) PlayerChip(text: item.yearText),
              if (item.category.isNotEmpty) PlayerChip(text: item.category),
              if (currentSource != null)
                PlayerChip(text: '当前线路：${currentSource.name}'),
            ],
          ),
          if (savedProgress != null && savedProgress!.positionSeconds > 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Icon(Icons.history, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Text(
                    '上次观看到：第 ${savedProgress!.episodeIndex + 1} 集',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          const SectionHeader(title: '全片源'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(detail.playSources.length, (index) {
              final source = detail.playSources[index];
              return PlayerChip(
                text: '${source.name} (${source.episodes.length})',
                selected: index == currentSourceIndex,
                onTap: () => onSwitchSource(index),
              );
            }),
          ),
          const SizedBox(height: 24),
          SectionHeader(
            title: '选集',
            trailing: currentSource == null ? null : '共 ${episodes.length} 集',
          ),
          const SizedBox(height: 12),
          if (episodes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('当前线路暂无可播放集数'),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              primary: false,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: episodes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final episode = episodes[index];
                final isCurrent = index == currentEpisodeIndex;

                return InkWell(
                  onTap: () => onSwitchEpisode(index),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isCurrent ? Colors.blue.shade50 : const Color(0xFFF7F8FA),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isCurrent ? Icons.play_arrow : Icons.play_circle_outline,
                          size: 20,
                          color: isCurrent ? Colors.blue : Colors.grey,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            episode.title,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 14,
                              color: isCurrent ? Colors.blue.shade800 : Colors.black87,
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 24),
          const SectionHeader(title: '简介'),
          const SizedBox(height: 10),
          Text(
            detail.description.isNotEmpty ? detail.description : '暂无剧情简介',
            style: const TextStyle(height: 1.6, fontSize: 14, color: Colors.black87),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class PlayerChip extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback? onTap;

  const PlayerChip({
    super.key,
    required this.text,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.blue.shade50 : const Color(0xFFF6F7F9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? Colors.blue : Colors.transparent),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: selected ? Colors.blue.shade700 : Colors.black87,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;

  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        if (trailing != null)
          Text(trailing!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
