import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart'; // 🚀 引入高性能图片缓存

import '../../models/aggregate_result.dart';

class AggregateSearchVideoCard extends StatelessWidget {
  const AggregateSearchVideoCard({
    super.key,
    required this.result,
    required this.coverUrl, // 🚀 优化：直接接收同步字符串
    required this.onTap,
  });

  final AggregateResult result;
  final String? coverUrl;
  final VoidCallback? onTap;

  String? _text(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final title = _text(result.video.vodName) ?? '未命名';
    final subtitle = _text(result.video.vodRemarks) ?? result.source.name;

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
                  child: _buildImage(), // 🚀 切换到高性能缓存构建器
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
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

  // 🏆 封装高性能的 CachedNetworkImage
  Widget _buildImage() {
    final imageUrl = coverUrl?.trim();

    if (imageUrl == null || imageUrl.isEmpty) {
      return _buildPlaceholder();
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        color: Colors.grey.shade200,
        alignment: Alignment.center,
        child: const SizedBox(
           width: 18, height: 18,
           child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      errorWidget: (context, url, error) => _buildPlaceholder(),
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