import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SearchResultCard extends StatelessWidget {
  const SearchResultCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.coverUrl, // 🚀 变量类型从 Future<String?>? 改为了极速的 String?
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final String? coverUrl;
  final VoidCallback? onTap;

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
                child: _buildImage(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildImage() {
    final imageUrl = coverUrl?.trim();
    if (imageUrl == null || imageUrl.isEmpty) {
      return _buildPlaceholder();
    }

    // 网格卡片宽约 120px，源站封面常为 1000×1500 大图。限制解码宽到 300px
    // （3 列网格在高密度屏也够清晰），避免全尺寸解码——此前缺这行，多图
    // 网格会把每张大图全尺寸解码进内存，快速滑动明显丢帧。与聚合卡片
    // 的 memCacheWidth 策略对齐。
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      memCacheWidth: 300,
      // 短淡入替代硬闪：缓存命中瞬显，新图柔和出现，主观更快。
      fadeInDuration: const Duration(milliseconds: 180),
      fadeOutDuration: const Duration(milliseconds: 80),
      placeholder: (context, url) => Container(
        color: Colors.grey.shade200,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      errorWidget: (context, url, error) => _buildPlaceholder(),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey.shade300,
      alignment: Alignment.center,
      child: Icon(Icons.movie_outlined, size: 34, color: Colors.grey.shade600),
    );
  }
}
