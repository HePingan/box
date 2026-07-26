import 'dart:io';

import 'package:box/video/controller/video_detail_controller.dart';
import 'package:box/video/models/video_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final directory = await Directory.systemTemp.createTemp('box_offline_detail_test_');
    Hive.init(directory.path);
  });

  tearDownAll(() async {
    await Hive.close();
  });

  test('offline playback does not request remote detail and creates local detail state',
      () async {
    var fetchCount = 0;
    final controller = VideoDetailController(
      source: const VideoSource(
        id: 'source-1',
        name: '原始线路',
        url: 'https://api.example.test',
        detailUrl: 'https://detail.example.test',
      ),
      vodId: 42,
      localPath: '/safe/files/episode-01.mp4',
      isOfflinePlayback: true,
      episodeName: '第01集',
      detailFetcher: () async {
        fetchCount++;
        return null;
      },
    );
    addTearDown(controller.dispose);

    await Future<void>.delayed(Duration.zero);

    expect(fetchCount, 0);
    expect(controller.isLoading, isFalse);
    expect(controller.errorMessage, isNull);
    expect(controller.currentLocalPath, '/safe/files/episode-01.mp4');
    expect(controller.currentEpisodeName, '第01集');
    expect(controller.fullDetail?.vodName, '第01集');
  });
}
