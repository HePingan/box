library;

import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:box/design_system/app_tokens.dart';
import 'package:box/features/home/presentation/home_page.dart';
import 'package:box/features/home/presentation/widgets/home_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

/// 把改版后的首页各分区渲染成真实 PNG，用来人眼核对排版。
///
/// 这不是 golden 断言（不比对基准图，也不用 matchesGoldenFile），
/// 只是把真实渲染结果落盘，
/// 避免「靠读代码猜视觉效果」。产物写到 build/visual/ 下。
///
/// 跑法：flutter test test/features/home/home_visual_golden_capture_test.dart

/// 注册成功后的中文字体族名；注册失败时为 null（截图会退回豆腐块）。
String? _cjkFontFamily;

/// 抓图边界的定位 key。
const _captureKey = ValueKey('home-visual-capture');

void main() {
  // headless 测试环境默认只有 Ahem/Roboto，没有中文字形，截图会全是豆腐块 □，
  // 人眼没法核对排版。这里把系统里的文泉驿正黑注册进测试字体库，让中文真实成字。
  setUpAll(() async {
    final candidates = <String>['/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc'];
    for (final path in candidates) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final loader = FontLoader('WenQuanYi')
        ..addFont(Future.value(file.readAsBytesSync().buffer.asByteData()));
      await loader.load();
      _cjkFontFamily = 'WenQuanYi';
      break;
    }
  });

  // 用环境变量而不是 @Tags 门控：dart_test.yaml 的 exclude_tags 是叠加的，
  // 命令行 --tags/--exclude-tags 都盖不掉它，打了 tag 反而永远跑不起来。
  // 跑法：HOME_VISUAL_CAPTURE=1 flutter test <本文件>
  testWidgets(
    '渲染首页分区并落盘 PNG',
    (tester) async {
      tester.view.physicalSize = const Size(392 * 3, 1000 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      // 复刻首页真实用到的四个快捷入口 + 两张继续使用卡 + 三条热闻，
      // 数据与 home_page.dart 里的一致（颜色走同一套 token）。
      final continueItems = [
        HomeContinueItem(
          eyebrow: '继续阅读',
          title: '小说书架',
          subtitle: '查看收藏与最近阅读',
          icon: Icons.menu_book_rounded,
          color: AppTokens.amber,
          onTap: () {},
        ),
        HomeContinueItem(
          eyebrow: '继续观看',
          title: '影视搜索',
          subtitle: '聚合影片、剧集与播放源',
          icon: Icons.play_circle_fill_rounded,
          color: AppTokens.emerald,
          onTap: () {},
        ),
      ];

      Widget sectionHeader(String title, Color accent, {Widget? action}) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppTokens.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (action != null) action,
            ],
          ),
        );
      }

      await tester.pumpWidget(
        RepaintBoundary(
          key: _captureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: _cjkFontFamily),
            // 必须有 Material 祖先：HomeContinueCard 内部用 InkWell。
            home: Scaffold(
              backgroundColor: AppTokens.background,
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 20, 14, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      sectionHeader('快捷入口', AppTokens.primaryBlue),
                      // 与 home_page.dart 同结构：IntrinsicHeight + Row + Expanded，
                      // 不用 GridView/childAspectRatio（会 overflow）。
                      for (final pair in <List<HomeQuickAction>>[
                        [
                          HomeQuickAction(
                            title: '工具',
                            subtitle: '效率工具箱',
                            icon: Icons.handyman_rounded,
                            accent: AppTokens.primaryBlue,
                            onTap: () {},
                          ),
                          HomeQuickAction(
                            title: '内容',
                            subtitle: '小说与影视',
                            icon: Icons.collections_bookmark_rounded,
                            accent: AppTokens.emerald,
                            onTap: () {},
                          ),
                        ],
                        [
                          HomeQuickAction(
                            title: 'AI 生图',
                            subtitle: '多模型生成',
                            icon: Icons.auto_awesome_rounded,
                            accent: AppTokens.violet,
                            onTap: () {},
                          ),
                          HomeQuickAction(
                            title: '扩展',
                            subtitle: '插件市场',
                            icon: Icons.tune_rounded,
                            accent: AppTokens.cyan,
                            onTap: () {},
                          ),
                        ],
                      ]) ...[
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: HomeQuickActionCard(action: pair[0]),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: HomeQuickActionCard(action: pair[1]),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 8),
                      sectionHeader('继续使用', AppTokens.amber),
                      SizedBox(
                        height: 72,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: continueItems.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (_, i) =>
                              HomeContinueCard(item: continueItems[i]),
                        ),
                      ),
                      const SizedBox(height: 18),
                      sectionHeader(
                        '今日热闻',
                        AppTokens.orange,
                        action: const Text(
                          '更多',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppTokens.primaryBlue,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTokens.surface,
                          borderRadius: BorderRadius.circular(
                            AppTokens.radiusCard,
                          ),
                          border: Border.all(color: AppTokens.divider),
                        ),
                        child: const Column(
                          children: [
                            HomeNewsLine(text: '国内多地迎来降温，部分地区发布寒潮预警信号'),
                            HomeNewsLine(text: '新一代折叠屏手机发布，续航与铰链结构均有升级'),
                            HomeNewsLine(
                              text: '某科技公司公布季度财报，营收同比增长超预期',
                              showDivider: false,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      sectionHeader('热闻空态（不可点、无箭头）', AppTokens.orange),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTokens.surface,
                          borderRadius: BorderRadius.circular(
                            AppTokens.radiusCard,
                          ),
                          border: Border.all(color: AppTokens.divider),
                        ),
                        child: const HomeNewsLine(
                          text: '网络异常，请下拉刷新重试',
                          showDivider: false,
                          isPlaceholder: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 直接从 RepaintBoundary 抓像素落盘，不用 matchesGoldenFile。
      // 原因：matchesGoldenFile 是「比对基准图」的断言，没有 --update-goldens
      // 时会判定失败，还会生成 failures/*Diff.png；而基准图本身不入库
      // （截图是给人看的产物，不是回归基线），于是这个 gate 永远不可能通过。
      // 这里要的只是「把真实渲染结果写出来」，所以自己编码 PNG。
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(_captureKey),
      );
      final bytes = await tester.binding.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3.0);
        final data = await image.toByteData(format: ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });
      expect(bytes, isNotNull, reason: '应能抓到真实渲染像素');

      final f = File('test/features/home/goldens/home_sections.png');
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(bytes!);
      stdout.writeln('VISUAL_PNG=${f.absolute.path} bytes=${f.lengthSync()}');
    },
    // dart_test.yaml 的 exclude_tags 是叠加的，命令行 --tags/--exclude-tags
    // 都盖不掉，所以不用 @Tags 门控，改用环境变量。
    // 跑法：HOME_VISUAL_CAPTURE=1 flutter test <本文件>
    skip: Platform.environment['HOME_VISUAL_CAPTURE'] != '1',
  );
}
