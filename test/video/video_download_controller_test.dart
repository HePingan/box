import 'package:flutter_test/flutter_test.dart';

import 'package:box/video/controller/video_download_controller.dart';
import 'package:box/video/models/video_download_task.dart';
import 'package:box/video/services/video_download_gateway.dart';
import 'package:box/video/services/video_download_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('enqueue', () {
    test(
      'rejects non-HTTPS and retains a valid task in the repository',
      () async {
        final repository = _MemoryRepository();
        final gateway = _FakeGateway();
        final controller = VideoDownloadController(
          repository: repository,
          gateway: gateway,
        );

        await controller.load();
        expect(controller.tasks, isEmpty);

        await controller.enqueue(_task('http://unsafe.example/episode.mp4'));
        expect(controller.tasks, isEmpty);
        expect(controller.message, contains('仅支持 HTTPS'));

        await controller.enqueue(_task('https://media.example/episode.mp4'));
        expect(controller.tasks, hasLength(1));
        expect(gateway.enqueued, ['task-1']);
      },
    );
  });

  test(
    'platform snapshot preserves a paused task and exposes native download speed',
    () async {
      final repository = _MemoryRepository(
        initial: [_task('https://media.example/episode.mp4')],
      );
      final controller = VideoDownloadController(
        repository: repository,
        gateway: _FakeGateway(),
      );

      await controller.load();
      await controller.applyPlatformSnapshots([
        {
          'id': 'task-1',
          'status': 'paused',
          'downloadedBytes': 524288,
          'totalBytes': 1048576,
          'downloadSpeedBytesPerSecond': 131072,
          'localPath': '/safe/local/episode.mp4',
        },
      ]);

      final task = controller.tasks.single;
      expect(task.status, VideoDownloadStatus.paused);
      expect(task.downloadSpeedBytesPerSecond, 131072);
      expect(task.speedLabel, '128 KB/s');
    },
  );

  test('shows total video size and estimated remaining time from speed', () {
    final task = _task('https://media.example/episode.mp4').copyWith(
      downloadedBytes: 512 * 1024 * 1024,
      totalBytes: 1024 * 1024 * 1024,
      downloadSpeedBytesPerSecond: 2 * 1024 * 1024,
    );

    expect(task.sizeLabel, '512.0MB / 1.0GB');
    expect(task.remainingTimeLabel, '预计剩余 4分16s');
  });

  test(
    'platform progress turns a task into a locally playable completed task',
    () async {
      final repository = _MemoryRepository(
        initial: [_task('https://media.example/episode.mp4')],
      );
      final controller = VideoDownloadController(
        repository: repository,
        gateway: _FakeGateway(),
      );

      await controller.load();
      await controller.applyPlatformSnapshots([
        {
          'id': 'task-1',
          'status': 'completed',
          'downloadedBytes': 42,
          'totalBytes': 42,
          'localPath': '/safe/local/episode.mp4',
        },
      ]);

      expect(controller.tasks.single.status, VideoDownloadStatus.completed);
      expect(controller.tasks.single.isPlayableOffline, isTrue);
    },
  );
}

VideoDownloadTask _task(String url) => VideoDownloadTask(
  id: 'task-1',
  sourceId: 'source',
  vodId: '42',
  vodName: '示例剧',
  vodPic: '',
  sourceName: '线路',
  episodeName: '第1集',
  mediaUrl: url,
  createdAt: DateTime.utc(2026, 7, 25),
);

class _MemoryRepository implements VideoDownloadRepository {
  _MemoryRepository({List<VideoDownloadTask> initial = const []})
    : _tasks = List.of(initial);
  final List<VideoDownloadTask> _tasks;
  @override
  Future<void> delete(String id) async =>
      _tasks.removeWhere((item) => item.id == id);
  @override
  Future<List<VideoDownloadTask>> loadAll() async => List.of(_tasks);
  @override
  Future<void> save(VideoDownloadTask task) async {
    _tasks.removeWhere((item) => item.id == task.id);
    _tasks.add(task);
  }
}

class _FakeGateway implements VideoDownloadGateway {
  final List<String> enqueued = [];
  @override
  Future<void> cancel(String id) async {}
  @override
  Future<void> enqueue(VideoDownloadTask task) async => enqueued.add(task.id);
  @override
  Future<List<Map<String, dynamic>>> snapshots() async => [];
  @override
  Future<void> pause(String id) async {}
  @override
  Future<void> remove(String id) async {}
  @override
  Future<void> resume(String id) async {}
}
