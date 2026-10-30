import 'dart:io';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/utils/app_logger.dart';
import 'package:box/video/controller/favorites_controller.dart';
import 'package:box/video/controller/history_controller.dart';
import 'package:box/video/controller/video_download_controller.dart';
import 'package:box/video/models/history_item.dart';
import 'package:box/video/models/video_download_task.dart';
import 'package:box/video/models/video_source.dart';
import 'package:box/video/models/vod_item.dart';
import 'package:box/video/pages/video_detail_page.dart';
import 'package:box/video/services/video_download_gateway.dart';
import 'package:box/video/services/video_download_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

/// 「看过」标记的**接线**护栏。
///
/// 判定逻辑本身在 `watched_episodes_test.dart`（纯函数 14 条）；
/// 这里只验界面真的用了它：历史里有第 1-8 集 → 格子上出现 8 个标记，
/// 且**当前集不重复标**（当前集优先，只保留橙色描边一种强调）。
///
/// 为什么必须有这条：`_EpisodeCell` 是私有组件、`watchedKeys` 是
/// 逐层传下去的，任何一层漏传都会静默退化成"永远没有标记"，
/// 而纯函数用例仍然全绿。

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

/// 直接给出固定的历史（不碰 Hive，避免用例依赖真实存储）。
class _SeededHistory extends HistoryController {
  _SeededHistory(this._items);
  final List<HistoryItem> _items;
  @override
  List<HistoryItem> get historyList => List.unmodifiable(_items);
}

const _source = VideoSource(
  id: 'quantum',
  name: '量子资源',
  url: 'https://api.example.test',
  detailUrl: 'https://detail.example.test',
);

String _episodeUrl(int oneBased) =>
    'https://media.example.test/$oneBased.m3u8';

VodItem _detail() {
  const dollar = r'$';
  final episodes = List.generate(
    24,
    (i) => '第${(i + 1).toString().padLeft(2, '0')}集$dollar${_episodeUrl(i + 1)}',
  ).join('#');
  return VodItem(
    vodId: 1,
    vodName: '初次爱你',
    vodRemarks: '更新至24集',
    vodPlayFrom: 'liangzi',
    vodPlayUrl: episodes,
  );
}

HistoryItem _watched(int oneBased, {int position = 300000}) => HistoryItem(
  vodId: '1',
  vodName: '初次爱你',
  vodPic: '',
  sourceId: 'quantum',
  sourceName: '量子资源',
  episodeName: '第${oneBased.toString().padLeft(2, '0')}集',
  episodeUrl: _episodeUrl(oneBased),
  position: position,
  duration: 2700000,
  updateTime: oneBased,
);

/// 界面上"看过"标记的呈现：那颗 4dp 的小圆点（`BoxShape.circle` +
/// `success` 色）。数它就是为了数"标记了几个格子"。
int countWatchedDots(WidgetTester tester) {
  return tester.widgetList<Container>(find.byType(Container)).where((c) {
    final deco = c.decoration;
    if (deco is! BoxDecoration) return false;
    if (deco.shape != BoxShape.circle) return false;
    final size = c.constraints;
    return size?.maxWidth == 4;
  }).length;
}

Future<void> pumpDetail(
  WidgetTester tester, {
  required List<HistoryItem> history,
  required String? cjk,
  String? initialEpisodeUrl,
  int initialPosition = 0,
}) async {
  tester.view.physicalSize = const Size(392 * 3, 850 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  AppTokens.setDark(false);
  addTearDown(() => AppTokens.setDark(false));

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: cjk),
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => FavoritesController()),
          Provider<HistoryController>.value(value: _SeededHistory(history)),
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
          initialEpisodeUrl: initialEpisodeUrl,
          initialPosition: initialPosition,
          detailFetcher: () async => _detail(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  Provider.debugCheckInvalidValueType = null;
  String? cjk;

  setUpAll(() async {
    final file = File(
      '/usr/share/fonts/google-noto-cjk/NotoSansCJK-Regular.ttc',
    );
    if (file.existsSync()) {
      final loader = FontLoader('WenQuanYi')
        ..addFont(Future.value(file.readAsBytesSync().buffer.asByteData()));
      await loader.load();
      cjk = 'WenQuanYi';
    }
    final dir = await Directory.systemTemp.createTemp('box_watched_marker_');
    Hive.init(dir.path);
  });

  tearDownAll(() async {
    await Hive.close();
  });

  testWidgets('历史里看过 8 集 → 网格上出现对应标记（当前集让位给橙色描边）', (tester) async {
    await pumpDetail(
      tester,
      cjk: cjk,
      history: [for (var i = 1; i <= 8; i++) _watched(i)],
    );

    // 看过 8 集，但第 1 集同时是当前集（默认选中第 1 集），
    // 当前集优先 → 绿点只出现在另外 7 集上。
    expect(
      countWatchedDots(tester),
      7,
      reason: '8 条已看历史里，当前集不重复标；数量不对说明 watchedKeys 没传到位',
    );

    await AppLogger.instance.flush();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('当前集不重复标记（当前集优先，只保留橙色描边）', (tester) async {
    // 第 1 集同时是"当前集"和"看过"，标记应当让位给当前集样式。
    await pumpDetail(
      tester,
      cjk: cjk,
      history: [for (var i = 1; i <= 8; i++) _watched(i)],
    );

    // 8 条历史里第 1 集是当前集 → 只应剩 7 个点。
    expect(
      countWatchedDots(tester),
      7,
      reason: '当前集已经有橙色描边，再叠一个绿点就成了双强调',
    );

    await AppLogger.instance.flush();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('只点进去看一眼（进度 < 1 分钟）不标', (tester) async {
    await pumpDetail(
      tester,
      cjk: cjk,
      history: [for (var i = 1; i <= 8; i++) _watched(i, position: 2000)],
    );

    expect(
      countWatchedDots(tester),
      0,
      reason: '播放器一初始化就会落记录，门槛太低等于全标，标记就没有信息量',
    );

    await AppLogger.instance.flush();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('没有历史时不出现任何标记', (tester) async {
    await pumpDetail(tester, cjk: cjk, history: const []);

    expect(countWatchedDots(tester), 0);
    expect(find.text('01'), findsOneWidget, reason: '网格本身要正常渲染');

    await AppLogger.instance.flush();
    await tester.pump(const Duration(seconds: 1));
  });
}
