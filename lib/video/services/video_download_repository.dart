import '../models/video_download_task.dart';

abstract interface class VideoDownloadRepository {
  Future<List<VideoDownloadTask>> loadAll();
  Future<void> save(VideoDownloadTask task);
  Future<void> delete(String id);
}
