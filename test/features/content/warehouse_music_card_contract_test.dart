// 音乐卡契约锁。
//
// 历史背景：音乐卡曾经副标题写「歌单历史」，点开却是「手动填链接」的表单，
// 而它右边紧邻的卡片就叫「导入资源 / 手动添加」，两者功能完全重复。
//
// 现状（六合四重构后）：手填入口整条链路已下线，音乐卡指向一个明确标注
// 「播放器开发中」的占位页。这里锁住的契约是：
//   1. 副标题不得再承诺任何不存在的功能（歌单历史 / 本地收藏）；
//   2. 音乐入口与漫画入口回调相互独立，不许串线；
//   3. 已下线的「导入资源 / 手动添加」卡不得复活。
library;

import 'package:box/features/content/presentation/widgets/warehouse_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpGrid(
    WidgetTester tester, {
    required VoidCallback onOpenMusic,
    required VoidCallback onOpenComics,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ContentEntryGrid(
              onOpenVideoCenter: () {},
              onOpenNovelLibrary: () {},
              onOpenComics: onOpenComics,
              onOpenMusic: onOpenMusic,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('音乐卡副标题不得承诺不存在的功能', (tester) async {
    await pumpGrid(tester, onOpenMusic: () {}, onOpenComics: () {});

    expect(find.text('音乐'), findsOneWidget);
    expect(
      find.text('歌单历史'),
      findsNothing,
      reason: '项目里没有歌单/播放历史功能，副标题不能承诺做不到的事',
    );
    expect(
      find.text('本地收藏'),
      findsNothing,
      reason: '手填收藏已下线，音乐卡不能再自称「本地收藏」',
    );
    expect(
      find.text('播放器开发中'),
      findsOneWidget,
      reason: '音乐是占位入口，必须如实告知未开放',
    );
  });

  testWidgets('音乐卡点击触发音乐入口回调，且与漫画入口相互独立', (tester) async {
    var musicTaps = 0;
    var comicTaps = 0;

    await pumpGrid(
      tester,
      onOpenMusic: () => musicTaps++,
      onOpenComics: () => comicTaps++,
    );

    await tester.tap(find.text('音乐'));
    await tester.pumpAndSettle();
    expect(musicTaps, 1);
    expect(comicTaps, 0, reason: '两个入口不能串线');

    await tester.tap(find.text('漫画'));
    await tester.pumpAndSettle();
    expect(comicTaps, 1);
    expect(musicTaps, 1);
  });

  testWidgets('已下线的「导入资源 / 手动添加」卡不得复活', (tester) async {
    await pumpGrid(tester, onOpenMusic: () {}, onOpenComics: () {});

    expect(find.text('导入资源'), findsNothing);
    expect(find.text('手动添加'), findsNothing);
  });
}
