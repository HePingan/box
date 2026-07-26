import 'package:hive/hive.dart';

import '../models/video_download_task.dart';
import 'video_download_repository.dart';

class HiveVideoDownloadRepository implements VideoDownloadRepository {
  static const String _boxName = 'video_download_tasks_v1';
  Box<dynamic>? _box;

  Future<Box<dynamic>> _ensureBox() async {
    if (_box?.isOpen == true) return _box!;
    _box = await Hive.openBox<dynamic>(_boxName);
    return _box!;
  }

  @override
  Future<void> delete(String id) async => (await _ensureBox()).delete(id);

  @override
  Future<List<VideoDownloadTask>> loadAll() async {
    final box = await _ensureBox();
    final tasks = <VideoDownloadTask>[];
    for (final value in box.values) {
      if (value is! Map) continue;
      try {
        final task = VideoDownloadTask.fromMap(Map<dynamic, dynamic>.from(value));
        if (task.id.isNotEmpty && task.mediaUrl.isNotEmpty) tasks.add(task);
      } catch (_) {}
    }
    tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return tasks;
  }

  @override
  Future<void> save(VideoDownloadTask task) async {
    await (await _ensureBox()).put(task.id, task.toMap());
  }
}
