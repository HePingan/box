import 'dart:io';
import 'dart:ui' show ImageByteFormat;

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
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

/// 把**详情页顶部的真实渲染结果**抓成 PNG，并量出各块的实际高度。
///
/// 为什么要有这个文件：顶部重排（第五轮）是"照真机截图逐格量"才定下来的，
/// 改完必须能用同一把尺子复核 —— 否则就退回"读代码猜视觉效果"。
///
/// 它**不是** golden 断言（不比基准图），只做两件事：
///   1. 落盘 `build/visual/video_detail_top.png`，人眼可核；
///   2. 用 `AUDIT` 行打印头部 / 播放器 / 工具行 / Tab 的纵向位置，
///      让"顶部到底占了多少"变成数字而不是感觉（真机 392×850 的一屏）。
///
/// 跑法：DETAIL_TOP_CAPTURE=1 flutter test test/video/video_detail_top_capture_test.dart

const _captureKey = ValueKey('video-detail-top-capture');

/// 真机同量级的逻辑分辨率（截图那台是 420×933 一类的宽屏）。
const _phone = Size(392, 850);

class _NoopDownloadRepository implements VideoDownloadRepository {
  @override
  Future<List<VideoDownloadTask>> loadAll() async => const [];
  @override
  Future<void> save(VideoDownloadTask task) async {}
  @override
  Future<void> delete(String id) async {}
}

class _NoopDownloadGateway implements VideoDownloadGateway {
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

/// 与用户截图同一形状：24 集、两条线路（其中一条是技术名）。
VodItem _detailFixture() {
  // 片源的 play_url 用 `$` 分隔「集名 / 地址」、用 `$$` 分隔线路，
  // 这里用 raw 字符串拼，避免 Dart 的插值语法吃掉分隔符。
  const dollar = r'$';

  String joinEpisodes(int count) {
    final buffer = StringBuffer();
    for (var i = 1; i <= count; i++) {
      if (i > 1) buffer.write('#');
      final number = i.toString().padLeft(2, '0');
      buffer.write('第$number集$dollar'
          'https://media.example.test/$i.m3u8');
    }
    return buffer.toString();
  }

  final episodes = joinEpisodes(24);

  return VodItem(
    vodId: 1,
    vodName: '初次爱你',
    typeName: '国产剧',
    vodRemarks: '更新至24集',
    vodYear: '2024',
    vodArea: '中国大陆',
    vodLang: '汉语普通话',
    vodDirector: '张三',
    vodActor: '李四,王五',
    vodContent: '剧情简介第一段。\n剧情简介第二段。',
    // 线路之间用 `$$$` 分隔（见 vod_item_play_parser 的兼容格式说明），
    // 线路内的「集名 / 地址」用单个 `$`。
    vodPlayFrom: 'liangzi${dollar * 3}lzm3u8',
    vodPlayUrl: '$episodes${dollar * 3}$episodes',
  );
}

void main() {
  // 线上注册的就是 `Provider<HistoryController>`（见 lib/app/app_providers.dart），
  // 这里为保持一致也用 Provider —— 而 provider 会对"用 Provider 包 Listenable"
  // 抛断言。关掉这一项检查（它只针对开发期误用，不影响行为）。
  Provider.debugCheckInvalidValueType = null;

  String? cjk;

  setUpAll(() async {
    for (final path in const [
      '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc',
      '/usr/share/fonts/google-noto-cjk/NotoSansCJK-Regular.ttc',
      '/usr/share/fonts/google-droid/DroidSansFallback.ttf',
    ]) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final loader = FontLoader('WenQuanYi')
        ..addFont(Future.value(file.readAsBytesSync().buffer.asByteData()));
      await loader.load();
      cjk = 'WenQuanYi';
      break;
    }
    // 详情页里的收藏 / 线路记忆都落在 Hive；不初始化会在抓图时抛
    // "Hive not initialized"。用临时目录，不碰真实数据。
    final hiveDir = await Directory.systemTemp.createTemp('box_detail_top_');
    Hive.init(hiveDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
  });

  for (final dark in <bool>[false, true]) {
    testWidgets(
      '抓详情页顶部并量各区块纵向占用（${dark ? '深色' : '浅色'}）',
      (tester) async {
        tester.view.physicalSize = Size(_phone.width * 3, _phone.height * 3);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);

        // 深浅两档都要能截：新头部全部走 AppTokens 取值，写死浅色会在深色档
        // 出现"浅字压白卡"。用 AppTokens.setDark 切（与线上 AppThemeController 同款）。
        AppTokens.setDark(dark);
        addTearDown(() => AppTokens.setDark(false));

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: cjk),
            home: RepaintBoundary(
              key: _captureKey,
              child: MultiProvider(
                providers: [
                  ChangeNotifierProvider(create: (_) => FavoritesController()),
                  // 线上就注册的是 `Provider<HistoryController>`（见 app_providers），
                  // 这里必须同款：换成 ChangeNotifierProvider 反而会跟线上不一致。
                  // provider 的类型检查断言会因此报错，关掉即可。
                  Provider<HistoryController>(
                    create: (_) => HistoryController(),
                  ),
                  ChangeNotifierProvider(
                    create: (_) => VideoDownloadController(
                      repository: _NoopDownloadRepository(),
                      gateway: _NoopDownloadGateway(),
                    ),
                  ),
                ],
                child: VideoDetailPage(
                  source: _source,
                  vodId: 1,
                  detailFetcher: () async => _detailFixture(),
                ),
              ),
            ),
          ),
        );

        // 详情拿到之后播放器会去连真实 m3u8（这里必然失败），所以不用
        // pumpAndSettle：它会一直等那个 12s 超时。给几帧让布局稳定即可。
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        final screenH = _phone.height;
        stdout.writeln('AUDIT screen_height=$screenH');

        void report(String label, Finder finder) {
          if (finder.evaluate().isEmpty) {
            stdout.writeln('AUDIT block="$label" rendered=NO');
            return;
          }
          final r = tester.getRect(finder.first);
          stdout.writeln(
            'AUDIT block="$label" top=${r.top.toStringAsFixed(1)} '
            'height=${r.height.toStringAsFixed(1)} bottom=${r.bottom.toStringAsFixed(1)}',
          );
        }

        report('片名', find.text('初次爱你'));
        report('副标题', find.textContaining('量子资源 · '));
        report('收起播放器', find.text('收起播放器'));
        report('线路标签', find.text('线路'));
        report('选集Tab', find.text('选集'));

        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(_captureKey),
        );
        final bytes = await tester.binding.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 3.0);
          final data = await image.toByteData(format: ImageByteFormat.png);
          return data!.buffer.asUint8List();
        });
        expect(bytes, isNotNull);

        final out = File(
          'build/visual/video_detail_top_${dark ? 'dark' : 'light'}.png',
        );
        out.parent.createSync(recursive: true);
        out.writeAsBytesSync(bytes!);
        stdout.writeln('DETAIL_PNG=${out.absolute.path} bytes=${out.lengthSync()}');

        // ── 第五轮（顶部重排）的版面断言 ──
        //
        // 这些是"改完到底有没有变"的硬证据，不是审美判断：
        //   ① 副标题带上了集数，而不是只有一个孤零零的片源名；
        //   ② 线路与「收起播放器」在**同一行**（纵向中心几乎相同），
        //      顶部因此少了一整行 —— 这是本轮最直接的收益；
        //   ③ 「收起播放器」不再独占一行：它和播放器底边之间只有一个
        //      spaceSm 级别的间距（8dp），而不是原先的 6 + 40dp 按钮高度。
        expect(
          find.textContaining('量子资源 · 全 24 集'),
          findsOneWidget,
          reason: '副标题应是「片源 · 全 N 集」，单片/无集数时才只写片源',
        );

        final lineLabel = tester.getRect(find.text('线路'));
        final collapseLabel = tester.getRect(find.text('收起播放器'));
        expect(
          (lineLabel.center.dy - collapseLabel.center.dy).abs(),
          lessThan(2),
          reason: '线路与收起播放器必须在同一行（同一纵向中心），否则就是又拆回两行',
        );

        final playerRect = tester.getRect(find.byType(AspectRatio).first);
        // 从播放器底边到「收起播放器」文字顶边只该是：外壳 4dp 内边距 +
        // 工具行 8dp 间距 + 行内 32dp 高度里文字的垂直居中余量（约 9dp）。
        // 原先是一个独立的 TextButton 行（6 + 40 + 上下留白），实测差 40dp 以上。
        expect(
          collapseLabel.top - playerRect.bottom,
          lessThan(24),
          reason: '收起入口要紧贴播放器下沿，不能像原来那样隔出一整行空白',
        );

        // 头部信息卡整体高度：重排前约 118dp（两行 + 46dp 方块行），
        // 现在应是紧凑的两行式，不该再涨回去。
        final headerCard = tester.getRect(
          find.byKey(const ValueKey<String>('video-detail-header')),
        );
        stdout.writeln(
          'AUDIT block="头部卡" top=${headerCard.top.toStringAsFixed(1)} '
          'height=${headerCard.height.toStringAsFixed(1)}',
        );
        expect(
          headerCard.height,
          lessThan(110),
          reason: '头部卡收紧后不该再回到 110dp 以上（那是四个 46dp 方块的行高）',
        );

        // 播放器顶部：头部卡底边 + 8dp 间距 + 播放器外壳 4dp 内边距 = 12dp。
        // 这一条锁的是"中间不许再多出无来由的空隙"（原先这里还夹着一段留白）。
        expect(
          playerRect.top - headerCard.bottom,
          lessThan(14),
          reason: '播放器要贴着头部卡（只留 spaceSm + 外壳内边距）',
        );

        // 详情加载会写日志，AppLogger 用一个 250ms 的防抖定时器落盘；
        // 测试结束时它还挂着，会被判 "Timer is still pending"。主动冲掉。
        await AppLogger.instance.flush();
        await tester.pump(const Duration(seconds: 1));
      },
      skip: Platform.environment['DETAIL_TOP_CAPTURE'] != '1',
    );
  }

  /// 边界：单片（只有一集）时，副标题不该出现「全 1 集」这种废话，
  /// 而应显示画质备注（`HD中字`）。
  ///
  /// 这条不用抓图，只看文字；它挡的是「按集数算副标题」时最常见的写法错误
  /// （把 `count > 1` 的判断漏掉）。
  testWidgets('单片时副标题是「片源 · 备注」，不写「全 1 集」', (tester) async {
    tester.view.physicalSize = Size(_phone.width * 3, _phone.height * 3);
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
            Provider<HistoryController>(create: (_) => HistoryController()),
            ChangeNotifierProvider(
              create: (_) => VideoDownloadController(
                repository: _NoopDownloadRepository(),
                gateway: _NoopDownloadGateway(),
              ),
            ),
          ],
          child: VideoDetailPage(
            source: _source,
            vodId: 2,
            detailFetcher: () async => VodItem(
              vodId: 2,
              vodName: '单集片',
              vodRemarks: 'HD中字',
              vodPlayFrom: 'liangzi',
              vodPlayUrl: '正片\$https://media.example.test/only.m3u8',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('全 1 集'), findsNothing,
        reason: '只有一集时写「全 1 集」是废话');
    expect(find.textContaining('量子资源 · HD中字'), findsOneWidget,
        reason: '单片时副标题应退化为「片源 · 画质备注」');

    await AppLogger.instance.flush();
    await tester.pump(const Duration(seconds: 1));
  });
}
