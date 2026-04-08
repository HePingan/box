import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controller/history_controller.dart';
import '../controller/video_controller.dart'; // [新增] 用于查找原始源
import '../models/history_item.dart';
import '../models/video_source.dart';
import '../pages/video_detail_page.dart';     // [新增] 用于跳回详情页刷新直链

class HistoryQuickView extends StatelessWidget {
  const HistoryQuickView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<HistoryController>(
      builder: (context, controller, _) {
        final items = controller.historyList;

        return Card(
          elevation: 0.5,
          color: Colors.white,
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
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text('清空', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
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
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ),
                  )
                else
                  // 🔥 修复一：将高度从 168 提高到 200，留出足够的空间显示底部三行文字
                  SizedBox(
                    height: 200, 
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return _HistoryCard(
                          item: item,
                          onTap: () {
                            // 🔥 修复二：绝不能拿旧的 m3u8 跳转播放！必须跳回详情页查新配置！
                            final videoController = context.read<VideoController>();
                            VideoSource? targetSource;
                            
                            try {
                              // 从全部配置源中匹配这个历史记录对应的原始源
                              targetSource = videoController.sources.firstWhere((s) => s.id == item.sourceId);
                            } catch (_) {}

                            if (targetSource == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('该视频的片源已失效或被移除')),
                              );
                              return;
                            }

                            // 带着正确的源和 vodId 前往详情页，触发底层 _loadDetail 拿到带有新鲜防盗链Token的直链
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => VideoDetailPage(
                                  source: targetSource!,
                                  vodId: int.tryParse(item.vodId) ?? 0,
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
          title: const Text('清空历史', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: const Text('确定要清空所有播放历史吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await controller.clearHistory();
              },
              child: const Text('确定', style: TextStyle(color: Colors.redAccent)),
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
          title: const Text('删除记录', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: Text('确定删除「${item.vodName}」的观看记录吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await controller.deleteHistory(item.vodId);
              },
              child: const Text('删除', style: TextStyle(color: Colors.redAccent)),
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
        width: 110, // 设定确切的宽度
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔥 修复一关键：放弃 AspectRatio 强制占用高度，换成 Expanded 让海报自适应剩余空间！
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      item.vodPic,
                      fit: BoxFit.cover,
                      headers: const {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'},
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey.shade100,
                        child: const Center(
                          child: Icon(Icons.movie_outlined, size: 32, color: Colors.grey),
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
                              Colors.black.withOpacity(0.85),
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
                              minHeight: 2.5, // 让进度条精致一点
                              backgroundColor: Colors.white.withOpacity(0.15),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).colorScheme.primary,
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
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.black87,
                height: 1.2
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
                height: 1.2
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.video_library_rounded, size: 10, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    item.sourceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                      height: 1.2
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