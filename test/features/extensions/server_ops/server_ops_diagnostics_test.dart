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
import 'package:box/features/extensions/plugins/server_ops/server_ops_request_log.dart';
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

/// 点「服务器连接」弹窗里的「测试连接」。
///
/// 弹窗现在有 7 个输入框 + 两个勾选 + 体检结果 + 最近请求面板，比测试视口
/// （800x600）高：`tap` 算出来的坐标会命中**下层路由**的滚动视图
/// （命中结果里是 `_RenderScrollSemantics`/`RenderClipRect`），表现为"点了没反应"。
/// `ensureVisible` 救不了（滚动是有动画的，pump 一帧后 tap 用的还是中途坐标），
/// `scrollUntilVisible` 也救不了（弹窗里是 SingleChildScrollView，子节点一次建完，
/// 它认为"已经在树里"就不滚）。
///
/// 所以这里直接取按钮的 onPressed 调一次，并**断言它确实可点**（顺带守住"按钮没被禁用"）。
/// 真实设备上用户是自己滑一下再点，不受影响。
Future<void> _tapDialogButton(WidgetTester tester, String label) async {
  final button = tester.widget<OutlinedButton>(
    find.widgetWithText(OutlinedButton, label),
  );
  expect(button.onPressed, isNotNull, reason: '$label 应该是可点的（没被禁用）');
  button.onPressed!();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  tearDown(() {
    debugSetServerOpsRuntime();
    debugSetOpsRequestLog();
  });

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

    test('文件通道 401 的提示说的是「地址与口令要属于同一台」，不是坚果云那套', () async {
      // 真机反馈过：把 175 的口令填到 /dav 的条目上，402/401 一堆；而底层 WebDAV 的
      // 401 文案来自远端存储插件（"坚果云请使用网页端生成的「应用密码」"），
      // 对自建运维通道是纯噪音，会把用户往错方向带。
      final r = await probeOpsFiles(
        _Files(fail: RemoteStorageException(RemoteStorageError.unauthorized, '口令不对')),
      );
      expect(r.detail, contains('每台机器不同'), reason: r.detail);
      expect(r.detail, contains('属于同一台'), reason: r.detail);
      expect(r.detail, isNot(contains('坚果云')), reason: '别用别的插件的措辞：${r.detail}');
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

    test('四项独立：第一项失败不影响后三项执行', () async {
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

      expect(results, hasLength(4));
      expect(results[0].ok, isFalse);
      expect(results[1].ok, isTrue);
      expect(results[2].ok, isTrue);
      // 第 4 项是 C2 的只读接口：这里没给地址/令牌 → 必须是"照它去设置里填"的可操作结论，
      // 而不是一句失败（它会出现在体检面板上，用户照着它做就行）。
      expect(results[3].ok, isFalse);
      expect(results[3].detail, contains('设置 → 服务器'));
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
      await _tapDialogButton(tester, '测试连接');

      expect(find.textContaining('文件通道（WebDAV）：根目录 1 项'), findsOneWidget);
      expect(find.textContaining('终端（ttyd）：认证失败（401）'), findsOneWidget);
      expect(find.textContaining('主机状态快照：1 台机器'), findsOneWidget);
    });

    testWidgets('口令填成另一台机器的：401 结论里直接点出是「腾讯云 · 构建/监控机」那台的', (tester) async {
      debugSetServerOpsRuntime(
        hostService: _Hosts(
          snapshot: const HostSnapshot(
            hosts: [HostEntry(id: 'hpa888', name: '阿里云')],
          ),
        ),
        settings: const ServerOpsSettings(
          servers: [testPrimaryServer, testSecondaryServer],
          selectedServerId: 'hpa888',
          passwords: {'hpa888': 'pw-hpa', 'tencent175': 'pw-175'},
        ),
        filesService: _Files(
          fail: RemoteStorageException(RemoteStorageError.unauthorized, '口令不对'),
        ),
        terminalProbe: (url, user, password) async => const OpsProbeResult(
          label: '终端（ttyd）',
          ok: false,
          detail: '认证失败（401）：这台机器的口令不对',
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: ServerOpsPage()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byTooltip('设置'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(ListTile, '阿里云 · 主服务端'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 把另一台（175）的口令填到主服务端的条目上 —— 真机反馈过的最常见错法。
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(3), 'pw-175');

      await _tapDialogButton(tester, '测试连接');

      expect(
        find.textContaining('这个口令是「腾讯云 · 构建/监控机」那台的'),
        findsWidgets,
      );
    });

    testWidgets('口令是这台自己的：不弹「别台的」那句（防呆不能误报）', (tester) async {
      debugSetServerOpsRuntime(
        hostService: _Hosts(
          snapshot: const HostSnapshot(
            hosts: [HostEntry(id: 'hpa888', name: '阿里云')],
          ),
        ),
        settings: const ServerOpsSettings(
          servers: [testPrimaryServer, testSecondaryServer],
          selectedServerId: 'hpa888',
          passwords: {'hpa888': 'pw-hpa', 'tencent175': 'pw-175'},
        ),
        filesService: _Files(
          fail: RemoteStorageException(RemoteStorageError.unauthorized, '口令不对'),
        ),
        terminalProbe: (url, user, password) async => const OpsProbeResult(
          label: '终端（ttyd）',
          ok: false,
          detail: '认证失败（401）：这台机器的口令不对',
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: ServerOpsPage()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byTooltip('设置'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(ListTile, '阿里云 · 主服务端'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(3), 'pw-hpa');

      await _tapDialogButton(tester, '测试连接');

      expect(find.textContaining('那台的'), findsNothing);
    });
  });

  group('最近请求（A9）', () {
    testWidgets('跑完体检，面板上留下"哪台机器 / 哪个入口 / 成不成 / 多久"', (tester) async {
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
      await tester.tap(find.byTooltip('设置'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(ListTile, '阿里云 · 主服务端'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await _tapDialogButton(tester, '测试连接');

      // 条数不写死：页面加载时"快照"那项也会记一条，写死就是脆用例。
      expect(
        serverOpsRequestLog.items.where((r) => r.entry == '体检'),
        hasLength(4),
      );
      expect(find.textContaining('最近请求（共'), findsOneWidget);
      expect(find.textContaining('体检 · 阿里云 · 主服务端 · OK'), findsWidgets);
      // 不写死条数：这一轮里**终端（注入的 401）与只读接口（没填令牌）都会失败**，
      // 两个都会各留一条"失败"记录。写死 findsOneWidget 就是脆用例。
      expect(find.textContaining('体检 · 阿里云 · 主服务端 · 失败'), findsWidgets);
      // 面板要能说清是哪一项失败的（[标签] 人话结论）。
      expect(find.textContaining('[终端（ttyd）]'), findsWidgets);
    });

    testWidgets('口令绝不出现在面板上（会被截图/共享屏幕）', (tester) async {
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
      await tester.tap(find.byTooltip('设置'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(ListTile, '阿里云 · 主服务端'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      // 用例里的那把口令是 'pw'（见 ops_test_servers.dart）；填进去、跑一遍体检，
      // 面板与日志里都不该出现它。
      await tester.enterText(fields.at(3), 'sekrit-pw-please-hide');

      await _tapDialogButton(tester, '测试连接');

      expect(find.textContaining('最近请求（共'), findsOneWidget);
      // 只看面板**渲染出来的那些行**：输入框里当然有用户刚打的字（那是他自己输入的，
      // 不是我们记下来的），要守的是"记录与面板里不出现它"。
      final rows = tester
          .widgetList<Text>(find.byWidgetPredicate((w) =>
              w is Text &&
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('ops-recent-')))
          .map((t) => t.data ?? '')
          .toList();
      expect(rows, isNotEmpty, reason: '面板本身要渲染出来，否则这条守卫是空的');
      for (final line in rows) {
        expect(line, isNot(contains('sekrit-pw-please-hide')), reason: line);
      }
      final probes =
          serverOpsRequestLog.items.where((r) => r.entry == '体检').toList();
      expect(probes, hasLength(4), reason: '口令那条不能挡住记录本身');
      for (final r in serverOpsRequestLog.items) {
        expect(r.summary, isNot(contains('sekrit-pw-please-hide')));
      }
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

      expect(results, hasLength(4));
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

      await _tapDialogButton(tester, '测试连接');

      expect(
        probed.single,
        'https://box.hpa888.top/term175/',
        reason: '当前选的是 175，体检就不该去打主服务端的终端',
      );
      expect(find.textContaining('文件通道（WebDAV）：根目录 1 项'), findsOneWidget);
    });
  });
}
