import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart'; // 🚀 引入高性能图片缓存

import '../../models/video_source.dart';
import '../../models/vod_item.dart';
import 'detail_models.dart';

class DetailInfoCard extends StatelessWidget {
  const DetailInfoCard({
    super.key,
    required this.detail,
    required this.source,
    required this.coverUrl,
    required this.lineCount,
    required this.totalEpisodeCount,
    required this.currentEpisodeName,
  });

  final VodItem detail;
  final VideoSource source;
  final String? coverUrl;
  final int lineCount;
  final int totalEpisodeCount;
  final String currentEpisodeName;

  String? _text(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final tags = <String>[
      '来源：${source.name}',
      if (_text(detail.typeName) != null) '分类：${_text(detail.typeName)}',
      if (_text(detail.vodRemarks) != null) '更新：${_text(detail.vodRemarks)}',
      if (_text(detail.vodTime) != null) '时间：${_text(detail.vodTime)}',
      if (_text(detail.vodYear) != null) '年份：${_text(detail.vodYear)}',
      if (_text(detail.vodArea) != null) '地区：${_text(detail.vodArea)}',
      if (_text(detail.vodLang) != null) '语言：${_text(detail.vodLang)}',
      if (_text(detail.vodDirector) != null) '导演：${_text(detail.vodDirector)}',
      if (_text(detail.vodActor) != null) '主演：${_text(detail.vodActor)}',
      '线路：$lineCount',
      '集数：$totalEpisodeCount',
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
              child: _buildCoverImage(),
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
                    for (final tag in tags) _buildTag(context, tag),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '当前播放：$currentEpisodeName',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 13,
                  ),
                ),
                if (_text(detail.vodContent) != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _text(detail.vodContent)!,
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

  // 🏆 提取图片构建方法，使用高性能组件
  Widget _buildCoverImage() {
    final url = coverUrl?.trim();
    if (url == null || url.isEmpty) {
      return _buildPlaceholder();
    }

    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        color: Colors.grey.shade100,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      errorWidget: (context, url, error) => _buildPlaceholder(),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey.shade100,
      alignment: Alignment.center,
      child: Icon(
        Icons.movie_outlined,
        size: 36,
        color: Colors.grey.shade400,
      ),
    );
  }

  Widget _buildTag(BuildContext context, String text) {
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
}