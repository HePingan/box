import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_bottom_sheet.dart';
import 'package:box/design_system/widgets/app_page_scaffold.dart';

import '../controller/favorites_controller.dart';
import '../controller/video_controller.dart';
import '../services/favorites_repository.dart';
import '../models/video_source.dart';
import 'video_detail_page.dart';
import 'video_downloads_page.dart';

/// 独立收藏/追剧页：网格展示、左滑删除单条、一键清空。
class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      child: Consumer<FavoritesController>(
        builder: (context, controller, _) {
          final items = controller.items;

          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: _buildHeader(context, controller, items.length),
              ),
              if (items.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyFavorites(),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 130,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.56,
                        ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final item = items[index];
                      return _FavoriteCard(
                        item: item,
                        onTap: () => _openFavorite(context, item),
                        onLongPress: () =>
                            _confirmDelete(context, controller, item),
                      );
                    }, childCount: items.length),
                  ),
                ),
              const SliverToBoxAdapter(
                child: SizedBox(height: AppTokens.pageBottomPadding + 24),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    FavoritesController controller,
    int count,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            color: AppTokens.textPrimary,
          ),
          const SizedBox(width: 2),
          const Text(
            '我的追剧',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppTokens.textPrimary,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 8),
            Text(
              '$count',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTokens.textSecondary,
              ),
            ),
          ],
          const Spacer(),
          if (count > 0)
            IconButton(
              icon: const Icon(Icons.file_download_rounded, size: 22),
              color: AppTokens.primaryBlue,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VideoDownloadsPage()),
              ),
            ),
          if (count > 0) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () => _confirmClear(context, controller),
              icon: const Icon(Icons.delete_sweep_rounded, size: 18),
              label: const Text('清空'),
              style: TextButton.styleFrom(foregroundColor: AppTokens.rose),
            ),
          ],
        ],
      ),
    );
  }

  void _openFavorite(BuildContext context, FavoriteItem item) {
    final videoController = context.read<VideoController>();
    final targetSource = _findSource(videoController.sources, item);

    if (targetSource == null) {
      _showSnackBar(context, '该视频的片源已失效或被移除');
      return;
    }

    if (item.vodId <= 0) {
      _showSnackBar(context, '收藏记录中的视频ID无效');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            VideoDetailPage(source: targetSource, vodId: item.vodId),
      ),
    );
  }

  VideoSource? _findSource(List<VideoSource> sources, FavoriteItem item) {
    for (final source in sources) {
      if (source.id == item.sourceId) return source;
    }
    // 回退：按 URL 匹配（收藏时 sourceId 可能取的是 url）。
    for (final source in sources) {
      if (source.url == item.sourceId || source.url == item.sourceUrl) {
        return source;
      }
    }
    return null;
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmDelete(
    BuildContext context,
    FavoritesController controller,
    FavoriteItem item,
  ) async {
    final confirmed = await _showConfirmSheet(
      context,
      title: '取消收藏',
      message: '确定要取消收藏「${item.vodName}」吗？',
      confirmLabel: '取消收藏',
    );
    if (!confirmed) return;
    await controller.removeItem(item);
  }

  Future<void> _confirmClear(
    BuildContext context,
    FavoritesController controller,
  ) async {
    final confirmed = await _showConfirmSheet(
      context,
      title: '清空收藏',
      message: '确定要清空全部追剧收藏吗？',
      confirmLabel: '清空',
    );
    if (!confirmed) return;
    await controller.clearAll();
  }

  Future<bool> _showConfirmSheet(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showAppModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => AppBottomSheetFrame(
        title: title,
        subtitle: '这个操作会立即更新本机收藏列表。',
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
}

class _FavoriteCard extends StatelessWidget {
  const _FavoriteCard({
    required this.item,
    required this.onTap,
    required this.onLongPress,
  });

  final FavoriteItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.vodPic?.trim() ?? '';
    final dpr = MediaQuery.of(context).devicePixelRatio;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imageUrl.isEmpty)
                    const _FavImagePlaceholder()
                  else
                    CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: (130 * dpr).round(),
                      useOldImageOnUrlChange: true,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      httpHeaders: const {
                        'User-Agent':
                            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
                      },
                      placeholder: (context, url) =>
                          const _FavImagePlaceholder(),
                      errorWidget: (context, url, error) =>
                          const _FavImagePlaceholder(),
                    ),
                  if (item.vodRemarks != null &&
                      item.vodRemarks!.trim().isNotEmpty)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          item.vodRemarks!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFFFE08A),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.vodName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: AppTokens.textPrimary,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              const Icon(
                Icons.video_library_rounded,
                size: 11,
                color: AppTokens.primaryBlue,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  item.sourceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTokens.textSecondary,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FavImagePlaceholder extends StatelessWidget {
  const _FavImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEEF1F6),
      alignment: Alignment.center,
      child: const Icon(
        Icons.movie_outlined,
        size: 30,
        color: AppTokens.textSecondary,
      ),
    );
  }
}

class _EmptyFavorites extends StatelessWidget {
  const _EmptyFavorites();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.favorite_border_rounded,
            size: 56,
            color: AppTokens.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          const Text(
            '还没有追剧收藏',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '在详情页点右上角 ♥ 即可加入追剧',
            style: TextStyle(fontSize: 12.5, color: AppTokens.textSecondary),
          ),
        ],
      ),
    );
  }
}
