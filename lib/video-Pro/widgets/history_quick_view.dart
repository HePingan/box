import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controller/history_controller.dart';
import '../models/history_item.dart';
import '../../video_module.dart';

class HistoryQuickView extends StatelessWidget {
  const HistoryQuickView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<HistoryController>(
      builder: (context, controller, _) {
        final items = controller.historyList;

        return Card(
          elevation: 0.5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '播放历史',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (items.isNotEmpty)
                      TextButton(
                        onPressed: () => _confirmClear(context, controller),
                        child: const Text('清空'),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        '暂无播放历史',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  )
                else
                  SizedBox(
                    height: 168,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return _HistoryCard(
                          item: item,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => VideoPlayerPage(
                                  url: item.episodeUrl,
                                  title: item.vodName,
                                  vodId: item.vodId,
                                  vodPic: item.vodPic,
                                  sourceId: item.sourceId,
                                  sourceName: item.sourceName,
                                  episodeName: item.episodeName,
                                  initialPosition: item.position,
                                ),
                              ),
                            );
                          },
                          onLongPress: () => _confirmDelete(context, controller, item),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmClear(BuildContext context, HistoryController controller) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('清空历史'),
          content: const Text('确定要清空所有播放历史吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await controller.clearHistory();
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  void _confirmDelete(
    BuildContext context,
    HistoryController controller,
    HistoryItem item,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('删除历史记录'),
          content: Text('确定删除「${item.vodName}」的观看记录吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await controller.deleteHistory(item.vodId);
              },
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final HistoryItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _HistoryCard({
    required this.item,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (item.progressPercentage * 100).clamp(0, 100).toInt();

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: 130,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      item.vodPic,
                      fit: BoxFit.cover,
                      headers: const {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'},
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey.shade300,
                        child: const Center(
                          child: Icon(Icons.movie_outlined, size: 30),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.72),
                            ],
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LinearProgressIndicator(
                              value: item.progressPercentage,
                              minHeight: 3,
                              backgroundColor: Colors.white.withOpacity(0.18),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).colorScheme.secondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$progress%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
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
            const SizedBox(height: 6),
            Text(
              item.vodName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.episodeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.sourceName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}