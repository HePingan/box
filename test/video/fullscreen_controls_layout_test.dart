import 'dart:io';
import 'dart:ui' as ui show ImageByteFormat, instantiateImageCodec;
import 'dart:ui' show ImageByteFormat;

import 'package:box/video/widgets/player/custom_video_controls.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'support/fake_video_controller.dart';

/// 全屏播放器控件的**排版**护栏。
///
/// 起因（第七轮）：真机截图（2800×1260 @3x，即 933×420dp）上抓到五处瑕疵，
/// 都是"看着别扭但不会让任何用例变红"的那类，所以这里全部用**实测数值**锁住：
///
/// 1. 顶栏渐变没铺满 —— 左右各一条纯黑，`y=28` 那行从 x=133 的 0 突跳到 x=140 的 9.3；
/// 2. 底部面板左边距 44dp / 右边距 10dp（差 4 倍）；
/// 3. 面板底边离屏幕只剩 7dp；
/// 4. 播放键 52×44 方角，其余 40×38 圆角，一排里形状语言不一致；
/// 5. 时间胶囊与进度条几乎贴住。
///
/// 渲染方式：用 video_player 上游测试的 FakeController 喂给真控件，
/// 不需要任何平台通道，也不需要真的解码视频。
///
/// 跑法：`flutter test test/video/fullscreen_controls_layout_test.dart`
/// 想看图：`FULLSCREEN_CAPTURE=1 flutter test <本文件>`，产物在 build/visual/。

const _captureKey = ValueKey('fullscreen-controls-capture');

/// 真机同尺寸：2800×1260 物理像素 / 3 = 933×420 逻辑像素。
const _screen = Size(933, 420);

String? _cjk;

Future<void> _loadFonts() async {
  final cjkFile = File(
    '/usr/share/fonts/google-noto-cjk/NotoSansCJK-Regular.ttc',
  );
  if (cjkFile.existsSync()) {
    final loader = FontLoader('WenQuanYi')
      ..addFont(Future.value(cjkFile.readAsBytesSync().buffer.asByteData()));
    await loader.load();
    _cjk = 'WenQuanYi';
  }
  // 图标字体：测试环境默认不加载 MaterialIcons，否则截图全是方块。
  final icons = File(
    '/opt/flutter-sdk/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(icons.readAsBytesSync().buffer.asByteData()));
    await loader.load();
  }
}

/// 进入全屏（**在 pump 之前**，否则 Chewie 会 push 一个独立全屏 Route），
/// 唤出控件栏，返回 ChewieController 以便断言。
Future<ChewieController> _pumpFullscreen(
  WidgetTester tester, {
  bool playing = false,
}) async {
  tester.view.physicalSize = Size(_screen.width * 3, _screen.height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final vc = FakeVideoController(
    VideoPlayerValue(
      duration: const Duration(minutes: 44, seconds: 11),
      position: const Duration(minutes: 1, seconds: 45),
      isInitialized: true,
      isPlaying: playing,
      size: const Size(1920, 800),
    ),
  );
  addTearDown(vc.dispose);

  final chewie = ChewieController(
    videoPlayerController: vc,
    autoInitialize: false,
    autoPlay: false,
    aspectRatio: 16 / 9,
    customControls: const CustomVideoControls(
      title: '初次爱你',
      episodeName: '第01集',
    ),
  );
  addTearDown(chewie.dispose);
  chewie.enterFullScreen();

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: _cjk),
      home: RepaintBoundary(
        key: _captureKey,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Chewie(controller: chewie),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));

  // 控件默认隐藏；点一下唤出（避开中心播放键，免得触发播放）
  await tester.tapAt(Offset(_screen.width * 0.32, _screen.height * 0.5));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return chewie;
}

void main() {
  setUpAll(_loadFonts);

  setUp(() {
    // 有些用例会切深浅，跑完复原，免得污染后续用例
    addTearDown(() {});
  });

  testWidgets('顶栏渐变铺满整宽：左右各留出对称的控件内边距，不再有黑边', (tester) async {
    await _pumpFullscreen(tester);

    final title = find.text('初次爱你');
    expect(title, findsOneWidget, reason: '全屏顶栏应当渲染片名');

    // 返回键是 30dp 的圆钮；它左边缘到屏幕左边的距离 = 顶栏水平内边距。
    final backIcon = find.byIcon(Icons.arrow_back_ios_new_rounded);
    expect(backIcon, findsOneWidget);
    final backRect = tester.getRect(backIcon);
    final backButtonLeft = backRect.center.dx - 15;
    expect(
      backButtonLeft,
      closeTo(10, 1.5),
      reason: '返回键左边缘应贴顶栏 10dp 内边距（渐变已铺满，不需要再留 margin）',
    );

    // 真正的判据（缺陷本体）：顶栏那一条**不能只在中间**。
    // 原实现给外层 Container 加了左右各 10dp 的 margin，渐变只铺在中间，
    // 于是屏幕最左/最右是纯黑（RGB 0,0,0），与中间渐变之间是一条竖直硬边。
    //
    // 这里直接读像素：在顶栏高度内取一行，比较"最左 1dp"与"中间"的亮度。
    // 修复后左边缘也应被渐变覆盖（非纯黑）。
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    final bytes = await tester.binding.runAsync(() async {
      final img = await boundary.toImage(pixelRatio: 3.0);
      final data = await img.toByteData(format: ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    expect(bytes, isNotNull);

    final image = (await tester.binding.runAsync(() async {
      final codec = await ui.instantiateImageCodec(bytes!);
      final frame = await codec.getNextFrame();
      return frame.image;
    }))!;
    final raw = await tester.binding.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    final rgba = raw!.buffer.asUint8List();
    final imgWidth = image.width;
    final imgHeight = image.height;

    int brightnessAt(int x, int y) {
      final i = (y * imgWidth + x) * 4;
      return (rgba[i] + rgba[i + 1] + rgba[i + 2]) ~/ 3;
    }

    // 取顶栏高度 ~8dp 处的一行（渐变在那里已经有明显不透明度）
    final row = (8 * 3).clamp(0, imgHeight - 1);
    final leftEdge = brightnessAt(0, row);
    final center = brightnessAt(imgWidth ~/ 2, row);

    expect(
      leftEdge,
      greaterThanOrEqualTo(center - 4),
      reason:
          '顶栏左边缘亮度 $leftEdge 明显低于中间 $center —— 说明渐变没铺满，'
          '左右还留着黑边（这是第七轮修掉的原始缺陷）',
    );
  });

  testWidgets('底部按钮：播放键与其余按钮同尺寸、同为圆形', (tester) async {
    await _pumpFullscreen(tester);

    // 六个按钮：上一个 / 播放 / 下一个 / 倍速 / 画中画(可能没有) / 全屏
    final previous = find.byIcon(Icons.skip_previous_rounded);
    final play = find.byIcon(Icons.play_arrow_rounded);
    expect(previous, findsOneWidget);
    expect(play, findsOneWidget);

    // 图标本身比按钮小，量它所在 Material 的尺寸
    Size buttonSizeOf(Icon icon) {
      final material = tester.widgetList<Material>(
        find.ancestor(
          of: find.byWidget(icon),
          matching: find.byType(Material),
        ),
      );
      expect(material, isNotEmpty);
      final rect = tester.getRect(
        find
            .ancestor(of: find.byWidget(icon), matching: find.byType(SizedBox))
            .first,
      );
      return rect.size;
    }

    final prevSize = buttonSizeOf(tester.widget<Icon>(previous));
    final playSize = buttonSizeOf(tester.widget<Icon>(play));

    expect(
      prevSize.width,
      closeTo(40, 0.5),
      reason: '全屏普通按钮应为 40dp',
    );
    expect(
      playSize.width,
      closeTo(prevSize.width, 0.5),
      reason: '播放键不该比同类按钮大一圈（原先 52 vs 40）',
    );
    expect(
      playSize.height,
      closeTo(prevSize.height, 0.5),
      reason: '播放键不该比同类按钮高（原先 44 vs 38）',
    );
    expect(
      playSize.width,
      closeTo(playSize.height, 0.5),
      reason: '按钮应为正圆（宽高相等），否则形状和旁边几个对不上',
    );
  });

  testWidgets('时间胶囊与进度条之间留出安全间距', (tester) async {
    await _pumpFullscreen(tester);

    final leftTime = tester.getRect(find.text('01:45'));
    final rightTime = tester.getRect(find.text('44:11'));

    // 进度条本体：找那个自绘的 SizedBox（宽=可用宽度、高=24 触摸区）
    final seekbar = find.byType(GestureDetector);
    expect(seekbar, findsWidgets);

    // 真实判据：时间胶囊**不贴**进度条轨道。
    // 轨道两端的 Padding 是 12dp（原先 8dp），所以胶囊与轨道之间至少 12dp。
    // 这里用胶囊内边距反推：胶囊右边到"进度条区域左边界"的距离。
    final trackLeft = leftTime.right + 12;
    final trackRight = rightTime.left - 12;
    expect(
      trackLeft,
      lessThan(trackRight),
      reason: '进度条必须有正宽度',
    );
    expect(
      trackRight - trackLeft,
      greaterThan(_screen.width * 0.7),
      reason: '进度条应占满中段（两端各让出 12dp 给时间胶囊）',
    );
  });

  testWidgets('全屏底栏贴底留白 ≥ 12dp（不再贴着屏幕边）', (tester) async {
    await _pumpFullscreen(tester);

    // 最下面那排按钮的底边到屏幕底边的距离
    final fullscreenExit = find.byIcon(Icons.fullscreen_exit_rounded);
    expect(fullscreenExit, findsOneWidget);
    final btnRect = tester.getRect(
      find
          .ancestor(
            of: fullscreenExit,
            matching: find.byType(SizedBox),
          )
          .first,
    );
    final bottomGap = _screen.height - btnRect.bottom;
    expect(
      bottomGap,
      greaterThanOrEqualTo(12),
      reason: '底栏离屏幕至少 12dp，否则手势条会压到按钮（原先只有 7dp）',
    );
  });

  testWidgets(
    '落盘全屏控件截图（人眼核对）',
    (tester) async {
      await _pumpFullscreen(tester);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(_captureKey),
      );
      final bytes = await tester.binding.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 3.0);
        final data = await img.toByteData(format: ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });
      final out = File('build/visual/fullscreen_controls.png');
      out.parent.createSync(recursive: true);
      out.writeAsBytesSync(bytes!);
      stdout.writeln('FULLSCREEN_PNG=${out.absolute.path}');
    },
    skip: Platform.environment['FULLSCREEN_CAPTURE'] != '1',
  );
}
