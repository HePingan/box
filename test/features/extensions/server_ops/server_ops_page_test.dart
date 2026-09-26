// 服务器运维插件：整页装配的用例（三个页签都在，默认进"服务器"）。
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/server_ops/host_models.dart';
import 'package:box/features/extensions/plugins/server_ops/host_service.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_files_service.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_page.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_runtime.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 取快照必然失败：断言只关心"进的是不是这个页签"，别让它真去请求。
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

Future<void> _pumpPage(WidgetTester tester) async {
  debugSetServerOpsRuntime(
    hostService: _FailingHostService(),
    settings: const ServerOpsSettings(),
    filesService: _FakeFilesService(),
  );
  await tester.pumpWidget(const MaterialApp(home: ServerOpsPage()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  tearDown(() => debugSetServerOpsRuntime());

  testWidgets('三个页签都在，默认停在"服务器"', (tester) async {
    await _pumpPage(tester);

    expect(find.text('服务器运维'), findsOneWidget);
    expect(find.text('服务器'), findsWidgets);
    expect(find.text('文件'), findsWidgets);
    expect(find.text('终端'), findsWidgets);
    // 默认页签是服务器：它进了错误态（假服务不联网）。
    expect(find.text('拿不到主机快照'), findsOneWidget);
  });

  testWidgets('切到"文件"进的是文件页签（面包屑在）', (tester) async {
    await _pumpPage(tester);
    await tester.tap(find.text('文件').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('根目录'), findsOneWidget);
    expect(find.text('新建文件夹'), findsOneWidget);
  });

  testWidgets('切到"终端"：没口令给引导，不是 401 白屏', (tester) async {
    await _pumpPage(tester);
    await tester.tap(find.text('终端').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('还没配置终端口令'), findsOneWidget);
  });

  testWidgets('设置入口打开的是服务器列表，两台内置都在（不预填任何口令）', (tester) async {
    await _pumpPage(tester);
    await tester.tap(find.byTooltip('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('运维通道设置'), findsOneWidget);
    expect(find.text('腾讯云 · 构建/监控机'), findsOneWidget);
    expect(find.text('阿里云 · 主服务端'), findsWidgets);
    expect(find.text('新增服务器'), findsOneWidget);
    // 列表里没有明文口令输入框：口令只在"点进一台"的对话框里填。
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.widgetWithText(ListTile, '阿里云 · 主服务端'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 名称/地址/用户名/口令/终端地址/只读接口地址/设备令牌 共 7 个输入框。
    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields, hasLength(7));
    // 两个秘密框（口令 + 设备令牌）都必须空的：不预填、不回显。
    final obscure = fields.where((f) => f.obscureText).toList();
    expect(obscure, hasLength(2), reason: '口令与设备令牌都是秘密');
    for (final f in obscure) {
      expect(f.controller?.text, isEmpty);
    }
    // 只读接口地址**不是**秘密：内置两台各有一个默认值（用户只差填令牌）。
    expect(
      fields.any((f) => (f.controller?.text ?? '').contains('/opsapi')),
      isTrue,
      reason: '内置机器要带默认的只读接口地址',
    );
  });

  testWidgets('AppBar 的切换器显示当前机器，展开能看到两台', (tester) async {
    await _pumpPage(tester);

    expect(find.byKey(const ValueKey('ops-server-switcher')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ops-server-switcher')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('阿里云 · 主服务端'), findsWidgets);
    expect(find.text('腾讯云 · 构建/监控机'), findsOneWidget);
    // 切换器每一项现在多一行"终端怎么样"（真机上正是这一格把人带偏的），
    // 所以地址那行不再是一整条 Text
    expect(find.textContaining('https://box.hpa888.top/dav175'), findsOneWidget);
    expect(find.textContaining('终端：'), findsWidgets);
  });
}
