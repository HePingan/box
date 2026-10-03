import 'package:box/video/widgets/player/player_overlays.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpHud(
    WidgetTester tester, {
    required bool isBrightness,
    required double value,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              PlayerGestureHud(isBrightness: isBrightness, value: value),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('亮度浮层：文案 + 百分比 + 进度值', (tester) async {
    await pumpHud(tester, isBrightness: true, value: 0.42);

    expect(find.text('亮度'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    expect(find.byIcon(Icons.brightness_6_rounded), findsOneWidget);

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(0.42, 0.0001));
  });

  testWidgets('音量浮层：换图标与文案，数值超界时进度条被夹紧', (tester) async {
    await pumpHud(tester, isBrightness: false, value: 3);

    expect(find.text('音量'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 1.0);
  });

  testWidgets('浮层不吃点击（IgnorePointer），不会挡住播放器控件', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => tapped = true,
                child: const SizedBox.expand(),
              ),
              const PlayerGestureHud(isBrightness: true, value: 0.5),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('亮度'), warnIfMissed: false);
    expect(tapped, isTrue, reason: '浮层不应该拦截手势');
  });
}
