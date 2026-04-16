import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

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

  /// 把简介里的 HTML 标签清理掉，并尽量保留换行
  String? _normalizeSynopsis(String? raw) {
    final sourceText = _text(raw);
    if (sourceText == null) return null;

    var text = sourceText
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");

    text = text
        .replaceAll(RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(r'</\s*(p|div|li|section|article|tr|h[1-6])\s*>',
              caseSensitive: false),
          '\n',
        )
        .replaceAll(RegExp(r'<\s*p[^>]*>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<\s*div[^>]*>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<[^>]+>'), '');

    final lines = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (lines.isEmpty) return null;
    return lines.join('\n');
  }

  Widget _buildTag(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
      ),
    );
  }

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

  Widget _buildTopInfo(
    BuildContext context,
    bool isNarrow,
    List<String> tags,
  ) {
    final title = Text(
      detail.vodName,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        height: 1.15,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );

    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 120,
                height: 170,
                child: _buildCoverImage(),
              ),
            ),
          ),
          const SizedBox(height: 14),
          title,
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final tag in tags) _buildTag(context, tag)],
          ),
        ],
      );
    }

    return Row(
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
              title,
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final tag in tags) _buildTag(context, tag)],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final synopsis = _normalizeSynopsis(detail.vodContent);

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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 420;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopInfo(context, isNarrow, tags),
              const SizedBox(height: 12),
              Text(
                '当前播放：$currentEpisodeName',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (synopsis != null && synopsis.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildSectionTitle(context, '简介'),
                const SizedBox(height: 8),
                Text(
                  synopsis,
                  maxLines: isNarrow ? 6 : 5,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}