import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/vod_item.dart';
import 'home_empty_state.dart';
import '../../../design_system/app_tokens.dart';

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
    this.onItemBuild,
  });

  final List<VodItem> videos;
  final double screenWidth;
  final HomeVideoCoverLoader coverUrlFor;
  final ValueChanged<VodItem> onTapVideo;
  final bool isLoading;
  final String emptyMessage;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;

  /// 网格构建到第 index 项时回调，用于随滚动分批预取视口附近封面。
  final ValueChanged<int>? onItemBuild;

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

    final effectiveWidth = screenWidth >= 560 ? 560.0 : screenWidth;

    // 新版视频首页：手机端固定 2 列大封面卡片，平板/窄桌面保持 2 列，
    // 让用户一眼看到“封面墙”而不是旧的小图密集网格。
    const crossAxisCount = 2;
    // 略微降低卡片高度，让首屏能多露出一点内容（更重封面本身、页脚更薄）。
    final childAspectRatio = effectiveWidth >= 520 ? 0.64 : 0.62;

    const horizontalPadding = 24.0;
    const crossAxisSpacing = 12.0;
    const mainAxisSpacing = 14.0;

    final itemWidth =
        (effectiveWidth -
            horizontalPadding -
            (crossAxisCount - 1) * crossAxisSpacing) /
        crossAxisCount;
    final itemHeight = itemWidth / childAspectRatio;

    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cacheWidth = max(1, (itemWidth * dpr).round());
    final cacheHeight = max(1, (itemHeight * dpr).round());

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            onItemBuild?.call(index);
            final video = videos[index];
            final coverUrl = coverUrlFor(video);

            return RepaintBoundary(
              child: HomeVideoCard(
                video: video,
                coverUrl: coverUrl,
                onTap: () => onTapVideo(video),
                cacheWidth: cacheWidth,
                cacheHeight: cacheHeight,
              ),
            );
          },
          childCount: videos.length,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: mainAxisSpacing,
          crossAxisSpacing: crossAxisSpacing,
          childAspectRatio: childAspectRatio,
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
    required this.cacheWidth,
    required this.cacheHeight,
  });

  final VodItem video;
  final String? coverUrl;
  final VoidCallback? onTap;
  final int cacheWidth;
  final int cacheHeight;

  String _safeText(String? value, {String fallback = ''}) {
    final text = value?.trim();
    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return fallback;
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final title = _safeText(video.vodName, fallback: '未命名');

    final remarks = _safeText(video.vodRemarks);
    final typeName = _safeText(video.typeName);
    final subtitle = remarks.isNotEmpty ? remarks : typeName;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTokens.inkDark,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        // 干净海报：整卡即封面，信息压在底部渐变里，不再有图下页脚。
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildImage(),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 22, 10, 9),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.82),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (typeName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        typeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.62),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // 更新信息移到左上，改半透明黑毛玻璃，不与片名抢亮度。
            if (subtitle.isNotEmpty)
              Positioned(
                top: 8,
                left: 8,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.42),
                        borderRadius: BorderRadius.circular(
                          AppTokens.radiusPill,
                        ),
                      ),
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage() {
    final imageUrl = coverUrl?.trim();

    if (imageUrl == null || imageUrl.isEmpty) {
      return const _VideoCoverPlaceholder();
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      memCacheWidth: cacheWidth,
      memCacheHeight: cacheHeight,
      useOldImageOnUrlChange: true,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder: (context, url) => const _VideoCoverPlaceholder(),
      errorWidget: (context, url, error) => const _VideoCoverPlaceholder(),
    );
  }
}

class _VideoCoverPlaceholder extends StatelessWidget {
  const _VideoCoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTokens.inkDark, Color(0xFF1D4ED8), Color(0xFF22D3EE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.movie_creation_outlined,
          size: 32,
          color: Colors.white.withValues(alpha: 0.88),
        ),
      ),
    );
  }
}
