// 服务器运维插件：多服务器模型（B1）的用例 —— 切换器 / 设置列表增改删 / 按服务器的连接。
//
// 必须守住：
//   * 切服务器后**文件页连的是新那台**（用"按设置现建服务"的接缝断言地址）；
//   * 选择与列表持久化（SharedPreferences 的 servers / selected）；
//   * 设置列表能新增 / 编辑 / 删除，**最后一台不许删**；
//   * 口令按服务器分键落进加密存储，且不写进 SharedPreferences；
//   * 「先去设置里填口令」的引导按当前服务器算。
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/server_ops/host_models.dart';
import 'package:box/features/extensions/plugins/server_ops/host_service.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_files_service.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_page.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_runtime.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_secret_store.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ops_test_servers.dart';

/// 取快照必然失败：这些用例只关心连接与设置，别让它真去请求。
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

class _StubFilesService extends ServerOpsFilesService {
  _StubFilesService({required super.settings});

  @override
  Future<List<RemoteStorageEntry>> list(String path) async => const [];
}

/// 内存版加密存储（按服务器分键）。
class _FakeStore implements OpsSecretStore {
  final Map<String, String> values = <String, String>{};
  String? legacy;

  @override
  Future<String?> readPassword(String serverId) async => values[serverId];

  @override
  Future<void> writePassword(String serverId, String password) async {
    values[serverId] = password;
  }

  @override
  Future<void> clearPassword(String serverId) async {
    values.remove(serverId);
  }

  /// 令牌与口令**分表**：两者的生命周期不同（撤销令牌不该动口令），
  /// 用例里也据此断言"改一个不动另一个"。
  final Map<String, String> tokens = <String, String>{};

  @override
  Future<String?> readApiToken(String serverId) async => tokens[serverId];

  @override
  Future<void> writeApiToken(String serverId, String token) async {
    tokens[serverId] = token;
  }

  @override
  Future<void> clearApiToken(String serverId) async {
    tokens.remove(serverId);
  }

  @override
  Future<String?> readLegacyPassword() async => legacy;

  @override
  Future<void> clearLegacyPassword() async {
    legacy = null;
  }
}

late _FakeStore _store;

/// 大一点的窗口：设置弹层比 600px 高，不然点不到下半部分（那是用例的假失败）。
Future<void> _pumpPage(
  WidgetTester tester,
  ServerOpsSettings settings, {
  ServerOpsFilesService Function(ServerOpsSettings settings)? filesServiceFactory,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  debugSetServerOpsRuntime(
    hostService: _FailingHostService(),
    settings: settings,
    filesServiceFactory: filesServiceFactory ??
        (settings) => _StubFilesService(settings: settings),
  );
  await tester.pumpWidget(const MaterialApp(home: ServerOpsPage()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip('设置'));
  await _settle(tester);
}

List<String> _listTexts(WidgetTester tester) {
  final out = <String>[];
  for (final tile in tester.widgetList<ListTile>(find.byType(ListTile))) {
    final subtitle = tile.subtitle;
    if (subtitle is Text && subtitle.data != null) out.add(subtitle.data!);
  }
  return out;
}

/// 两台机器、只有主服务端配了口令的形态（口令状态要按台算）。
const _twoServersOnePassword = ServerOpsSettings(
  servers: [testPrimaryServer, testSecondaryServer],
  selectedServerId: 'hpa888',
  passwords: {'hpa888': 'pw'},
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    _store = _FakeStore();
    debugSetOpsSecretStore(_store);
  });

  tearDown(() => debugSetServerOpsRuntime());

  testWidgets('切换器显示当前机器，切到另一台后文件页连的是新那台', (tester) async {
    final built = <String>[];
    await _pumpPage(
      tester,
      testSettingsOnSecondary,
      filesServiceFactory: (settings) {
        built.add(settings.effectiveBaseUrl);
        return _StubFilesService(settings: settings);
      },
    );

    // 切到「文件」页：它拿到的设置就是当前这台（175）。
    await tester.tap(find.text('文件').first);
    await _settle(tester);
    expect(
      built,
      everyElement('https://box.hpa888.top/dav175'),
      reason: '当前是 175，文件页就该连 /dav175',
    );

    await tester.tap(find.byKey(const ValueKey('ops-server-switcher')));
    await _settle(tester);
    await tester.tap(find.text('阿里云 · 主服务端').last);
    await _settle(tester);

    // 切到主服务端：页面拿着新设置重建了文件页，地址跟着换。
    expect(
      built.last,
      'https://box.hpa888.top/dav',
      reason: '切完必须用新选中的那台重建连接',
    );
    expect(
      find.byKey(const ValueKey('ops-server-switcher')),
      findsOneWidget,
      reason: '切换器还在（没把页面弄崩）',
    );

    // 选择要持久化。
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ServerOpsSettings.selectedKey), 'hpa888');
  });

  testWidgets('文件页的"先去设置里填口令"引导按当前服务器算', (tester) async {
    await _pumpPage(tester, _twoServersOnePassword);
    await tester.tap(find.text('文件').first);
    await _settle(tester);
    expect(
      find.textContaining('还没配置运维通道口令'),
      findsNothing,
      reason: '这台配过口令了',
    );

    // 切到没配口令的 175。
    await tester.tap(find.byKey(const ValueKey('ops-server-switcher')));
    await _settle(tester);
    await tester.tap(find.text('腾讯云 · 构建/监控机').last);
    await _settle(tester);

    expect(
      find.textContaining('还没配置运维通道口令'),
      findsOneWidget,
      reason: '换了台机器，口令状态要跟着这台算',
    );
  });

  testWidgets('设置列表：两台都在，口令状态各按各的显示', (tester) async {
    await _pumpPage(tester, _twoServersOnePassword);
    await _openSettings(tester);

    expect(find.text('运维通道设置'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '腾讯云 · 构建/监控机'), findsOneWidget);
    final subtitles = _listTexts(tester);
    expect(subtitles, hasLength(2));
    expect(subtitles[0], contains('口令：已在本机加密保存'));
    expect(subtitles[1], contains('口令：还没配置'));
  });

  testWidgets('新增服务器：填完确定就进列表，保存后落盘', (tester) async {
    await _pumpPage(tester, testSettingsOnSecondary);
    await _openSettings(tester);

    await tester.tap(find.text('新增服务器'));
    await _settle(tester);

    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), '机房 B');
    await tester.enterText(fields.at(1), 'https://b.test/dav');
    await tester.enterText(fields.at(3), 'pw-b');
    await tester.tap(find.text('确定'));
    await _settle(tester);

    expect(find.text('机房 B'), findsOneWidget);
    expect(_listTexts(tester), hasLength(3));

    await tester.tap(find.text('保存'));
    await _settle(tester);

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(ServerOpsSettings.serversKey)!;
    expect(saved, contains('"label":"机房 B"'));
    expect(saved, contains('"baseUrl":"https://b.test/dav"'));
    expect(saved, contains('srv1'), reason: '新 id 不撞已有的两台');
    expect(
      _store.values['srv1'],
      'pw-b',
      reason: '新口令按服务器分键落进加密存储',
    );
    expect(
      prefs.getString(ServerOpsSettings.passwordKey),
      isNull,
      reason: '明文键永远是空的',
    );
  });

  testWidgets('地址写错了不让保存：把原因指出来，弹窗不关', (tester) async {
    await _pumpPage(tester, testSettingsOnSecondary);
    await _openSettings(tester);
    await tester.tap(find.widgetWithText(ListTile, '腾讯云 · 构建/监控机'));
    await _settle(tester);

    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(1), 'https://box hpa888.top/dav175x');
    await tester.tap(find.text('确定'));
    await _settle(tester);

    expect(find.text('服务器连接 · tencent175'), findsOneWidget,
        reason: '弹窗还开着（标题带上正在改的是哪台）');
    expect(
      find.textContaining('文件通道地址'),
      findsWidgets,
      reason: '要说清是哪一格不对',
    );
  });

  testWidgets('串机器护栏：终端指向另一台时先问一句，能给一键改对', (tester) async {
    // 真机上就是这么错的：175 那条的终端地址指向主服务端，拿 175 的口令去打必然 401
    await _pumpPage(tester, testSettingsOnSecondary);
    await _openSettings(tester);
    await tester.tap(find.widgetWithText(ListTile, '腾讯云 · 构建/监控机'));
    await _settle(tester);

    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(4), 'https://box.hpa888.top/term/');
    await _settle(tester);

    expect(find.textContaining('多半是 401'), findsOneWidget, reason: '当场说清后果');

    // 一键改对：按文件地址推回这一族
    await tester.tap(find.text('改成对的那台'));
    await _settle(tester);
    expect(find.textContaining('多半是 401'), findsNothing, reason: '改对了就不该再提醒');
  });

  testWidgets('编辑服务器：改名/改地址后列表与落盘都跟着变', (tester) async {
    await _pumpPage(tester, testSettingsOnSecondary);
    await _openSettings(tester);

    await tester.tap(find.widgetWithText(ListTile, '腾讯云 · 构建/监控机'));
    await _settle(tester);

    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), '腾讯云 · 新名字');
    await tester.enterText(fields.at(1), 'https://box.hpa888.top/dav175x');
    await tester.tap(find.text('确定'));
    await _settle(tester);
    // 改了文件地址、终端那格却还是旧的一族 → 会先问一句（新加的护栏），测试按"就这样保存"
    if (find.text('地址可能不是同一台').evaluate().isNotEmpty) {
      await tester.tap(find.text('就这样保存'));
      await _settle(tester);
    }

    expect(find.text('腾讯云 · 新名字'), findsOneWidget);
    expect(_listTexts(tester).last, contains('/dav175x'));

    await tester.tap(find.text('保存'));
    await _settle(tester);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(ServerOpsSettings.serversKey),
      contains('https://box.hpa888.top/dav175x'),
    );
    expect(
      prefs.getString(ServerOpsSettings.selectedKey),
      'tencent175',
      reason: '编辑不该顺手把当前选择改掉',
    );
  });

  testWidgets('删除服务器：两台时能删，落盘后只剩一台', (tester) async {
    await _pumpPage(tester, testSettingsOnSecondary);
    await _openSettings(tester);

    await tester.tap(find.byTooltip('删除').last);
    await _settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await _settle(tester);

    expect(
      find.widgetWithText(ListTile, '腾讯云 · 构建/监控机'),
      findsNothing,
      reason: '列表里该没有这一行了',
    );
    expect(_listTexts(tester), hasLength(1));

    await tester.tap(find.text('保存'));
    await _settle(tester);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(ServerOpsSettings.serversKey),
      isNot(contains('tencent175')),
    );
    expect(
      _store.values.containsKey('tencent175'),
      isFalse,
      reason: '删掉的那台的口令键要一起清掉',
    );
  });

  testWidgets('最后一台不许删：给提示，条目还在', (tester) async {
    await _pumpPage(tester, testSettingsPrimary);
    await _openSettings(tester);

    expect(_listTexts(tester), hasLength(1));
    await tester.tap(find.byTooltip('删除'));
    await _settle(tester);

    expect(find.text('最后一台服务器不能删'), findsOneWidget);
    expect(_listTexts(tester), hasLength(1), reason: '不许把最后一台删掉');
  });

  testWidgets('编辑对话框里"清除已保存口令"：保存后分服务器键被清掉', (tester) async {
    _store.values['hpa888'] = 'pw';
    await _pumpPage(tester, testSettingsPrimary);
    await _openSettings(tester);

    await tester.tap(find.widgetWithText(ListTile, '阿里云 · 主服务端'));
    await _settle(tester);
    await tester.tap(find.text('清除已保存口令'));
    await _settle(tester);
    await tester.tap(find.text('确定'));
    await _settle(tester);

    expect(find.textContaining('口令：还没配置'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await _settle(tester);

    expect(_store.values.containsKey('hpa888'), isFalse);
  });
}
