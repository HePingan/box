import 'dart:async';

import 'package:box/features/admin/presentation/widgets/video_source_tab.dart';
import 'package:box/video-Pro/controller/video_catalog_repository.dart';
import 'package:box/video-Pro/models/video_category.dart';
import 'package:box/video_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

class _VideoRepository extends VideoCatalogRepository {
  _VideoRepository({this.emptySources = false});

  final bool emptySources;
  int loadSourcesCalls = 0;

  @override
  Future<List<VideoSource>> loadSources(String catalogUrl) async {
    if (emptySources) return const [];
    return const [
      VideoSource(
        id: 'source-1',
        name: '测试片源',
        url: 'https://source.example/api.php/provide/vod/',
        detailUrl: 'https://source.example',
      ),
    ];
  }

  @override
  Future<List<VideoCategory>> loadCategories(VideoSource source) async =>
      const [];

  @override
  Future<List<VodItem>> loadVideos(
    VideoSource source, {
    required int? typeId,
    required int page,
  }) async {
    return const [];
  }
}

void main() {
  Widget buildApp({
    required VideoController controller,
    required http.Client client,
  }) {
    return MaterialApp(
      home: ChangeNotifierProvider<VideoController>.value(
        value: controller,
        child: Scaffold(
          body: VideoSourceTab(
            httpClient: client,
            resolveCatalogUrl: () async =>
                'https://catalog.example/sources.json',
          ),
        ),
      ),
    );
  }

  Future<void> loadSource(WidgetTester tester) async {
    await tester.tap(find.text('刷新'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('connectivity test marks non-2xx responses as unreachable', (
    tester,
  ) async {
    final controller = VideoController(repository: _VideoRepository());
    final client = MockClient((_) async => http.Response('missing', 404));
    addTearDown(() {
      client.close();
      controller.dispose();
    });

    await tester.pumpWidget(buildApp(controller: controller, client: client));
    await loadSource(tester);
    await tester.tap(find.text('测试片源'));
    await tester.pump();
    await tester.tap(find.text('测试连通性'));
    await tester.pump();

    expect(find.textContaining('不可达（HTTP 404）'), findsOneWidget);
    expect(find.textContaining('404 ('), findsNothing);
  });

  testWidgets('connectivity test shows a concise normalized transport error', (
    tester,
  ) async {
    final controller = VideoController(repository: _VideoRepository());
    final client = MockClient(
      (_) async => throw TimeoutException('internal endpoint details'),
    );
    addTearDown(() {
      client.close();
      controller.dispose();
    });

    await tester.pumpWidget(buildApp(controller: controller, client: client));
    await loadSource(tester);
    await tester.tap(find.text('测试片源'));
    await tester.pump();
    await tester.tap(find.text('测试连通性'));
    await tester.pump();

    expect(find.textContaining('不可达（连接超时）'), findsOneWidget);
    expect(find.textContaining('internal endpoint details'), findsNothing);
  });

  testWidgets(
    'refresh shows failure feedback instead of success when loading fails',
    (tester) async {
      final controller = VideoController(
        repository: _VideoRepository(emptySources: true),
      );
      final client = MockClient((_) async => http.Response('', 200));
      addTearDown(() {
        client.close();
        controller.dispose();
      });

      await tester.pumpWidget(buildApp(controller: controller, client: client));
      await tester.tap(find.text('刷新'));
      await tester.pumpAndSettle();

      expect(find.textContaining('刷新失败'), findsOneWidget);
      expect(find.text('刷新完成'), findsNothing);
    },
  );
}
