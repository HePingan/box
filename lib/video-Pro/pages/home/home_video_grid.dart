import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/vod_item.dart';
import 'package:box/utils/app_logger.dart';
import 'home_empty_state.dart';

// 极速同步封面地址加载
typedef HomeVideoCoverLoader = String? Function(VodItem video);

void _logGrid(String message) {
  if (kDebugMode) {
    AppLogger.instance.log(message, tag: 'HOME_GRID');
  }
}

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

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final video = videos[index];
            final coverUrl = coverUrlFor(video);

            _logGrid(
              '[CARD] vodId=${video.vodId} '
              'vodName=${_safeText(video.vodName, fallback: "未命名")} '
              'vodPic=${video.vodPic ?? "null"} '
              'coverUrl=${coverUrl ?? "null"}',
            );

            return HomeVideoCard(
              video: video,
              coverUrl: coverUrl,
              onTap: () => onTapVideo(video),
            );
          },
          childCount: videos.length,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 12,
          crossAxisSpacing: 10,
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
  });

  final VodItem video;
  final String? coverUrl;
  final VoidCallback? onTap;

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
                child: _buildImage(title),
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

  Widget _buildImage(String title) {
    final imageUrl = coverUrl?.trim();

    if (imageUrl == null || imageUrl.isEmpty) {
      _logGrid(
        '[IMG_EMPTY] vodId=${video.vodId} title=$title '
        'vodPic=${video.vodPic ?? "null"}',
      );
      return _buildPlaceholder();
    }

    _logGrid(
      '[IMG_LOAD] vodId=${video.vodId} title=$title url=$imageUrl',
    );

    // 临时 debug 版：用 Image.network 更容易看到 Web/CORS/404 的错误
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        _logGrid(
          '[IMG_ERROR] vodId=${video.vodId} title=$title '
          'url=$imageUrl error=$error',
        );
        return _buildPlaceholder();
      },
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: Icon(
        Icons.movie_outlined,
        size: 28,
        color: Colors.grey.shade400,
      ),
    );
  }
}