import 'package:box/design_system/app_tokens.dart';
import 'package:box/features/home/presentation/home_page.dart';
import 'package:box/features/home/presentation/widgets/home_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 首页布局在极端屏宽/字号下不应溢出。
///
/// 改版把快捷入口网格从固定 childAspectRatio 换成按内容 + 字体缩放算高度，
/// 这类改动最容易在小屏或放大字体时冒出黄黑 overflow 条，所以专门钉住。
void main() {
  /// 渲染一棵子树并断言没有 overflow 异常。
  Future<void> expectNoOverflow(
    WidgetTester tester, {
    required Widget child,
    required Size size,
    required double textScale,
  }) async {
    tester.view.physicalSize = Size(size.width * 3, size.height * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );

    expect(
      tester.takeException(),
      isNull,
      reason: '屏宽 ${size.width} / 字体 ${textScale}x 下出现了布局异常（通常是 overflow）',
    );
  }

  group('热闻条目在窄屏与放大字体下不溢出', () {
    // 320 是仍在流通的小屏机型下限；1.6x 是系统无障碍常见放大档。
    for (final width in <double>[320, 360, 392]) {
      for (final scale in <double>[1.0, 1.3, 1.6]) {
        testWidgets('屏宽 $width、字体 ${scale}x', (tester) async {
          await expectNoOverflow(
            tester,
            size: Size(width, 720),
            textScale: scale,
            child: const Column(
              children: [
                HomeNewsLine(text: '这是一条比较长的热闻标题用来测试单行截断与布局是否会溢出'),
                HomeNewsLine(text: '短标题'),
                HomeNewsLine(text: '最后一条不画分隔线', showDivider: false),
              ],
            ),
          );
        });
      }
    }
  });

  group('快捷入口卡片在窄屏与放大字体下不溢出', () {
    // 改版历史：最初用 GridView + childAspectRatio 推算格子高度，实测在
    // 1.15x~1.6x 字体下差 3~10px，稳定触发 RenderFlex overflow 黄条。
    // 现结构是 IntrinsicHeight + Row + Expanded，高度由内容决定。
    // 这里直接渲染真实的 HomeQuickActionCard，不复刻任何高度公式。
    for (final width in <double>[320, 360, 392, 412]) {
      for (final scale in <double>[1.0, 1.15, 1.3, 1.6, 2.0]) {
        testWidgets('屏宽 $width、字体 ${scale}x', (tester) async {
          await expectNoOverflow(
            tester,
            size: Size(width, 900),
            textScale: scale,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: HomeQuickActionCard(
                        action: HomeQuickAction(
                          title: '工具',
                          subtitle: '效率工具箱',
                          icon: Icons.handyman_rounded,
                          accent: AppTokens.primaryBlue,
                          onTap: () {},
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: HomeQuickActionCard(
                        action: HomeQuickAction(
                          title: 'AI 生图',
                          subtitle: '多模型生成',
                          icon: Icons.auto_awesome_rounded,
                          accent: AppTokens.violet,
                          onTap: () {},
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      }
    }
  });

  group('HomeNewsLine 分隔线开关', () {
    testWidgets('showDivider=false 时不画底边', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HomeNewsLine(text: '末条', showDivider: false),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(HomeNewsLine),
          matching: find.byType(Container),
        ).first,
      );
      final decoration = container.decoration as BoxDecoration?;
      expect(
        decoration?.border,
        isNull,
        reason: '最后一条不应有分隔线，否则卡片底部会出现悬空的线',
      );
    });

    testWidgets('默认画底边', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: HomeNewsLine(text: '中间条目')),
        ),
      );

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(HomeNewsLine),
          matching: find.byType(Container),
        ).first,
      );
      final decoration = container.decoration as BoxDecoration?;
      expect(decoration?.border, isNotNull);
    });
  });
}
