import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart'; // 🚀 引入高性能图片缓存

import '../../models/aggregate_result.dart';

/// 聚合搜索封面统一解码宽度(px)。卡片解码与搜索页预取共用此值,
/// 确保预取的即展示的那份内存缓存,零重复解码。卡片宽仅 96px,
/// 200px 在高密度屏也足够清晰,又远小于源站 1000+ 原图。
const int kAggregateCoverDecodeWidth = 200;

class AggregateSearchVideoCard extends StatelessWidget {
  const AggregateSearchVideoCard({
    super.key,
    required this.result,
    required this.coverUrl, // 🚀 优化：直接接收同步字符串
    required this.onTap,
    this.sourceLabel,
  });

  final AggregateResult result;
  final String? coverUrl;
  final VoidCallback? onTap;

  /// 分组视图下用于标注该卡片来自哪个源；为空时回退到备注/源名。
  final String? sourceLabel;

  String? _text(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final title = _text(result.video.vodName) ?? '未命名';
    final subtitle =
        _text(sourceLabel) ??
        _text(result.video.vodRemarks) ??
        result.source.name;

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
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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

    // 卡片宽仅 96px,源站封面常为 1000×1500 大图。限制解码宽到 200px
    // (足够小卡清晰),避免全尺寸解码——解码量降一个数量级,多图列表
    // 明显跟手,内存也大幅下降。此值与搜索页 _precacheCovers 的 maxWidth
    // 保持一致,确保预取的即展示的那份,零重复解码。
    const decodeWidth = kAggregateCoverDecodeWidth;
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      memCacheWidth: decodeWidth,
      // 短淡入替代硬闪:缓存命中瞬显,新图柔和出现,主观更快。
      fadeInDuration: const Duration(milliseconds: 180),
      fadeOutDuration: const Duration(milliseconds: 80),
      placeholder: (context, url) => Container(
        color: Colors.grey.shade200,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 18,
          height: 18,
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
      child: Icon(Icons.movie_outlined, size: 30, color: Colors.grey.shade600),
    );
  }
}
