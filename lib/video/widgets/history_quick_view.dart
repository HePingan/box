import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_bottom_sheet.dart';

import '../controller/history_controller.dart';
import '../controller/video_controller.dart';
import '../models/history_item.dart';
import '../models/video_source.dart';
import '../pages/video_detail_page.dart';
import '../pages/watch_history_page.dart';

class HistoryQuickView extends StatelessWidget {
  const HistoryQuickView({
    super.key,
    this.title = '播放历史',
    this.subtitle = '最近播放记录',
    this.emptyText = '暂无播放历史',
  });

  final String title;
  final String subtitle;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return Consumer<HistoryController>(
      builder: (context, controller, _) {
        final items = controller.historyList;

        return RepaintBoundary(
          child: Card(
            elevation: 0,
            color: AppTokens.inkDark,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
              side: const BorderSide(color: Color(0xFF273449)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context, controller, items.length),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.white.withValues(alpha: 0.60),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Center(
                        child: Text(
                          emptyText,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.60),
                          ),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height: 172,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const ClampingScrollPhysics(),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return RepaintBoundary(
                            child: _HistoryCard(
                              item: item,
                              onTap: () => _openHistoryItem(context, item),
                              onLongPress: () =>
                                  _confirmDelete(context, controller, item),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context,
    HistoryController controller,
    int itemCount,
  ) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
        const Spacer(),
        if (itemCount > 0)
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WatchHistoryPage()),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '查看全部',
                  style: TextStyle(
                    color: Color(0xFFFFE08A),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: Color(0xFFFFE08A),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _openHistoryItem(BuildContext context, HistoryItem item) {
    final videoController = context.read<VideoController>();
    final targetSource = _findSourceById(
      videoController.sources,
      item.sourceId,
    );

    if (targetSource == null) {
      _showSnackBar(context, '该视频的片源已失效或被移除');
      return;
    }

    final vodId = int.tryParse(item.vodId) ?? 0;
    if (vodId <= 0) {
      _showSnackBar(context, '历史记录中的视频ID无效');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoDetailPage(
          source: targetSource,
          vodId: vodId,
          initialEpisodeUrl: item.episodeUrl,
          initialPosition: item.position,
        ),
      ),
    );
  }

  VideoSource? _findSourceById(List<VideoSource> sources, String sourceId) {
    for (final source in sources) {
      if (source.id == sourceId) return source;
    }
    return null;
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _showHistoryConfirmSheet(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showAppModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => AppBottomSheetFrame(
        title: title,
        subtitle: '这个操作会立即更新本机播放历史。',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTokens.rose.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                border: Border.all(
                  color: AppTokens.rose.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: AppTokens.rose,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: AppTokens.textPrimary,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(sheetContext, false),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTokens.rose,
                    ),
                    onPressed: () => Navigator.pop(sheetContext, true),
                    child: Text(confirmLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return result == true;
  }

  Future<void> _confirmDelete(
    BuildContext context,
    HistoryController controller,
    HistoryItem item,
  ) async {
    final confirmed = await _showHistoryConfirmSheet(
      context,
      title: '删除记录',
      message: '确定删除「${item.vodName}」的观看记录吗？',
      confirmLabel: '删除',
    );
    if (!confirmed) return;
    await controller.deleteHistory(item);
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.item,
    required this.onTap,
    required this.onLongPress,
  });

  final HistoryItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final progress = (item.progressPercentage * 100).clamp(0, 100).toInt();
    final imageUrl = item.vodPic.trim();
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cacheWidth = (96 * dpr).round();
    final cacheHeight = (134 * dpr).round();

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: 96,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (imageUrl.isEmpty)
                      const _HistoryImagePlaceholder()
                    else
                      CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: cacheWidth,
                        memCacheHeight: cacheHeight,
                        useOldImageOnUrlChange: true,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        httpHeaders: const {
                          'User-Agent':
                              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
                        },
                        placeholder: (context, url) =>
                            const _HistoryLoadingPlaceholder(),
                        errorWidget: (context, url, error) =>
                            const _HistoryImagePlaceholder(),
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.85),
                            ],
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$progress%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(
                              value: item.progressPercentage,
                              minHeight: 2.5,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.15,
                              ),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFFFFE08A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              item.vodName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.white,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.episodeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.70),
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(
                  Icons.video_library_rounded,
                  size: 10,
                  color: Color(0xFFFFE08A),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    item.sourceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.54),
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryLoadingPlaceholder extends StatelessWidget {
  const _HistoryLoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade100,
      alignment: Alignment.center,
      child: const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class _HistoryImagePlaceholder extends StatelessWidget {
  const _HistoryImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade100,
      alignment: Alignment.center,
      child: Icon(
        Icons.movie_outlined,
        size: 32,
        color: Colors.white.withValues(alpha: 0.72),
      ),
    );
  }
}
