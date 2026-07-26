import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/video_download_task.dart';
import '../models/video_source.dart';
import '../controller/video_download_controller.dart';
import '../pages/video_detail_page.dart';
import '../../design_system/app_tokens.dart';

class VideoDownloadsPage extends StatelessWidget {
  const VideoDownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.background,
      appBar: AppBar(
        backgroundColor: AppTokens.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: AppTokens.textPrimary,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          '下载管理',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: AppTokens.textPrimary,
          ),
        ),
        actions: [
          Consumer<VideoDownloadController>(
            builder: (context, controller, _) {
              final hasCompleted = controller.tasks.any(
                (t) => t.status == VideoDownloadStatus.completed,
              );
              if (!hasCompleted) return const SizedBox.shrink();
              return TextButton(
                onPressed: () async {
                  final toRemove = controller.tasks
                      .where((t) => t.status == VideoDownloadStatus.completed)
                      .map((t) => t.id)
                      .toList();
                  for (final id in toRemove) {
                    await controller.remove(id);
                  }
                },
                child: const Text(
                  '清空已完成',
                  style: TextStyle(color: Color(0xFFEF4444), fontSize: 13),
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<VideoDownloadController>(
        builder: (context, controller, _) {
          final tasks = controller.tasks;
          final downloading = tasks
              .where(
                (t) =>
                    t.status == VideoDownloadStatus.downloading ||
                    t.status == VideoDownloadStatus.queued,
              )
              .toList();
          final completed = tasks
              .where((t) => t.status == VideoDownloadStatus.completed)
              .toList();
          final failed = tasks
              .where((t) => t.status == VideoDownloadStatus.failed)
              .toList();
          final paused = tasks
              .where((t) => t.status == VideoDownloadStatus.paused)
              .toList();

          return CustomScrollView(
            slivers: [
              if (downloading.isEmpty &&
                  paused.isEmpty &&
                  completed.isEmpty &&
                  failed.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      '暂无下载任务',
                      style: TextStyle(color: Color(0xFF94A3B8)),
                    ),
                  ),
                )
              else ...[
                _group('下载中', downloading, controller),
                _group('已暂停', paused, controller),
                _group('已完成', completed, controller),
                _group('失败', failed, controller),
              ],
            ],
          );
        },
      ),
    );
  }

  /// 播放已下载的视频 — 跳转到视频详情页并标记为离线播放。
  void _playDownloadedVideo(BuildContext context, VideoDownloadTask task) {
    // 创建 VideoSource 对象（使用 sourceId 作为名称）
    final source = VideoSource(
      id: task.sourceId,
      name: task.sourceName.trim().isEmpty ? task.sourceId : task.sourceName,
      url: '',
      detailUrl: '',
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoDetailPage(
          source: source,
          vodId: int.tryParse(task.vodId) ?? 0,
          localPath: task.localPath,
          isOfflinePlayback: true,
          episodeName: task.episodeName,
          localFileExpectedBytes: task.totalBytes,
        ),
      ),
    );
  }

  Widget _group(
    String title,
    List<VideoDownloadTask> items,
    VideoDownloadController controller,
  ) {
    if (items.isEmpty) return const SliverToBoxAdapter();
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _taskCard(context, items[index], controller),
          childCount: items.length,
        ),
      ),
    );
  }

  Widget _taskCard(
    BuildContext context,
    VideoDownloadTask task,
    VideoDownloadController controller,
  ) {
    final isDownloading =
        task.status == VideoDownloadStatus.downloading ||
        task.status == VideoDownloadStatus.queued;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7ECF5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.episodeName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTokens.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                if (isDownloading || task.status == VideoDownloadStatus.paused)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isDownloading &&
                                task.status == VideoDownloadStatus.queued
                            ? '排队中…'
                            : '${(task.downloadPercent * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: task.status == VideoDownloadStatus.paused
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF3B82F6),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        task.status == VideoDownloadStatus.paused
                            ? task.sizeLabel
                            : '${task.sizeLabel} · ${task.speedLabel}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                if (isDownloading && task.status != VideoDownloadStatus.queued)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      task.remainingTimeLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTokens.textSecondary,
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                if (isDownloading)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: task.status == VideoDownloadStatus.queued
                          ? null
                          : task.downloadPercent,
                      minHeight: 4,
                      color: const Color(0xFF3B82F6),
                      backgroundColor: const Color(0xFFF1F5F9),
                    ),
                  )
                else if (task.status == VideoDownloadStatus.paused)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: task.downloadPercent,
                      minHeight: 4,
                      color: const Color(0xFFF59E0B),
                      backgroundColor: const Color(0xFFF1F5F9),
                    ),
                  )
                else if (task.status == VideoDownloadStatus.failed)
                  Text(
                    task.errorMessage,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFEF4444),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isDownloading)
                TextButton(
                  onPressed: () => controller.pause(task.id),
                  child: const Text('暂停'),
                )
              else if (task.status == VideoDownloadStatus.paused ||
                  task.status == VideoDownloadStatus.failed)
                TextButton(
                  onPressed: () => controller.resume(task.id),
                  child: const Text('继续'),
                )
              else if (task.status == VideoDownloadStatus.completed)
                IconButton(
                  icon: const Icon(Icons.play_circle_filled_rounded, size: 28),
                  color: const Color(0xFF3B82F6),
                  onPressed: () => _playDownloadedVideo(context, task),
                  tooltip: '播放',
                )
              else if (task.status == VideoDownloadStatus.failed)
                TextButton(
                  onPressed: () => controller.resume(task.id),
                  child: const Text('重试'),
                ),
              TextButton(
                onPressed: () => controller.remove(task.id),
                child: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
