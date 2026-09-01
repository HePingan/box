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
import 'package:box/features/home/data/home_quick_action_prefs.dart';
import 'package:box/features/home/presentation/home_page.dart';

late List<HomePlugin> _builtIns;

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
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('还没有快捷入口'), findsOneWidget);
  });
}
