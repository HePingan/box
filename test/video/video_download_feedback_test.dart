import 'dart:io';

import 'package:box/video/controller/video_detail_controller.dart';
import 'package:box/video/controller/video_download_controller.dart';
import 'package:box/video/models/video_download_task.dart';
import 'package:box/video/models/video_source.dart';
import 'package:box/video/models/vod_item.dart';
import 'package:box/video/pages/video_downloads_page.dart';
import 'package:box/video/services/video_download_gateway.dart';
import 'package:box/video/services/video_download_repository.dart';
import 'package:box/video/widgets/download/video_download_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

class _FakeDownloadRepository implements VideoDownloadRepository {
  final Map<String, VideoDownloadTask> _tasks = {};

  @override
  Future<void> delete(String id) async => _tasks.remove(id);

  @override
  Future<List<VideoDownloadTask>> loadAll() async => _tasks.values.toList();

  @override
  Future<void> save(VideoDownloadTask task) async => _tasks[task.id] = task;
}

class _FakeDownloadGateway implements VideoDownloadGateway {
  final List<VideoDownloadTask> enqueued = [];

  @override
  Future<void> cancel(String id) async {}

  @override
  Future<void> enqueue(VideoDownloadTask task) async => enqueued.add(task);

  @override
  Future<void> pause(String id) async {}

  @override
  Future<void> remove(String id) async {}

  @override
  Future<void> resume(String id) async {}

  @override
  Future<List<Map<String, dynamic>>> snapshots() async => const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final directory = await Directory.systemTemp.createTemp(
      'box_download_feedback_test_',
    );
    Hive.init(directory.path);
  });

  tearDownAll(() async => Hive.close());

  testWidgets('confirms queued download before closing the episode sheet', (
    tester,
  ) async {
    final detailController = VideoDetailController(
      source: const VideoSource(
        id: 'source',
        name: '测试线路',
        url: 'https://api.example.test',
        detailUrl: 'https://referer.example.test',
      ),
      vodId: 1,
      detailFetcher: () async => VodItem(
        vodId: 1,
        vodName: '测试剧',
        vodPlayFrom: '测试线路',
        vodPlayUrl: '第1集\$https://media.example.test/1.m3u8',
      ),
    );
    final gateway = _FakeDownloadGateway();
    final downloadController = VideoDownloadController(
      repository: _FakeDownloadRepository(),
      gateway: gateway,
    );
    addTearDown(detailController.dispose);
    addTearDown(downloadController.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: detailController),
          ChangeNotifierProvider.value(value: downloadController),
        ],
        child: const MaterialApp(
          home: Scaffold(body: VideoDownloadBottomSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('第1集'));
    await tester.pump();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    // The bottom sheet pops itself and pushes VideoDownloadsPage.
    // The download controller starts a 1-second poll timer; pump once to
    // let the navigation settle but don't wait for the periodic timer.
    await tester.pump(const Duration(milliseconds: 500));

    expect(gateway.enqueued, hasLength(1));
    expect(find.byType(VideoDownloadsPage), findsOneWidget);
  });
}
