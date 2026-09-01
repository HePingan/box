// 「自选快捷入口」页的交互契约。
//
// 这页是本次改版的核心：快捷入口从硬编码变成用户自选。钉住：
//  1. 已选/可选分区正确，且已选的不重复出现在可选池；
//  2. 添加 / 移除会真正落盘（重进页面还在）；
//  3. 达到上限后拒绝添加并给提示，不静默丢弃；
//  4. 已选里存在「插件已卸载」的残留 id 时，页面不崩、不显示空白条目，
//     但也不静默改存储（插件装回来顺序还能恢复）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/extensions/core/home_plugin_core.dart';
import 'package:box/features/home/data/home_quick_action_prefs.dart';
import 'package:box/features/home/presentation/quick_action_picker_page.dart';

/// 用真实内置插件表里的 id，避免测试和实现各写一份假 id 后一起飘。
late List<HomePlugin> _builtIns;

Future<void> _pumpPicker(
  WidgetTester tester,
  HomeQuickActionPrefs prefs,
) async {
  // 把测试视口拉高，让「已选区 + 可添加池」一屏装得下。
  //
  // 否则要靠 scrollUntilVisible 去找池子里的行，而这页有嵌套滚动
  // （外层 ListView + 内层 shrinkWrap 的 ReorderableListView），
  // `find.byType(Scrollable).first` 拖到的不一定是外层那个，
  // 拖 50 次都露不出目标，报的还是含糊的「Bad state: No element」。
  // 视口拉高把这个坑绕开，断言的是渲染契约本身，不是滚动行为。
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(home: QuickActionPickerPage(prefs: prefs)),
  );
  // 首帧是 loading（读存储是异步的），pumpAndSettle 等它读完。
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    // builtInPluginsForTesting 需要 binding（内部有插件初始化会碰 channel）。
    TestWidgetsFlutterBinding.ensureInitialized();
    _builtIns = HomePluginHost.instance.builtInPluginsForTesting();
    // 页面监听的是 HomePluginHost.listenable，测试里 bootstrap() 会挂在
    // path_provider 上，所以直接把真实内置插件表灌进去。
    HomePluginHost.instance.seedForTesting(_builtIns);
  });

  tearDown(() {
    HomePluginHost.instance.resetForTesting();
  });

  testWidgets('已选区显示默认入口，且它们不再出现在可添加池里', (tester) async {
    final prefs = HomeQuickActionPrefs(
      cache: CacheStore.inMemory('picker_default'),
    );

    await _pumpPicker(tester, prefs);

    // 默认 4 个，标题栏应显示 4/8。
    expect(
      find.textContaining('已放到首页（4/${HomeQuickActionPrefs.maxSlots}）'),
      findsOneWidget,
    );

    // 默认里的插件标题应各只出现一次（在已选区），不该在可选池重复出现。
    for (final id in HomeQuickActionPrefs.defaultIds) {
      final plugin = _builtIns.firstWhere((p) => p.id == id);
      expect(
        find.text(plugin.title),
        findsOneWidget,
        reason: '${plugin.title} 应只在已选区出现一次',
      );
    }
  });

  testWidgets('点「加到首页」会落盘，重进页面仍在', (tester) async {
    final cache = CacheStore.inMemory('picker_add');
    final prefs = HomeQuickActionPrefs(cache: cache);

    await _pumpPicker(tester, prefs);

    // 找一个不在默认列表里的启用插件来添加。
    final candidate = _builtIns.firstWhere(
      (p) => p.enabled && !HomeQuickActionPrefs.defaultIds.contains(p.id),
    );

    // 可选池里点它整行即可添加。
    await tester.tap(find.text(candidate.title));
    await tester.pumpAndSettle();

    // 直接查存储，避免只验证了 UI 局部状态。
    final saved = await HomeQuickActionPrefs(cache: cache).readSelectedIds();
    expect(saved, contains(candidate.id));
    expect(saved.length, HomeQuickActionPrefs.defaultIds.length + 1);
  });

  testWidgets('点移除按钮会落盘删掉该入口', (tester) async {
    final cache = CacheStore.inMemory('picker_remove');
    final prefs = HomeQuickActionPrefs(cache: cache);

    await _pumpPicker(tester, prefs);

    final removeButtons = find.byIcon(Icons.remove_circle_outline_rounded);
    expect(removeButtons, findsWidgets);

    await tester.tap(removeButtons.first);
    await tester.pumpAndSettle();

    final saved = await HomeQuickActionPrefs(cache: cache).readSelectedIds();
    expect(saved.length, HomeQuickActionPrefs.defaultIds.length - 1);
    // 被移掉的是第一个默认项。
    expect(saved, isNot(contains(HomeQuickActionPrefs.defaultIds.first)));
  });

  testWidgets('达到上限后再添加会被拒绝并提示，不静默丢弃', (tester) async {
    final cache = CacheStore.inMemory('picker_full');
    final prefs = HomeQuickActionPrefs(cache: cache);

    // 先塞满 maxSlots 个真实插件 id。
    final enabled = _builtIns.where((p) => p.enabled).toList();
    // 内置插件必须够多才能测满，否则这个用例本身没意义。
    expect(
      enabled.length,
      greaterThan(HomeQuickActionPrefs.maxSlots),
      reason: '内置插件数量不足以填满上限，用例前提不成立',
    );
    await prefs.saveSelectedIds(
      enabled.take(HomeQuickActionPrefs.maxSlots).map((p) => p.id).toList(),
    );

    await _pumpPicker(tester, prefs);

    expect(
      find.textContaining(
        '已放到首页（${HomeQuickActionPrefs.maxSlots}/'
        '${HomeQuickActionPrefs.maxSlots}）',
      ),
      findsOneWidget,
    );

    // 再点一个池子里的插件。
    final extra = enabled[HomeQuickActionPrefs.maxSlots];
    await tester.tap(find.text(extra.title));
    await tester.pump(); // 让 SnackBar 出来

    expect(find.textContaining('最多只能放'), findsOneWidget);

    final saved = await HomeQuickActionPrefs(cache: cache).readSelectedIds();
    expect(saved.length, HomeQuickActionPrefs.maxSlots);
    expect(saved, isNot(contains(extra.id)));
  });

  testWidgets('已选里有不存在的插件 id 时页面不崩，也不静默改存储', (tester) async {
    final cache = CacheStore.inMemory('picker_ghost');
    final prefs = HomeQuickActionPrefs(cache: cache);

    final real = _builtIns.firstWhere((p) => p.enabled);
    await prefs.saveSelectedIds(<String>[real.id, 'plugin_that_was_uninstalled']);

    await _pumpPicker(tester, prefs);

    expect(tester.takeException(), isNull);
    // 幽灵 id 不渲染成条目。
    expect(find.text('plugin_that_was_uninstalled'), findsNothing);
    // 真实那条还在。
    expect(find.text(real.title), findsOneWidget);

    // 存储没被顺手清理——插件装回来后顺序还能恢复。
    final saved = await HomeQuickActionPrefs(cache: cache).readSelectedIds();
    expect(saved, contains('plugin_that_was_uninstalled'));
  });

  testWidgets('全部清空后显示引导文案而不是空白', (tester) async {
    final cache = CacheStore.inMemory('picker_empty');
    final prefs = HomeQuickActionPrefs(cache: cache);
    await prefs.saveSelectedIds(const <String>[]);

    await _pumpPicker(tester, prefs);

    expect(find.text('还没有选任何入口，从下面添加'), findsOneWidget);
  });
}
