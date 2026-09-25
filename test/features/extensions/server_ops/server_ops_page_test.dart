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

  testWidgets('设置入口可打开（口令等秘密默认留空，不预填明文）', (tester) async {
    await _pumpPage(tester);
    await tester.tap(find.byTooltip('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('运维通道设置'), findsOneWidget);
    // 地址/用户名预填的是生效值，口令输入框必须是空的。
    final passwordField = tester.widgetList<TextField>(find.byType(TextField));
    expect(passwordField.length, 4, reason: '地址/用户名/口令/终端地址');
    final obscure = passwordField.where((f) => f.obscureText).toList();
    expect(obscure, hasLength(1));
    expect(obscure.single.controller?.text, isEmpty);
  });
}
