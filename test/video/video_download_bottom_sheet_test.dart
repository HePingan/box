import 'dart:async';
import 'dart:io';

import 'package:box/video/controller/video_detail_controller.dart';
import 'package:box/video/models/video_source.dart';
import 'package:box/video/models/vod_item.dart';
import 'package:box/video/widgets/download/video_download_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final directory = await Directory.systemTemp.createTemp('box_download_sheet_test_');
    Hive.init(directory.path);
  });

  tearDownAll(() async {
    await Hive.close();
  });

  testWidgets('download episode sheet updates when detail finishes after opening',
      (tester) async {
    final detailCompleter = Completer<VodItem>();
    final detailController = VideoDetailController(
      source: const VideoSource(
        id: 'late-source',
        name: '延迟线路',
        url: 'https://api.example.test',
        detailUrl: 'https://referer.example.test',
      ),
      vodId: 2,
      detailFetcher: () => detailCompleter.future,
    );
    addTearDown(detailController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider.value(
          value: detailController,
          child: const Scaffold(body: VideoDownloadBottomSheet()),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    detailCompleter.complete(
      VodItem(
        vodId: 2,
        vodName: '延迟返回剧',
        vodPlayFrom: '延迟线路',
        vodPlayUrl: r'第1集$https://media.example.test/late-1.m3u8',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('第1集'), findsOneWidget);
  });

  testWidgets('download episode sheet reads detail state across modal route',
      (tester) async {
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
    addTearDown(detailController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider.value(
          value: detailController,
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => ChangeNotifierProvider<VideoDetailController>.value(
                      value: detailController,
                      child: const VideoDownloadBottomSheet(),
                    ),
                  ),
                  child: const Text('打开下载'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('打开下载'));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('第1集'), findsOneWidget);
  });
}
