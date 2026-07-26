import 'package:box/video/models/video_download_task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('platform metadata refresh keeps local task identity and updates labels', () {
    final task = VideoDownloadTask(
      id: 'task-1',
      sourceId: 'source-1',
      vodId: 'vod-1',
      vodName: '影片',
      vodPic: '',
      sourceName: '旧来源',
      episodeName: '旧剧集',
      mediaUrl: 'https://example.com/video.mp4',
      referer: '',
      createdAt: DateTime(2026),
    );

    final refreshed = task.copyWith(
      sourceName: '新来源',
      episodeName: '第01集',
      totalBytes: 1024,
    );

    expect(refreshed.id, 'task-1');
    expect(refreshed.sourceName, '新来源');
    expect(refreshed.episodeName, '第01集');
    expect(refreshed.totalBytes, 1024);
  });
}
