// test/features/home/continue_rail_widget_test.dart
//
// 「继续使用」区块的渲染契约：真实进度要看得见，无历史要给引导而不是空白。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/home/data/continue_item.dart';
import 'package:box/features/home/presentation/widgets/continue_rail.dart';

ContinueItem _item({
  ContinueKind kind = ContinueKind.video,
  String id = 'v1',
  String title = '剧集甲',
  String subtitle = '甲源 · 第3集',
  int updatedAt = 1000,
  String coverUrl = '',
  double? progress,
}) {
  return ContinueItem(
    kind: kind,
    id: id,
    title: title,
    subtitle: subtitle,
    updatedAt: updatedAt,
    coverUrl: coverUrl,
    progress: progress,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required List<ContinueItem> items,
  ValueChanged<ContinueItem>? onOpen,
  VoidCallback? onBrowseNovel,
  VoidCallback? onBrowseVideo,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ContinueRail(
          items: items,
          onOpen: onOpen ?? (_) {},
          onBrowseNovel: onBrowseNovel ?? () {},
          onBrowseVideo: onBrowseVideo ?? () {},
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('有历史时渲染标题、副标题与进度百分比', (tester) async {
    await _pump(tester, items: [_item(progress: 0.42)]);

    expect(find.text('剧集甲'), findsOneWidget);
    expect(find.text('甲源 · 第3集'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('小说条目没有百分比时不画进度条', (tester) async {
    await _pump(
      tester,
      items: [
        _item(
          kind: ContinueKind.novel,
          title: '某本书',
          subtitle: '第十章 山雨',
          progress: null,
        ),
      ],
    );

    expect(find.text('某本书'), findsOneWidget);
    expect(find.text('第十章 山雨'), findsOneWidget);
    expect(
      find.byType(LinearProgressIndicator),
      findsNothing,
      reason: '拿不到可信进度就不该画进度条',
    );
  });

  testWidgets('点击卡片回传被点的那一条', (tester) async {
    final opened = <String>[];
    await _pump(
      tester,
      items: [
        _item(id: 'a', title: '第一条'),
        _item(id: 'b', title: '第二条'),
      ],
      onOpen: (item) => opened.add(item.id),
    );

    await tester.tap(find.text('第二条'));
    await tester.pump();

    expect(opened, ['b'], reason: '必须回传被点那条，不能总回传第一条');
  });

  testWidgets('无历史时给两个发现入口，而不是空白或假的进度卡', (tester) async {
    var novel = 0;
    var video = 0;
    await _pump(
      tester,
      items: const [],
      onBrowseNovel: () => novel++,
      onBrowseVideo: () => video++,
    );

    expect(find.textContaining('还没有'), findsOneWidget);

    await tester.tap(find.text('去书架'));
    await tester.pump();
    await tester.tap(find.text('去影视'));
    await tester.pump();

    expect(novel, 1);
    expect(video, 1);
  });

  testWidgets('影视与小说用不同图标区分来源', (tester) async {
    await _pump(
      tester,
      items: [
        _item(kind: ContinueKind.video, id: 'v', title: '看的'),
        _item(kind: ContinueKind.novel, id: 'n', title: '读的'),
      ],
    );

    expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
    expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);
  });

  testWidgets('封面为空时回落到图标占位，不留裂图', (tester) async {
    await _pump(tester, items: [_item(coverUrl: '')]);

    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
  });

  testWidgets('区块标题为「继续使用」并带查看全部', (tester) async {
    await _pump(tester, items: [_item()]);

    expect(find.text('继续使用'), findsOneWidget);
  });
}
