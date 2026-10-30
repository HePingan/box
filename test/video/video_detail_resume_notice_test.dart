import 'dart:io';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/utils/app_logger.dart';
import 'package:box/video/controller/favorites_controller.dart';
import 'package:box/video/controller/history_controller.dart';
import 'package:box/video/controller/video_download_controller.dart';
import 'package:box/video/models/video_download_task.dart';
import 'package:box/video/models/video_source.dart';
import 'package:box/video/models/vod_item.dart';
import 'package:box/video/pages/video_detail_page.dart';
import 'package:box/video/services/video_download_gateway.dart';
import 'package:box/video/services/video_download_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

/// 续播提示**只说一遍**。
///
/// 真实现象（第六轮）：带着播放进度进详情页时，同一句
/// 「已为你恢复到上次播放位置：00:43」会同时出现在
///   ① 一个 SnackBar（2 秒后消失、盖住底部内容）
///   ② 选集卡顶部的黄色提示条（可关闭、不遮挡）
/// 两者读的是同一个 `resumeMessage`，内容一字不差。
///
/// 现在只保留 ②：更持久、可关闭、不挡内容。这条用例锁两件事：
///   1. 不再弹 SnackBar；
///   2. 提示条不会因为"被消费"而自己消失（3 秒后仍在）。
///
/// 跑法：直接 `flutter test test/video/video_detail_resume_notice_test.dart`。

class _NoopRepository implements VideoDownloadRepository {
  @override
  Future<List<VideoDownloadTask>> loadAll() async => const [];
  @override
  Future<void> save(VideoDownloadTask task) async {}
  @override
  Future<void> delete(String id) async {}
}

class _NoopGateway implements VideoDownloadGateway {
  @override
  Future<void> enqueue(VideoDownloadTask task) async {}
  @override
  Future<void> pause(String id) async {}
  @override
  Future<void> resume(String id) async {}
  @override
  Future<void> cancel(String id) async {}
  @override
  Future<void> remove(String id) async {}
  @override
  Future<List<Map<String, dynamic>>> snapshots() async => const [];
}

const _source = VideoSource(
  id: 'quantum',
  name: '量子资源',
  url: 'https://api.example.test',
  detailUrl: 'https://detail.example.test',
);

/// 24 集、单线路；第 1 集的地址就是"上次播到 43 秒"的那一集。
VodItem _detailWithResumableEpisode() {
  const dollar = r'$';
  final episodes = List.generate(
    24,
    (i) => '第${(i + 1).toString().padLeft(2, '0')}集$dollar'
        'https://media.example.test/${i + 1}.m3u8',
  ).join('#');
  return VodItem(
    vodId: 1,
    vodName: '初次爱你',
    vodRemarks: '更新至24集',
    vodPlayFrom: 'liangzi',
    vodPlayUrl: episodes,
  );
}

const _firstEpisodeUrl = 'https://media.example.test/1.m3u8';

void main() {
  Provider.debugCheckInvalidValueType = null;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('box_resume_notice_');
    Hive.init(dir.path);
  });

  tearDownAll(() async {
    await Hive.close();
  });

  testWidgets('续播提示只出现在卡内提示条，不弹 SnackBar，且不会自己消失', (tester) async {
    tester.view.physicalSize = const Size(392 * 3, 850 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    AppTokens.setDark(false);
    addTearDown(() => AppTokens.setDark(false));

    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => FavoritesController()),
            Provider<HistoryController>(create: (_) => HistoryController()),
            ChangeNotifierProvider(
              create: (_) => VideoDownloadController(
                repository: _NoopRepository(),
                gateway: _NoopGateway(),
              ),
            ),
          ],
          child: VideoDetailPage(
            source: _source,
            vodId: 1,
            // 上次就停在第 1 集的 43 秒 —— 与用户截图里的 00:43 同一个形状。
            initialEpisodeUrl: _firstEpisodeUrl,
            initialPosition: 43000,
            detailFetcher: () async => _detailWithResumableEpisode(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final resumeText = find.textContaining('恢复到上次播放位置');
    expect(resumeText, findsOneWidget, reason: '续播提示应当**只出现一次**');
    expect(
      find.byType(SnackBar),
      findsNothing,
      reason: '同一句话不该再用 SnackBar 说一遍（它会盖住底部并在 2 秒后消失）',
    );

    // 关键回归点：旧实现会在 listener 里 consumeResumeMessage()，
    // 提示条读的是同一个字段，于是"刚出现就被清掉"。
    await tester.pump(const Duration(seconds: 3));
    expect(
      find.textContaining('恢复到上次播放位置'),
      findsOneWidget,
      reason: '卡内提示条要留着，直到用户点关闭（不能被监听器顺手消费掉）',
    );

    await AppLogger.instance.flush();
    await tester.pump(const Duration(seconds: 1));
  });

  /// 用户点关闭后应当消失 —— 否则这条提示会一直占着卡片顶部。
  testWidgets('点关闭后提示条消失', (tester) async {
    tester.view.physicalSize = const Size(392 * 3, 850 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    AppTokens.setDark(false);
    addTearDown(() => AppTokens.setDark(false));

    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => FavoritesController()),
            Provider<HistoryController>(create: (_) => HistoryController()),
            ChangeNotifierProvider(
              create: (_) => VideoDownloadController(
                repository: _NoopRepository(),
                gateway: _NoopGateway(),
              ),
            ),
          ],
          child: VideoDetailPage(
            source: _source,
            vodId: 2,
            initialEpisodeUrl: _firstEpisodeUrl,
            initialPosition: 43000,
            detailFetcher: () async => _detailWithResumableEpisode(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('恢复到上次播放位置'), findsOneWidget);

    // 提示条右侧那个 × （Icons.close_rounded）
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.textContaining('恢复到上次播放位置'),
      findsNothing,
      reason: '点关闭后要真的消失（consumeResumeMessage 要生效）',
    );

    await AppLogger.instance.flush();
    await tester.pump(const Duration(seconds: 1));
  });
}
