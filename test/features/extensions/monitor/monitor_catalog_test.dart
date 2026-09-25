// 服务监控插件：目录与路由接线的冒烟用例 —— 防止「页面写好了但没接上」
// （283 的 clearThumbnailCache 就是这种：有实现、有单测、没有入口）。
//
// 这里会真的构建页面，所以注入一个"取快照必然失败"的服务：
// 页面走到错误态即可，断言只关心"进的是不是这个页面"。
import 'package:box/features/extensions/core/builtin_plugin_catalog.dart';
import 'package:box/features/extensions/core/builtin_plugin_pages.dart';
import 'package:box/features/extensions/core/home_plugin_core.dart';
import 'package:box/features/extensions/plugins/monitor/monitor_page.dart';
import 'package:box/features/extensions/plugins/monitor/monitor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    debugSetServiceMonitorRuntime(
      service: ServiceMonitorService(
        fetcher: (url, timeout) async => throw Exception('用例不联网'),
      ),
    );
  });

  tearDown(() => debugSetServiceMonitorRuntime());

  test('插件目录里有「服务监控」条目，且是内建、可点开', () {
    final plugins = buildDefaultPlugins();
    final monitor =
        plugins.where((p) => p.id == 'builtin_service_monitor').toList();
    expect(monitor, hasLength(1), reason: '服务监控必须出现在内置插件目录里');
    final plugin = monitor.single;
    expect(plugin.title, '服务监控');
    expect(plugin.builtIn, isTrue);
    expect(plugin.enabled, isTrue);
    expect(plugin.area, HomePluginArea.center);
    expect(plugin.subtitle, isNotEmpty);
  });

  testWidgets('点开条目进的是服务监控页', (tester) async {
    final plugin =
        buildDefaultPlugins().firstWhere((p) => p.id == 'builtin_service_monitor');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => plugin.onTap(context),
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(ServiceMonitorPage), findsOneWidget);
  });

  testWidgets('路由码 service_monitor / openServiceMonitor 指向服务监控页',
      (tester) async {
    registerBuiltinRouteDefaults();
    expect(HomePluginRouteRegistry.contains('service_monitor'), isTrue);
    expect(HomePluginRouteRegistry.contains('openServiceMonitor'), isTrue);

    final builder = HomePluginRouteRegistry.lookup('openServiceMonitor');
    expect(builder, isNotNull);
    await tester.pumpWidget(MaterialApp(home: Builder(builder: builder!)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(ServiceMonitorPage), findsOneWidget);
  });
}
