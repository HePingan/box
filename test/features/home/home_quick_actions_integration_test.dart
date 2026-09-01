// 首页「快捷入口」接线的集成契约。
//
// 前面的 widget 测试只验证了自选页和热点区块各自的行为，这里补上首页本身：
// 用户存的 id 到底有没有被首页读出来并渲染成卡片。
// 这条接线断了（比如忘了 _loadQuickActions、或者顺序没跟着存储走），
// 单看那两组测试是全绿的。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/extensions/core/home_plugin_core.dart';
import 'package:box/features/home/data/continue_repository.dart';
import 'package:box/features/home/data/home_quick_action_prefs.dart';
import 'package:box/features/home/presentation/home_page.dart';

late List<HomePlugin> _builtIns;

/// 不碰 Hive / SharedPreferences 的「继续使用」数据源。
///
/// 这几条测试关心的是快捷入口接线，不该被本地存储初始化拖下水。
ContinueRepository _noContinueData() => ContinueRepository(
      loadVideoHistory: () async => const [],
      loadBookshelf: () async => const [],
      loadNovelProgress: (_) async => null,
    );

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    _builtIns = HomePluginHost.instance.builtInPluginsForTesting();
    HomePluginHost.instance.seedForTesting(_builtIns);
  });

  tearDown(() {
    HomePluginHost.instance.resetForTesting();
  });

  testWidgets('首页按存储里的 id 和顺序渲染快捷入口', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final enabled = _builtIns.where((p) => p.enabled).toList();
    // 故意挑两个、并且用「倒序」，这样如果实现是按插件表原序渲染
    // 而不是按用户存的顺序，这条会红。
    final first = enabled[1];
    final second = enabled[0];

    final cache = CacheStore.inMemory('home_integration');
    await HomeQuickActionPrefs(cache: cache)
        .saveSelectedIds(<String>[first.id, second.id]);

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          quickActionPrefs: HomeQuickActionPrefs(cache: cache),
          continueRepository: _noContinueData(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('快捷入口'), findsOneWidget);
    expect(find.text('管理'), findsOneWidget);

    final firstPos = tester.getTopLeft(find.text(first.title));
    final secondPos = tester.getTopLeft(find.text(second.title));
    // 同一行时比 x，跨行时比 y —— 总之 first 必须在 second 之前。
    final firstIsBefore = firstPos.dy < secondPos.dy ||
        (firstPos.dy == secondPos.dy && firstPos.dx < secondPos.dx);
    expect(
      firstIsBefore,
      isTrue,
      reason: '快捷入口顺序应跟随用户存储的顺序，而不是插件表原序',
    );
  });

  testWidgets('存储为空时首页显示引导卡而不是空白', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cache = CacheStore.inMemory('home_integration_empty');
    await HomeQuickActionPrefs(cache: cache).saveSelectedIds(const <String>[]);

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          quickActionPrefs: HomeQuickActionPrefs(cache: cache),
          continueRepository: _noContinueData(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('还没有快捷入口'), findsOneWidget);
  });

  testWidgets('本地进度读取抛异常时首页照常渲染，不把异常抛到 initState', (tester) async {
    // 真实场景：Hive 未初始化 / 盒子损坏时 HistoryController.loadHistory 会抛
    // HiveError。「继续使用」只是首页的一个区块，它读不到数据不该让整个首页崩。
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cache = CacheStore.inMemory('home_integration_boom');
    await HomeQuickActionPrefs(cache: cache).saveSelectedIds(const <String>[]);

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          quickActionPrefs: HomeQuickActionPrefs(cache: cache),
          continueRepository: ContinueRepository(
            loadVideoHistory: () async =>
                throw StateError('Hive not initialized'),
            loadBookshelf: () async => const [],
            loadNovelProgress: (_) async => null,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull, reason: '进度读取失败不应冒泡出来');
    expect(find.text('快捷入口'), findsOneWidget, reason: '首页其余部分应正常渲染');
  });
}
