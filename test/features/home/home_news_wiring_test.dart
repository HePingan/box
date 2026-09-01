// test/features/home/home_news_wiring_test.dart
//
// 首页热闻的「接线」契约。DailyNewsService 的单测只证明数据层对，
// 这里证明 HomePage 真的把它用对了：
//   - 错误态走独立分支渲染，不混进数据列表（A4）
//   - 后发先至的请求不会覆盖新结果（A3）
//   - 下拉刷新绕过缓存（A2）
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/home/data/ai_hot_models.dart';
import 'package:box/features/home/data/ai_hot_service.dart';
import 'package:box/features/home/data/continue_repository.dart';
import 'package:box/features/home/data/daily_news_service.dart';
import 'package:box/features/home/data/home_quick_action_prefs.dart';
import 'package:box/features/home/presentation/home_page.dart';
import 'package:box/video/controller/video_controller.dart';

/// 永远没有历史的仓库：让「继续使用」走引导态，不碰 Hive。
ContinueRepository _emptyContinue() => ContinueRepository(
      loadVideoHistory: () async => const [],
      loadBookshelf: () async => const [],
      loadNovelProgress: (_) async => null,
    );

/// 不打网络的 AI HOT 桩：首页另一个区块也会发请求，
/// 不桩掉它 pumpAndSettle 永远等不到静止。
class _StubAiHotService extends AiHotService {
  _StubAiHotService() : super(cache: CacheStore.inMemory('wiring_aihot'));

  @override
  Future<AiHotFeed> fetchSelected({
    int take = AiHotService.previewCount,
    bool forceRefresh = false,
  }) async => const AiHotFeed.empty();
}

/// 可控 service：用 completer 精确摆布两次请求的返回顺序。
class _ScriptedNewsService extends DailyNewsService {
  _ScriptedNewsService(this._responses)
      : super(cache: CacheStore.inMemory('wiring_${_seq++}'));

  static int _seq = 0;

  final List<Future<DailyNewsFeed>> _responses;
  int calls = 0;
  final List<bool> forceRefreshLog = <bool>[];

  @override
  Future<DailyNewsFeed> fetch({
    int take = DailyNewsService.previewCount,
    bool forceRefresh = false,
  }) {
    forceRefreshLog.add(forceRefresh);
    final index = calls < _responses.length ? calls : _responses.length - 1;
    calls++;
    return _responses[index];
  }
}

Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<VideoController>(create: (_) => VideoController()),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('拿不到内容时，提示文案以不可点的提示态渲染', (tester) async {
    final service = _ScriptedNewsService([
      Future.value(
        const DailyNewsFeed(items: [], errorMessage: '网络异常，请下拉刷新重试'),
      ),
    ]);

    await tester.pumpWidget(_wrap(HomePage(
      quickActionPrefs: HomeQuickActionPrefs(cache: CacheStore.inMemory('wiring_qa')),
      continueRepository: _emptyContinue(),
      newsService: service,
      aiHotService: _StubAiHotService(),
    )));
    await tester.pumpAndSettle();

    expect(find.text('网络异常，请下拉刷新重试'), findsOneWidget);
    // 提示态不该有可点的箭头（老实现把它当成一条真新闻，带箭头且能点开
    // 一个 url 为 null 的详情页）。
    final chevrons = find.descendant(
      of: find.text('网络异常，请下拉刷新重试'),
      matching: find.byIcon(Icons.chevron_right_rounded),
    );
    expect(chevrons, findsNothing);
  });

  testWidgets('正常内容渲染成可点条目', (tester) async {
    final service = _ScriptedNewsService([
      Future.value(const DailyNewsFeed(items: [
        DailyNewsItem(title: '真新闻一', url: 'https://a.example/1'),
        DailyNewsItem(title: '真新闻二', url: 'https://a.example/2'),
      ])),
    ]);

    await tester.pumpWidget(_wrap(HomePage(
      quickActionPrefs: HomeQuickActionPrefs(cache: CacheStore.inMemory('wiring_qa')),
      continueRepository: _emptyContinue(),
      newsService: service,
      aiHotService: _StubAiHotService(),
    )));
    await tester.pumpAndSettle();

    expect(find.text('真新闻一'), findsOneWidget);
    expect(find.text('真新闻二'), findsOneWidget);
    // 没有任何伪装成新闻的提示文案。
    expect(find.textContaining('下拉刷新重试'), findsNothing);
  });

  testWidgets('后发先至的旧请求不覆盖新结果', (tester) async {
    // 第一次请求慢、第二次快。老实现里第一次返回时会把第二次的结果盖掉。
    final slow = Completer<DailyNewsFeed>();
    final fast = Completer<DailyNewsFeed>();

    final service = _ScriptedNewsService([slow.future, fast.future]);

    await tester.pumpWidget(_wrap(HomePage(
      quickActionPrefs: HomeQuickActionPrefs(cache: CacheStore.inMemory('wiring_qa')),
      continueRepository: _emptyContinue(),
      newsService: service,
      aiHotService: _StubAiHotService(),
    )));
    await tester.pump();

    // 触发第二次拉取（下拉刷新）。
    await tester.fling(find.byType(CustomScrollView).first, const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(service.calls, greaterThanOrEqualTo(2), reason: '应发出第二次请求');

    // 新请求先返回。
    fast.complete(const DailyNewsFeed(items: [
      DailyNewsItem(title: '新结果', url: 'https://a.example/new'),
    ]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 旧请求后返回 —— 必须被丢弃。
    slow.complete(const DailyNewsFeed(items: [
      DailyNewsItem(title: '旧结果', url: 'https://a.example/old'),
    ]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('新结果'), findsOneWidget);
    expect(find.text('旧结果'), findsNothing, reason: 'LoadGeneration 必须挡掉后发先至');

    await tester.pumpAndSettle();
  });

  testWidgets('首屏用缓存、下拉刷新强制绕过缓存', (tester) async {
    final service = _ScriptedNewsService([
      Future.value(const DailyNewsFeed(items: [
        DailyNewsItem(title: '首屏', url: 'https://a.example/1'),
      ])),
      Future.value(const DailyNewsFeed(items: [
        DailyNewsItem(title: '刷新后', url: 'https://a.example/2'),
      ])),
    ]);

    await tester.pumpWidget(_wrap(HomePage(
      quickActionPrefs: HomeQuickActionPrefs(cache: CacheStore.inMemory('wiring_qa')),
      continueRepository: _emptyContinue(),
      newsService: service,
      aiHotService: _StubAiHotService(),
    )));
    await tester.pumpAndSettle();

    expect(service.forceRefreshLog.first, isFalse, reason: '首屏允许吃缓存');

    await tester.fling(find.byType(CustomScrollView).first, const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(service.forceRefreshLog.length, greaterThanOrEqualTo(2));
    expect(
      service.forceRefreshLog[1],
      isTrue,
      reason: '下拉刷新必须绕过缓存，否则用户下拉了却什么都不变',
    );
  });
}
