// 首页资讯卡合并（A 方案）的行为锁。
//
// 背景：改版前「今日热闻」和「AI 热点」是两个上下紧邻的独立分区，外框、行高、
// 条数（都是 3 条）完全一致，实测渲染下来像同一个组件贴了两遍，且两块合计占掉
// 首屏近六成高度。A 方案把它们合成一张带 Tab 的资讯卡：默认「热闻」，切到
// 「AI」看 AI 热点，两个数据源都保留，省下一个分区标题 + 一套卡片边框的高度。
//
// 这些测试锁住合并**不能弄丢**的东西：
//   - 两个数据源各自的内容、条数上限
//   - AI 侧的署名（上游硬要求）
//   - 各自独立的空态/重试，一边挂了不影响另一边
//   - 点击回调仍然分别生效
library;

import 'package:box/features/home/data/ai_hot_models.dart';
import 'package:box/features/home/data/daily_news_service.dart';
import 'package:box/features/home/presentation/widgets/ai_hot_section.dart';
import 'package:box/features/home/presentation/widgets/home_feed_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(child: child),
  ),
);

const _news = <DailyNewsItem>[
  DailyNewsItem(title: '热闻第一条', url: 'https://example.com/1'),
  DailyNewsItem(title: '热闻第二条', url: 'https://example.com/2'),
  DailyNewsItem(title: '热闻第三条', url: 'https://example.com/3'),
];

const _aiFeed = AiHotFeed(
  items: <AiHotItem>[
    AiHotItem(id: 'a', title: 'AI 第一条'),
    AiHotItem(id: 'b', title: 'AI 第二条'),
    AiHotItem(id: 'c', title: 'AI 第三条'),
  ],
  attributionSource: 'AIHOT',
);

HomeFeedCard _card({
  List<DailyNewsItem> news = _news,
  String newsError = '',
  bool isLoadingNews = false,
  AiHotFeed? aiFeed = _aiFeed,
  bool isLoadingAiHot = false,
  void Function(DailyNewsItem)? onOpenNews,
  void Function(AiHotItem)? onOpenAiHot,
  VoidCallback? onOpenNewsAll,
  VoidCallback? onOpenAiHotAll,
  VoidCallback? onRetryAiHot,
}) => HomeFeedCard(
  isLoadingNews: isLoadingNews,
  newsItems: news,
  newsError: newsError,
  onOpenNews: onOpenNews ?? (_) {},
  onOpenNewsAll: onOpenNewsAll ?? () {},
  isLoadingAiHot: isLoadingAiHot,
  aiHotFeed: aiFeed,
  onOpenAiHot: onOpenAiHot ?? (_) {},
  onOpenAiHotAll: onOpenAiHotAll ?? () {},
  onRetryAiHot: onRetryAiHot ?? () {},
);

void main() {
  group('合并资讯卡：单卡双 Tab', () {
    testWidgets('只有一个分区标题和一张卡片外框（合并的意义所在）', (tester) async {
      await tester.pumpWidget(_host(_card()));
      await tester.pumpAndSettle();

      // 旧的两个独立分区标题都不该再出现
      expect(find.text('今日热闻'), findsNothing);
      expect(find.text('AI 热点'), findsNothing);
      // 合并后是一个统一标题 + 两个 Tab
      expect(find.text('资讯'), findsOneWidget);
      expect(find.text('热闻'), findsOneWidget);
      expect(find.text('AI'), findsOneWidget);
    });

    testWidgets('默认显示热闻，AI 内容不占位', (tester) async {
      await tester.pumpWidget(_host(_card()));
      await tester.pumpAndSettle();

      expect(find.text('热闻第一条'), findsOneWidget);
      expect(find.text('热闻第三条'), findsOneWidget);
      expect(find.text('AI 第一条'), findsNothing);
    });

    testWidgets('切到 AI Tab 显示 AI 热点，热闻让位', (tester) async {
      await tester.pumpWidget(_host(_card()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('AI'));
      await tester.pumpAndSettle();

      expect(find.text('AI 第一条'), findsOneWidget);
      expect(find.text('AI 第三条'), findsOneWidget);
      expect(find.text('热闻第一条'), findsNothing);
    });

    testWidgets('AI Tab 必须保留上游要求的署名', (tester) async {
      await tester.pumpWidget(_host(_card()));
      await tester.pumpAndSettle();

      // 热闻 Tab 下不该出现 AI 的署名
      expect(find.textContaining('内容来源'), findsNothing);

      await tester.tap(find.text('AI'));
      await tester.pumpAndSettle();

      expect(find.textContaining('内容来源'), findsOneWidget);
      expect(find.textContaining('AIHOT'), findsOneWidget);
    });

    testWidgets('两侧空态互不影响：AI 挂了热闻照常看', (tester) async {
      await tester.pumpWidget(_host(_card(aiFeed: const AiHotFeed.empty())));
      await tester.pumpAndSettle();

      expect(find.text('热闻第一条'), findsOneWidget);

      await tester.tap(find.text('AI'));
      await tester.pumpAndSettle();

      expect(find.text('暂时拿不到 AI 热点'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      // 空态不显示署名栏（沿用 AiHotSection 的既有约定）
      expect(find.textContaining('内容来源'), findsNothing);
    });

    testWidgets('热闻挂了 AI 照常看', (tester) async {
      await tester.pumpWidget(
        _host(_card(news: const [], newsError: '网络异常，请下拉刷新重试')),
      );
      await tester.pumpAndSettle();

      expect(find.text('网络异常，请下拉刷新重试'), findsOneWidget);

      await tester.tap(find.text('AI'));
      await tester.pumpAndSettle();

      expect(find.text('AI 第一条'), findsOneWidget);
    });

    testWidgets('两侧各自的加载态互不串台', (tester) async {
      await tester.pumpWidget(
        _host(_card(isLoadingNews: true, news: const [])),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.tap(find.text('AI'));
      await tester.pumpAndSettle();

      // AI 侧不在加载中，应直接出内容而不是继续转圈
      expect(find.text('AI 第一条'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('点击回调分别生效', (tester) async {
      DailyNewsItem? tappedNews;
      AiHotItem? tappedAi;
      await tester.pumpWidget(
        _host(
          _card(
            onOpenNews: (i) => tappedNews = i,
            onOpenAiHot: (i) => tappedAi = i,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('热闻第二条'));
      await tester.pumpAndSettle();
      expect(tappedNews?.title, '热闻第二条');

      await tester.tap(find.text('AI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI 第二条'));
      await tester.pumpAndSettle();
      expect(tappedAi?.id, 'b');
    });

    testWidgets('「更多」按当前 Tab 分派：热闻进热闻页，AI 进 AI 站', (tester) async {
      var newsAll = 0;
      var aiAll = 0;
      await tester.pumpWidget(
        _host(
          _card(onOpenNewsAll: () => newsAll++, onOpenAiHotAll: () => aiAll++),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('更多'));
      await tester.pumpAndSettle();
      expect(newsAll, 1);
      expect(aiAll, 0);

      await tester.tap(find.text('AI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('更多'));
      await tester.pumpAndSettle();
      expect(aiAll, 1);
      expect(newsAll, 1);
    });

    testWidgets('不可点的热闻条目（上游没给 url）不响应点击', (tester) async {
      DailyNewsItem? tapped;
      await tester.pumpWidget(
        _host(
          _card(
            news: const [DailyNewsItem(title: '没有链接的一条')],
            onOpenNews: (i) => tapped = i,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('没有链接的一条'));
      await tester.pumpAndSettle();
      expect(tapped, isNull);
    });

    testWidgets('AI 空态点重试回调出去', (tester) async {
      var retried = 0;
      await tester.pumpWidget(
        _host(
          _card(
            aiFeed: const AiHotFeed.empty(),
            onRetryAiHot: () => retried++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('AI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(retried, 1);
    });
    testWidgets('AI 侧最多只显示 kAiHotPreviewCount 条（从独立分区迁移的断言）', (tester) async {
      final many = AiHotFeed(
        items: List<AiHotItem>.generate(
          kAiHotPreviewCount + 4,
          (i) => AiHotItem(id: 'id$i', title: 'AI 条目 $i'),
        ),
        attributionSource: 'AIHOT',
      );
      await tester.pumpWidget(_host(_card(aiFeed: many)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('AI'));
      await tester.pumpAndSettle();

      expect(find.byType(AiHotRow), findsNWidgets(kAiHotPreviewCount));
      expect(find.text('AI 条目 0'), findsOneWidget);
      expect(find.text('AI 条目 ${kAiHotPreviewCount + 3}'), findsNothing);
    });

    testWidgets('署名缺失时回落到默认标签（从独立分区迁移的断言）', (tester) async {
      const noAttr = AiHotFeed(
        items: <AiHotItem>[AiHotItem(id: 'x', title: '无署名条目')],
      );
      await tester.pumpWidget(_host(_card(aiFeed: noAttr)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('AI'));
      await tester.pumpAndSettle();

      expect(find.textContaining('AI HOT'), findsOneWidget);
    });
    testWidgets('AI 内容来自缓存要打「缓存」标记（从独立分区迁移的断言）', (tester) async {
      const cached = AiHotFeed(
        items: <AiHotItem>[AiHotItem(id: 'x', title: '缓存条目')],
        attributionSource: 'AIHOT',
        fromCache: true,
      );
      await tester.pumpWidget(_host(_card(aiFeed: cached)));
      await tester.pumpAndSettle();

      // 热闻页签下不该出现缓存标记（那是 AI 侧的状态）
      expect(find.text('缓存'), findsNothing);

      await tester.tap(find.text('AI'));
      await tester.pumpAndSettle();
      expect(find.text('缓存'), findsOneWidget);
    });

    testWidgets('非缓存内容不该出现「缓存」标记（从独立分区迁移的断言）', (tester) async {
      await tester.pumpWidget(_host(_card()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('AI'));
      await tester.pumpAndSettle();
      expect(find.text('缓存'), findsNothing);
    });
  });
}
