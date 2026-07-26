import '../models/video_download_task.dart';

/// Pure priority policy shared by the UI and platform bridge.
///
/// A task playing from the same source stays queued until normal downloads are
/// exhausted so current playback gets the network headroom first.
class VideoDownloadScheduler {
  const VideoDownloadScheduler({this.maxConcurrentTasks = 2})
    : assert(maxConcurrentTasks > 0);

  final int maxConcurrentTasks;

  List<String> nextTaskIds(Iterable<VideoDownloadTask> tasks) {
    final normal = <VideoDownloadTask>[];
    final lowPriority = <VideoDownloadTask>[];
    for (final task in tasks) {
      if (task.status != VideoDownloadStatus.queued) continue;
      (task.isPlaybackActive ? lowPriority : normal).add(task);
    }
    normal.sort(_byCreationThenId);
    lowPriority.sort(_byCreationThenId);
    return [...normal, ...lowPriority]
        .take(maxConcurrentTasks)
        .map((task) => task.id)
        .toList(growable: false);
  }

  static int _byCreationThenId(VideoDownloadTask a, VideoDownloadTask b) {
    final byTime = a.createdAt.compareTo(b.createdAt);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  }
}
