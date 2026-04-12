import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../models/vod_item.dart';
import 'home_empty_state.dart';

// 🏆 优化：签名从 Future<String?> 变为极速同步的 String?
typedef HomeVideoCoverLoader = String? Function(VodItem video);

class HomeVideoSliverGrid extends StatelessWidget {
  const HomeVideoSliverGrid({
    super.key,
    required this.videos,
    required this.screenWidth,
    required this.coverUrlFor,
    required this.onTapVideo,
    required this.isLoading,
    required this.emptyMessage,
    this.emptyActionLabel,
    this.onEmptyAction,
  });

  final List<VodItem> videos;
  final double screenWidth;
  final HomeVideoCoverLoader coverUrlFor;
  final ValueChanged<VodItem> onTapVideo;
  final bool isLoading;
  final String emptyMessage;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;

  @override
  Widget build(BuildContext context) {
    if (isLoading && videos.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在加载视频，请稍候...'),
            ],
          ),
        ),
      );
    }

    if (videos.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: HomeEmptyState(
          message: emptyMessage,
          actionLabel: emptyActionLabel,
          onAction: onEmptyAction,
          icon: Icons.movie_outlined,
        ),
      );
    }

    final crossAxisCount = screenWidth > 800 ? 6 : (screenWidth > 500 ? 4 : 3);

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final video = videos[index];
            return HomeVideoCard(
              video: video,
              // 🚀 极速传递 URL 字符串，彻底消灭渲染延迟闪烁
              coverUrl: coverUrlFor(video), 
              onTap: () => onTapVideo(video),
            );
          },
          childCount: videos.length,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 12,
          crossAxisSpacing: 10,
          childAspectRatio: 0.55,
        ),
      ),
    );
  }
}

class HomeVideoCard extends StatelessWidget {
  const HomeVideoCard({
    super.key,
    required this.video,
    required this.coverUrl,
    required this.onTap,
  });

  final VodItem video;
  final String? coverUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final title = video.vodName.trim().isNotEmpty ? video.vodName : '未命名';
    final subtitle = (video.vodRemarks?.trim().isNotEmpty == true)
        ? video.vodRemarks
        : video.typeName;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SizedBox(
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: _buildImage(),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
          ),
          Text(
            subtitle ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
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

    // 🏆 终极方案：使用 CachedNetworkImage。不仅彻底接管本地缓存，而且滑卡直接飞起
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      placeholder: (context, url) => Container(
        color: Colors.grey.shade200,
        alignment: Alignment.center,
        child: const SizedBox(
           width: 20, height: 20,
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
      child: Icon(Icons.movie_outlined, size: 28, color: Colors.grey.shade400),
    );
  }
}