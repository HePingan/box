import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_bottom_sheet.dart';
import 'package:box/design_system/widgets/app_page_scaffold.dart';

import '../controller/history_controller.dart';
import '../controller/video_controller.dart';
import '../models/history_item.dart';
import '../models/video_source.dart';
import 'video_detail_page.dart';

/// 独立观看历史页：按日期分组、左滑删除单条、一键清空。
class WatchHistoryPage extends StatelessWidget {
  const WatchHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      child: Consumer<HistoryController>(
        builder: (context, controller, _) {
          final items = controller.historyList;
          final groups = _groupByDate(items);

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
                  child: _EmptyHistory(),
                )
              else
                for (final group in groups) ...[
                  SliverToBoxAdapter(
                    child: _buildDateHeader(group.label, group.items.length),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final item = group.items[index];
                      return _buildDismissibleRow(context, controller, item);
                    }, childCount: group.items.length),
                  ),
                ],
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
    HistoryController controller,
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
            '观看历史',
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
            TextButton.icon(
              onPressed: () => _confirmClear(context, controller),
              icon: const Icon(Icons.delete_sweep_rounded, size: 18),
              label: const Text('清空'),
              style: TextButton.styleFrom(
                foregroundColor: AppTokens.rose,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDateHeader(String label, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 15,
            decoration: BoxDecoration(
              color: AppTokens.primaryBlue,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppTokens.textPrimary,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDismissibleRow(
    BuildContext context,
    HistoryController controller,
    HistoryItem item,
  ) {
    return Dismissible(
      key: ValueKey(item.storageKey),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: AppTokens.rose,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.white, size: 22),
            SizedBox(width: 6),
            Text(
              '删除',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
      onDismissed: (_) => controller.deleteHistory(item),
      child: _HistoryRow(
        item: item,
        onTap: () => _openHistoryItem(context, item),
      ),
    );
  }

  void _openHistoryItem(BuildContext context, HistoryItem item) {
    final videoController = context.read<VideoController>();
    final targetSource = _findSourceById(videoController.sources, item.sourceId);

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

  Future<void> _confirmClear(
    BuildContext context,
    HistoryController controller,
  ) async {
    final confirmed = await showAppModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => AppBottomSheetFrame(
        title: '清空历史',
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
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: AppTokens.rose,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '确定要清空所有播放历史吗？',
                      style: TextStyle(
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
                    child: const Text('清空'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await controller.clearHistory();
    }
  }

  List<_HistoryGroup> _groupByDate(List<HistoryItem> items) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    final groups = <String, List<HistoryItem>>{};
    final order = <String>[];

    String labelFor(DateTime d) {
      final day = DateTime(d.year, d.month, d.day);
      if (day == today) return '今天';
      if (day == yesterday) return '昨天';
      if (day.isAfter(weekAgo)) return '本周';
      if (day.year == now.year) return '${d.month}月${d.day}日';
      return '${d.year}年${d.month}月${d.day}日';
    }

    for (final item in items) {
      final date = DateTime.fromMillisecondsSinceEpoch(item.updateTime);
      final label = labelFor(date);
      final bucket = groups.putIfAbsent(label, () {
        order.add(label);
        return <HistoryItem>[];
      });
      bucket.add(item);
    }

    return [
      for (final label in order) _HistoryGroup(label, groups[label]!),
    ];
  }
}

class _HistoryGroup {
  const _HistoryGroup(this.label, this.items);
  final String label;
  final List<HistoryItem> items;
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.item, required this.onTap});

  final HistoryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = (item.progressPercentage * 100).clamp(0, 100).toInt();
    final imageUrl = item.vodPic.trim();
    final dpr = MediaQuery.of(context).devicePixelRatio;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 76,
                    height: 100,
                    child: imageUrl.isEmpty
                        ? const _RowImagePlaceholder()
                        : CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: (76 * dpr).round(),
                            memCacheHeight: (100 * dpr).round(),
                            useOldImageOnUrlChange: true,
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            httpHeaders: const {
                              'User-Agent':
                                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
                            },
                            placeholder: (context, url) =>
                                const _RowImagePlaceholder(),
                            errorWidget: (context, url, error) =>
                                const _RowImagePlaceholder(),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.vodName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppTokens.textPrimary,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.episodeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppTokens.textSecondary,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.video_library_rounded,
                            size: 12,
                            color: AppTokens.primaryBlue,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              item.sourceName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppTokens.textSecondary,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: item.progressPercentage,
                                minHeight: 4,
                                backgroundColor: const Color(0xFFE7ECF5),
                                valueColor:
                                    const AlwaysStoppedAnimation<Color>(
                                      AppTokens.primaryBlue,
                                    ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$progress%',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RowImagePlaceholder extends StatelessWidget {
  const _RowImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEEF1F6),
      alignment: Alignment.center,
      child: const Icon(
        Icons.movie_outlined,
        size: 28,
        color: AppTokens.textSecondary,
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.history_rounded,
            size: 56,
            color: AppTokens.textSecondary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          const Text(
            '暂无观看历史',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
