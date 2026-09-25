// 服务器运维插件：连接体检（A1）的用例。
//
// 三件必须守住：
//   * 三项互相独立 —— 第一项失败不能挡住后面两项（否则"文件通了但终端挂在哪"永远查不出）；
//   * 结论要带原因/状态码，不能只说"失败"；
//   * 单测里不许联网 —— 终端探针走注入，别让用例真去打 /term/。
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/server_ops/host_models.dart';
import 'package:box/features/extensions/plugins/server_ops/host_service.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_diagnostics.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_files_service.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_page.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_runtime.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ops_test_servers.dart';

const _settings = testSettingsPrimary;

RemoteStorageEntry _file(String name) => RemoteStorageEntry(
      name: name,
      path: name,
      size: 10,
      isDirectory: false,
    );

class _Files extends ServerOpsFilesService {
  _Files({this.entries = const [], this.fail})
      : super(settings: const ServerOpsSettings());

  final List<RemoteStorageEntry> entries;
  final Object? fail;

  @override
  Future<List<RemoteStorageEntry>> list(String path) async {
    if (fail != null) throw fail!;
    return entries;
  }
}

class _Hosts extends HostService {
  _Hosts({this.snapshot, this.error});

  final HostSnapshot? snapshot;
  final Object? error;

  @override
  Future<HostSnapshot> fetch() async {
    if (error != null) throw error!;
    return snapshot!;
  }

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

void main() {
  tearDown(() => debugSetServerOpsRuntime());

  group('三项体检', () {
    test('文件通道：列出根目录就算通，结论报条数', () async {
      final r = await probeOpsFiles(_Files(entries: [_file('a.txt'), _file('b.txt')]));
      expect(r.ok, isTrue);
      expect(r.label, '文件通道（WebDAV）');
      expect(r.detail, '根目录 2 项');
    });

    test('文件通道：失败给中文原因，不是裸异常', () async {
      final r = await probeOpsFiles(
        _Files(fail: RemoteStorageException(RemoteStorageError.unauthorized, '口令不对')),
      );
      expect(r.ok, isFalse);
      expect(r.detail.contains('口令'), isTrue, reason: '结论要能定位：${r.detail}');
    });

    test('主机快照：成功时带上采样时刻（分钟级）', () async {
      final r = await probeOpsSnapshot(
        _Hosts(
          snapshot: HostSnapshot(
            hosts: const [
              HostEntry(id: 'hpa888', name: '阿里云'),
              HostEntry(id: 'tencent175', name: '腾讯云'),
            ],
            generatedAt: DateTime(2026, 9, 25, 8, 30),
          ),
        ),
      );
      expect(r.ok, isTrue);
      expect(r.label, '主机状态快照');
      expect(r.detail.contains('2 台机器'), isTrue, reason: r.detail);
      expect(r.detail.contains(':30'), isTrue, reason: '要能看到采样时刻：${r.detail}');
    });

    test('主机快照：失败把原因原样带出来', () async {
      final r = await probeOpsSnapshot(_Hosts(error: HostFetchException('快照令牌被拒（404）')));
      expect(r.ok, isFalse);
      expect(r.detail, '快照令牌被拒（404）');
    });

    test('终端探针：地址空/非法时直接给结论，不发请求', () async {
      final empty = await probeOpsTerminal('', 'u', 'p');
      expect(empty.ok, isFalse);
      expect(empty.detail.contains('没填'), isTrue, reason: empty.detail);

      final bad = await probeOpsTerminal('not a url', 'u', 'p');
      expect(bad.ok, isFalse, reason: '非法 URL 不能联网试探');
    });

    test('三项独立：第一项失败不影响后两项执行', () async {
      final order = <String>[];
      final results = await runOpsProbes(
        files: _Files(fail: RemoteStorageException(RemoteStorageError.network, '连不上')),
        hosts: _Hosts(
          snapshot: const HostSnapshot(hosts: [HostEntry(id: 'x', name: 'X')]),
        ),
        terminalUrl: 'https://box.hpa888.top/term/',
        user: 'u',
        password: 'p',
        terminalProbe: (url, user, password) async {
          order.add('terminal');
          return const OpsProbeResult(label: '终端（ttyd）', ok: true, detail: '页面可达（200）');
        },
      );

      expect(results, hasLength(3));
      expect(results[0].ok, isFalse);
      expect(results[1].ok, isTrue);
      expect(results[2].ok, isTrue);
      expect(order, ['terminal'], reason: '注入的探针必须被真的调到');
    });
  });

  group('设置页「测试连接」', () {
    testWidgets('点一下把三项结果都显示出来（含失败项的原因）', (tester) async {
      debugSetServerOpsRuntime(
        hostService: _Hosts(
          snapshot: const HostSnapshot(
            hosts: [HostEntry(id: 'hpa888', name: '阿里云')],
          ),
        ),
        settings: _settings,
        filesService: _Files(entries: [_file('root.txt')]),
        terminalProbe: (url, user, password) async => const OpsProbeResult(
          label: '终端（ttyd）',
          ok: false,
          detail: '认证失败（401）：口令不对',
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: ServerOpsPage()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // B1：诊断在一台服务器的对话框里 —— 先打开设置，再点进那一台。
      await tester.tap(find.byTooltip('设置'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(ListTile, '阿里云 · 主服务端'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 对话框内容在小窗口里要滚一下才够得着（真机同款行为）。
      await tester.ensureVisible(find.text('测试连接'));
      await tester.pump();
      await tester.tap(find.text('测试连接'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('文件通道（WebDAV）：根目录 1 项'), findsOneWidget);
      expect(find.textContaining('终端（ttyd）：认证失败（401）'), findsOneWidget);
      expect(find.textContaining('主机状态快照：1 台机器'), findsOneWidget);
    });
  });

  group('诊断跟着服务器走（B1）', () {
    test('runOpsProbesForServer 用的是这台机器的地址 / 用户名 / 终端地址', () async {
      final seen = <String>[];
      final files = _Files(entries: [_file('a.txt')]);
      final results = await runOpsProbesForServer(
        server: testSecondaryServer,
        password: 'pw-175',
        files: files,
        hosts: _Hosts(
          snapshot: const HostSnapshot(hosts: [HostEntry(id: 'x', name: 'X')]),
        ),
        terminalProbe: (url, user, password) async {
          seen.add('$url|$user|$password');
          return const OpsProbeResult(
            label: '终端（ttyd）',
            ok: true,
            detail: '页面可达（200）',
          );
        },
      );

      expect(results, hasLength(3));
      expect(
        seen.single,
        'https://box.hpa888.top/term175/|boxops|pw-175',
        reason: '体检必须打当前这台机器（175），不是主服务端',
      );
    });

    testWidgets('点了另一台服务器：诊断显示的就是那台', (tester) async {
      final probed = <String>[];
      debugSetServerOpsRuntime(
        hostService: _Hosts(
          snapshot: const HostSnapshot(
            hosts: [HostEntry(id: 'tencent175', name: '腾讯云')],
          ),
        ),
        settings: testSettingsOnSecondary,
        filesService: _Files(entries: [_file('root.txt')]),
        terminalProbe: (url, user, password) async {
          probed.add(url);
          return const OpsProbeResult(
            label: '终端（ttyd）',
            ok: true,
            detail: '页面可达（200）',
          );
        },
      );
      await tester.pumpWidget(const MaterialApp(home: ServerOpsPage()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byTooltip('设置'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(ListTile, '腾讯云 · 构建/监控机'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.ensureVisible(find.text('测试连接'));
      await tester.pump();
      await tester.tap(find.text('测试连接'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        probed.single,
        'https://box.hpa888.top/term175/',
        reason: '当前选的是 175，体检就不该去打主服务端的终端',
      );
      expect(find.textContaining('文件通道（WebDAV）：根目录 1 项'), findsOneWidget);
    });
  });
}
