// 服务器运维插件：目录与路由接线的冒烟用例 —— 防止「页面写好了但没接上」
// （283 的 clearThumbnailCache 就是这种：有实现、有单测、没有入口）。
//
// 这里会真的构建页面，所以注入"取快照必然失败"的服务与假文件服务：
// 页面走到错误态即可，断言只关心"进的是不是这个页面"。
import 'package:box/features/extensions/core/builtin_plugin_catalog.dart';
import 'package:box/features/extensions/core/builtin_plugin_pages.dart';
import 'package:box/features/extensions/core/home_plugin_core.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/server_ops/host_models.dart';
import 'package:box/features/extensions/plugins/server_ops/host_service.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_files_service.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_page.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_runtime.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingHostService extends HostService {
  @override
  Future<HostSnapshot> fetch() async => throw HostFetchException('用例不联网');

  @override
  Future<HostCachedSnapshot?> cached() async => null;

  @override
  Future<Map<String, HostHistory>> loadHistories() async => const {};

  @override
  Future<Map<String, HostHistory>> recordSample(
    HostSnapshot snapshot, {
    DateTime? now,
  }) async =>
      const {};
}

class _FakeFilesService extends ServerOpsFilesService {
  _FakeFilesService() : super(settings: const ServerOpsSettings());

  @override
  Future<List<RemoteStorageEntry>> list(String path) async => const [];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    debugSetServerOpsRuntime(
      hostService: _FailingHostService(),
      settings: const ServerOpsSettings(),
      filesService: _FakeFilesService(),
    );
  });

  tearDown(() => debugSetServerOpsRuntime());

  test('插件目录里有「服务器运维」条目，且是内建、可点开', () {
    final plugins = buildDefaultPlugins();
    final ops = plugins.where((p) => p.id == 'builtin_server_ops').toList();
    expect(ops, hasLength(1), reason: '服务器运维必须出现在内置插件目录里');
    final plugin = ops.single;
    expect(plugin.title, '服务器运维');
    expect(plugin.builtIn, isTrue);
    expect(plugin.enabled, isTrue);
    expect(plugin.area, HomePluginArea.center);
    expect(plugin.subtitle, isNotEmpty);
  });

  testWidgets('点开条目进的是服务器运维页', (tester) async {
    final plugin =
        buildDefaultPlugins().firstWhere((p) => p.id == 'builtin_server_ops');
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
    expect(find.byType(ServerOpsPage), findsOneWidget);
  });

  testWidgets('路由码 server_ops / openServerOps 指向服务器运维页', (tester) async {
    registerBuiltinRouteDefaults();
    expect(HomePluginRouteRegistry.contains('server_ops'), isTrue);
    expect(HomePluginRouteRegistry.contains('openServerOps'), isTrue);

    final builder = HomePluginRouteRegistry.lookup('openServerOps');
    expect(builder, isNotNull);
    await tester.pumpWidget(MaterialApp(home: Builder(builder: builder!)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(ServerOpsPage), findsOneWidget);
  });
}
