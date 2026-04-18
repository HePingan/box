import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/vod_item.dart';
import 'home_empty_state.dart';

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

  String _safeText(String? value, {String fallback = ''}) {
    final text = value?.trim();
    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return fallback;
    }
    return text;
  }

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

    final crossAxisCount = effectiveWidth >= 520
        ? 4
        : effectiveWidth >= 360
            ? 3
            : 2;

    final childAspectRatio = effectiveWidth >= 520
        ? 0.62
        : effectiveWidth >= 360
            ? 0.58
            : 0.52;

    final horizontalPadding = 24.0;
    final crossAxisSpacing = 10.0;
    final mainAxisSpacing = 12.0;

    final itemWidth =
        (effectiveWidth - horizontalPadding - (crossAxisCount - 1) * crossAxisSpacing) /
            crossAxisCount;
    final itemHeight = itemWidth / childAspectRatio;

    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cacheWidth = max(1, (itemWidth * dpr).round());
    final cacheHeight = max(1, (itemHeight * dpr).round());

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
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
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SizedBox(
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _buildImage(),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Colors.black87,
            ),
          ),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
              ),
            )
          else
            const SizedBox(height: 14),
        ],
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
    return ColoredBox(
      color: Color(0xFFECEFF1),
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          size: 28,
          color: Colors.grey,
        ),
      ),
    );
  }
}