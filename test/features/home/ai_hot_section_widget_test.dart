// 首页「AI 热点」区块的渲染契约。
//
// 钉住四件容易在后续改版里悄悄坏掉的事：
//  1. 有数据时只展示 kAiHotPreviewCount 条（首页不能被热点占满）；
//  2. 署名（attribution）必须出现——用别人的数据，这是底线，
//     不能因为「视觉太挤」被顺手删掉；
//  3. 空态给重试而不是空白，且不显示署名栏（没内容就没来源可署）；
//  4. 缓存数据要打「缓存」标记，别让用户以为看的是最新的。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/home/data/ai_hot_models.dart';
import 'package:box/features/home/presentation/widgets/ai_hot_section.dart';

AiHotItem _item(String id, String title, {String? permalink, String? url}) {
  return AiHotItem(
    id: id,
    title: title,
    permalink: permalink ?? 'https://aihot.virxact.com/i/$id',
    url: url,
    category: 'paper',
    source: 'arxiv',
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required bool isLoading,
  required AiHotFeed? feed,
  void Function(AiHotItem)? onOpenItem,
  VoidCallback? onOpenAll,
  VoidCallback? onRetry,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AiHotSection(
            isLoading: isLoading,
            feed: feed,
            onOpenItem: onOpenItem ?? (_) {},
            onOpenAll: onOpenAll ?? () {},
            onRetry: onRetry ?? () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('有数据时最多只渲染 kAiHotPreviewCount 条', (tester) async {
    // 故意给 6 条，多于展示上限。
    final feed = AiHotFeed(
      items: <AiHotItem>[
        _item('a', '第一条热点'),
        _item('b', '第二条热点'),
        _item('c', '第三条热点'),
        _item('d', '第四条热点'),
        _item('e', '第五条热点'),
        _item('f', '第六条热点'),
      ],
      attributionSource: 'AIHOT',
    );

    await _pump(tester, isLoading: false, feed: feed);

    // 当前上限是 3；这里直接钉住「前 3 条在、第 4 条起不在」，
    // 同时用常量断言一次，避免以后改了 kAiHotPreviewCount 而测试还假绿。
    expect(kAiHotPreviewCount, 3);
    expect(find.text('第一条热点'), findsOneWidget);
    expect(find.text('第二条热点'), findsOneWidget);
    expect(find.text('第三条热点'), findsOneWidget);
    // 第 4 条及以后不该出现。
    expect(find.text('第四条热点'), findsNothing);
    expect(find.text('第五条热点'), findsNothing);
    expect(find.text('第六条热点'), findsNothing);
  });

  testWidgets('署名栏必须展示上游要求的来源', (tester) async {
    final feed = AiHotFeed(
      items: <AiHotItem>[_item('a', '一条热点')],
      attributionSource: 'AIHOT',
    );

    await _pump(tester, isLoading: false, feed: feed);

    expect(find.textContaining('内容来源'), findsOneWidget);
    expect(find.textContaining('AIHOT'), findsOneWidget);
  });

  testWidgets('上游没给 attribution 也要有兜底署名，不能一片空白', (tester) async {
    final feed = AiHotFeed(items: <AiHotItem>[_item('a', '一条热点')]);

    await _pump(tester, isLoading: false, feed: feed);

    expect(find.textContaining('内容来源'), findsOneWidget);
    expect(find.textContaining('AI HOT'), findsOneWidget);
  });

  testWidgets('点某条把该条回调出去（首页据此打开站内 WebView）', (tester) async {
    AiHotItem? tapped;
    final feed = AiHotFeed(
      items: <AiHotItem>[_item('a', '可点热点')],
      attributionSource: 'AIHOT',
    );

    await _pump(
      tester,
      isLoading: false,
      feed: feed,
      onOpenItem: (item) => tapped = item,
    );

    await tester.tap(find.text('可点热点'));
    await tester.pump();

    expect(tapped, isNotNull);
    expect(tapped!.id, 'a');
  });

  testWidgets('空态给重试入口，且不显示署名栏', (tester) async {
    var retried = 0;

    await _pump(
      tester,
      isLoading: false,
      feed: const AiHotFeed.empty(),
      onRetry: () => retried++,
    );

    expect(find.text('暂时拿不到 AI 热点'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    // 没内容就没有来源可署，此时出现署名反而是错的。
    expect(find.textContaining('内容来源'), findsNothing);

    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(retried, 1);
  });

  testWidgets('首次加载中显示转圈而不是空态', (tester) async {
    await _pump(tester, isLoading: true, feed: null);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('暂时拿不到 AI 热点'), findsNothing);
  });

  testWidgets('缓存内容要打「缓存」标记', (tester) async {
    final feed = AiHotFeed(
      items: <AiHotItem>[_item('a', '缓存里的热点')],
      attributionSource: 'AIHOT',
      fromCache: true,
    );

    await _pump(tester, isLoading: false, feed: feed);

    expect(find.text('缓存'), findsOneWidget);
  });

  testWidgets('非缓存内容不该出现「缓存」标记', (tester) async {
    final feed = AiHotFeed(
      items: <AiHotItem>[_item('a', '新鲜热点')],
      attributionSource: 'AIHOT',
    );

    await _pump(tester, isLoading: false, feed: feed);

    expect(find.text('缓存'), findsNothing);
  });

  testWidgets('点「全部」触发进站回调', (tester) async {
    var all = 0;
    final feed = AiHotFeed(
      items: <AiHotItem>[_item('a', '热点')],
      attributionSource: 'AIHOT',
    );

    await _pump(tester, isLoading: false, feed: feed, onOpenAll: () => all++);

    await tester.tap(find.text('全部 ›'));
    await tester.pump();
    expect(all, 1);
  });
}
