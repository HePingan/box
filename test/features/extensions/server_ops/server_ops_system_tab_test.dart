// 服务器运维插件：「系统」页签（C2 门面）的用例。
//
// 这一页守的是三件事：
//   1. **没配令牌时给"去哪填"的引导**，而不是一句 failed（真机上这就是用户唯一能看到的线索）；
//   2. **一节挂了不拖垮整页**（进程/服务/端口/磁盘/登录各拉各的）；
//   3. 401 的文案要讲清"口令与令牌不是一回事"——291 那类串台坑在 C2 上的同形；
//   4. 每次刷新往 A9 的请求日志记一条（入口=系统），且**记录与页面都不出现令牌**。
import 'dart:convert';

import 'package:box/features/extensions/plugins/server_ops/server_ops_api_client.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_request_log.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';
import 'package:box/features/extensions/plugins/server_ops/system_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const String _token = 'tok-system-tab-1';

/// 一台配好东西的服务器（地址与令牌都不是构建默认值，避免"假通"）。
const ServerOpsServer _server = ServerOpsServer(
  id: 'hpa888',
  label: '阿里云 · 主服务端',
  baseUrl: 'https://box.hpa888.top/dav',
  user: 'boxops',
  terminalUrl: 'https://box.hpa888.top/term/',
  apiUrl: 'https://box.hpa888.top/opsapi',
  snapshotId: 'hpa888',
);

ServerOpsSettings _settings({String token = _token, String apiUrl = 'https://box.hpa888.top/opsapi'}) =>
    ServerOpsSettings(
      servers: [_server.copyWith(apiUrl: apiUrl)],
      selectedServerId: 'hpa888',
      passwords: const {'hpa888': 'pw'},
      apiTokens: {if (token.isNotEmpty) 'hpa888': token},
    );

/// 按动作回假的 JSON（可选让某个动作失败）；同时记录请求路径。
/// 假响应**必须带 charset=utf-8**：`http.Response(String, status)` 默认按 latin1 编码 body，
/// 中文会直接抛 ArgumentError（"Contains invalid characters"），而被客户端按"网络错"归类 ——
/// 排查时表现为"403 变成了网络错误"，很费时间。第一次就是这么踩的。
const Map<String, String> _jsonHeaders = {
  'content-type': 'application/json; charset=utf-8',
};

MockClient _api({
  required List<String> seen,
  List<String>? queries,
  int? failStatusFor,
  String? failAction,
  bool write = true,
}) =>
    MockClient((req) async {
      final action = req.url.path.split('/').where((s) => s.isNotEmpty).last;
      seen.add(action);
      queries?.add('$action?${req.url.query}');
      if (failAction != null && action == failAction) {
        return http.Response(
            jsonEncode({'error': '没有权限'}),
          failStatusFor ?? 403,
          headers: _jsonHeaders,
        );
      }
      switch (action) {
        case 'capabilities':
          return http.Response(
            jsonEncode({
              'hostname': 'VM-0-15-debian',
              'version': '1.1.0',
              'admin': true,
              'write': write,
              'readActions': ['health', 'overview', 'capabilities'],
              'writeActions': ['capabilities', 'service', 'mkdir', 'chmod', 'chown', 'extract'],
              'selfDestructiveUnits': ['sshd.service', 'box-ops-api.service'],
              'protectedPaths': ['/root/.secrets'],
            }),
            200,
            headers: _jsonHeaders,
          );
        case 'overview':
          return http.Response(
            jsonEncode({
              'hostname': 'VM-0-15-debian',
              'os': {'pretty': 'Debian GNU/Linux 12', 'kernel': '6.1.0'},
              'uptimeSeconds': 90061,
              'load': {'load1': 0.5, 'load5': 0.4, 'load15': 0.3},
              'cpu': {'model': 'Intel(R) Xeon(R) Platinum', 'cores': 4},
              'memory': {'memTotal': 8000000000, 'memUsed': 3300000000, 'swapTotal': 0, 'swapUsed': 0},
              'disks': [
                {'mount': '/', 'size': '59G', 'used': '46G', 'avail': '10G', 'usePercent': '78%'}
              ],
            }),
            200,
            headers: _jsonHeaders,
          );
        case 'processes':
          return http.Response(
            jsonEncode({
              'processes': [
                {'pid': 1234, 'user': 'root', 'cpuPercent': 12.5, 'memPercent': 3.1, 'rssKb': 2048, 'elapsed': '01:02', 'name': 'python3', 'args': 'box-ops-api.py serve'},
              ],
            }),
            200,
            headers: _jsonHeaders,
          );
        case 'services':
          return http.Response(
            jsonEncode({
              'units': [
                {'unit': 'nginx.service', 'active': 'active', 'sub': 'running', 'enabled': 'enabled', 'description': 'nginx'},
                {'unit': 'box-ops-api.service', 'active': 'failed', 'sub': 'failed', 'enabled': 'enabled', 'description': 'box-ops api'},
              ],
            }),
            200,
            headers: _jsonHeaders,
          );
        case 'service':
          // 同一个 action 既用于 GET（详情）也用于 POST（启停）：形状都带 activeState。
          return http.Response(
            jsonEncode({
              'unit': 'nginx.service',
              'activeState': 'active',
              'subState': 'running',
              'unitFileState': 'enabled',
              'mainPid': '1234',
              'memoryBytes': 45678901,
              'restarts': '0',
              'since': 'Fri 2026-09-25 20:00:00 CST',
              'journal': '20:00:01 started',
            }),
            200,
            headers: _jsonHeaders,
          );
        case 'ports':
          return http.Response(
            jsonEncode({
              'listeners': [
                {'proto': 'tcp', 'state': 'LISTEN', 'local': '127.0.0.1:8095', 'process': 'python3'},
              ],
            }),
            200,
            headers: _jsonHeaders,
          );
        case 'diskusage':
          return http.Response(
            jsonEncode({
              'rows': [
                {'size': '1.2G', 'path': '/var/log'},
              ],
            }),
            200,
            headers: _jsonHeaders,
          );
        case 'sessions':
          return http.Response(
            jsonEncode({
              'logins': [
                {'user': 'root', 'tty': 'pts/0', 'from': '1.2.3.4', 'at': 'Fri Sep 25 20:00'},
              ],
              'failedLogins': [
                {'user': 'admin', 'tty': 'ssh:notty', 'from': '9.9.9.9', 'at': 'Fri Sep 25 19:00'},
              ],
            }),
            200,
            headers: _jsonHeaders,
          );
        case 'logfiles':
          return http.Response(
            jsonEncode({
              'count': 3,
              'total': 3,
              'roots': ['/var/log', '/www/wwwlogs', '/home/update-server/logs'],
              'list': [
                {'path': '/www/wwwlogs/box.hpa888.top.log', 'name': 'box.hpa888.top.log',
                 'root': '/www/wwwlogs', 'size': 4096, 'mtime': '2026-09-26 09:41:03'},
                {'path': '/var/log/nginx/access.log', 'name': 'access.log',
                 'root': '/var/log', 'size': 2048, 'mtime': '2026-09-26 09:40:00'},
                {'path': '/var/log/syslog', 'name': 'syslog',
                 'root': '/var/log', 'size': 8192, 'mtime': '2026-09-26 09:30:00'},
              ],
            }),
            200,
            headers: _jsonHeaders,
          );
        case 'logs':
          return http.Response(
            jsonEncode({
              'path': '/www/wwwlogs/box.hpa888.top.log',
              'lines': 2,
              'truncated': false,
              'content': '10.0.0.1 - - GET /health 200\n10.0.0.2 - - GET /updates 206',
              'generatedAt': '2026-09-26T09:41:05+08:00',
            }),
            200,
            headers: _jsonHeaders,
          );
        case 'channel':
          return http.Response(
            jsonEncode({
              'available': true,
              'logPath': '/www/wwwlogs/box-ops-access.log',
              'ownerHost': 'hpa888',
              'windowDays': 7,
              'users': [
                {'user': 'phone-hpa888', 'readOnly': false, 'stillValid': true,
                 'count': 42, 'lastSeen': '2026-09-26 09:47:12', 'lastIp': '120.32.145.146',
                 'entries': {'hpa888 文件': 40, 'hpa888 终端': 2},
                 'methods': {'PROPFIND': 30, 'GET': 12}, 'denied': 0},
                {'user': 'ro-probe-175', 'readOnly': true, 'stillValid': true,
                 'count': 8, 'lastSeen': '2026-09-26 09:40:05', 'lastIp': '175.178.248.237',
                 'entries': {'175 文件': 8}, 'methods': {'PROPFIND': 8}, 'denied': 1},
                {'user': 'old-device', 'readOnly': false, 'stillValid': false,
                 'count': 3, 'lastSeen': '2026-09-26 09:20:00', 'lastIp': '10.0.0.9',
                 'entries': {'hpa888 文件': 3}, 'methods': {'GET': 3}, 'denied': 3},
              ],
              'unused': ['phone-175'],
            }),
            200,
            headers: _jsonHeaders,
          );
        case 'audit':
          return http.Response(
            jsonEncode({
              'items': [
                {'at': '2026-09-25T22:00:00+08:00', 'action': 'overview', 'token': 'box-app-hpa888', 'ip': '5.6.7.8', 'status': 200, 'ms': 31},
              ],
            }),
            200,
            headers: _jsonHeaders,
          );
        default:
          return http.Response('{}', 200);
      }
    });

Future<void> _pump(WidgetTester tester, ServerOpsSettings settings, MockClient client) async {
  // 窗口放大：这一页有七个小节，600px 高会让下面的小节根本没被建出来（假的失败）。
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ServerOpsSystemTab(
          settings: settings,
          clientFactory: (s) => OpsApiClient(
            baseUrl: s.effectiveApiUrl,
            token: s.effectiveApiToken,
            client: client,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() {
    serverOpsRequestLog = OpsRequestLog();
  });

  testWidgets('没配令牌：给"去哪填"的引导，且一次请求都不发', (tester) async {
    final seen = <String>[];
    await _pump(tester, _settings(token: ''), _api(seen: seen));

    expect(find.text('这台机器还没接只读接口'), findsOneWidget);
    expect(find.textContaining('设备令牌：'), findsOneWidget);
    expect(find.textContaining('不是同一个凭据'), findsOneWidget);
    expect(seen, isEmpty, reason: '没令牌就别去敲接口');
    expect(serverOpsRequestLog.items, isEmpty);
  });

  testWidgets('配好了：各小节都渲染出来，并留一条"系统"请求记录', (tester) async {
    final seen = <String>[];
    await _pump(tester, _settings(), _api(seen: seen));

    expect(
      seen,
      containsAll(['capabilities', 'overview', 'processes', 'services', 'ports',
        'diskusage', 'sessions', 'audit', 'logfiles']),
    );
    expect(find.textContaining('概览'), findsWidgets);
    expect(find.text('VM-0-15-debian'), findsOneWidget);
    expect(find.textContaining('Intel(R) Xeon(R) Platinum'), findsOneWidget);
    expect(find.textContaining('1 天 1 小时'), findsOneWidget);
    expect(find.textContaining('nginx.service'), findsWidgets);
    expect(find.textContaining('127.0.0.1:8095'), findsWidgets);
    expect(find.textContaining('admin'), findsWidgets);
    expect(find.textContaining('日志（白名单'), findsOneWidget);

    final records = serverOpsRequestLog.items;
    expect(records, hasLength(1));
    expect(records.single.entry, '系统');
    expect(records.single.ok, isTrue);
    expect(records.single.serverLabel, '阿里云 · 主服务端');
    expect(records.single.detail, contains('4 核'));
    expect(records.single.detail, contains('内存'));
  });

  testWidgets('一节失败不拖垮整页：端口 403，其它节照旧渲染', (tester) async {
    final seen = <String>[];
    await _pump(
      tester,
      _settings(),
      _api(seen: seen, failAction: 'ports', failStatusFor: 403),
    );

    expect(find.textContaining('端口：没有权限'), findsOneWidget);
    // 别的节还在
    expect(find.text('VM-0-15-debian'), findsOneWidget);
    expect(find.textContaining('nginx.service'), findsWidgets);
    expect(find.textContaining('127.0.0.1:8095'), findsNothing, reason: '端口那节确实挂了');

    final rec = serverOpsRequestLog.items.single;
    expect(rec.ok, isFalse);
    expect(rec.detail, contains('没有权限'));
  });

  testWidgets('401：页面说清"口令与令牌不是一回事"（防串台）', (tester) async {
    final seen = <String>[];
    await _pump(
      tester,
      _settings(),
      _api(seen: seen, failAction: 'overview', failStatusFor: 401),
    );

    expect(find.textContaining('设备令牌无效或已被撤销'), findsWidgets);
    expect(find.textContaining('不是一回事'), findsWidgets);
  });

  testWidgets('令牌绝不出现在页面上（会被截图/共享屏幕）', (tester) async {
    final seen = <String>[];
    await _pump(tester, _settings(), _api(seen: seen));

    for (final w in tester.widgetList<Text>(find.byType(Text))) {
      expect(w.data ?? '', isNot(contains(_token)));
    }
    for (final r in serverOpsRequestLog.items) {
      expect(r.summary, isNot(contains(_token)));
    }
  });

  testWidgets('服务详情：有写权限时出现启停按钮，点了要确认', (tester) async {
    final seen = <String>[];
    await _pump(tester, _settings(), _api(seen: seen));

    await tester.tap(find.text('nginx.service').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(seen, contains('service'));
    expect(find.text('重启'), findsOneWidget);
    expect(find.text('开机自启'), findsOneWidget);

    // 点了要先确认（写动作会真的改机器）。
    await tester.tap(find.text('重启'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('这会真的改动这台机器'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });

  testWidgets('服务详情：只读令牌不显示写按钮，并说明怎么开', (tester) async {
    final seen = <String>[];
    await _pump(tester, _settings(), _api(seen: seen, write: false));

    await tester.tap(find.text('nginx.service').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('这把令牌只能读'), findsOneWidget);
    // 按钮还在（形状一致），但是禁用的 —— 不让用户点了才知道。
    final restart = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '重启'),
    );
    expect(restart.onPressed, isNull);
  });

  testWidgets('日志小节：列出白名单里的文件（最近的在前），点开能看尾巴', (tester) async {
    final seen = <String>[];
    final queries = <String>[];
    await _pump(tester, _settings(), _api(seen: seen, queries: queries));

    expect(find.textContaining('日志（白名单'), findsOneWidget);
    // 白名单内的三个文件都在（前 4 个直接列，3 个都在里面）
    expect(find.text('/www/wwwlogs/box.hpa888.top.log'), findsOneWidget);
    expect(find.text('/var/log/nginx/access.log'), findsOneWidget);
    expect(find.textContaining('4.0 KB'), findsWidgets);

    // 点第一个：弹层去读尾巴，默认 100 行
    await tester.tap(find.text('/www/wwwlogs/box.hpa888.top.log'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(queries, contains('logs?path=%2Fwww%2Fwwwlogs%2Fbox.hpa888.top.log&lines=100'));
    expect(find.textContaining('GET /health 200'), findsOneWidget);

    // 切 500 行：重读一次
    await tester.tap(find.text('500 行'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(queries, contains('logs?path=%2Fwww%2Fwwwlogs%2Fbox.hpa888.top.log&lines=500'));
  });

  testWidgets('日志小节挂了只挂这一节：别的节照旧', (tester) async {
    final seen = <String>[];
    await _pump(tester, _settings(),
        _api(seen: seen, failAction: 'logfiles', failStatusFor: 403));

    expect(find.textContaining('日志文件'), findsWidgets, reason: '这一节要有自己的错误卡');
    expect(find.textContaining('没有权限'), findsWidgets);
    expect(find.text('VM-0-15-debian'), findsOneWidget, reason: '概览不该被带崩');
    expect(find.textContaining('127.0.0.1:8095'), findsWidgets, reason: '端口不该被带崩');
  });

  testWidgets('通道凭据：谁在用、用哪条、最近什么时候，且不出现口令与哈希', (tester) async {
    final seen = <String>[];
    await _pump(tester, _settings(), _api(seen: seen));

    expect(seen, contains('channel'));
    expect(find.textContaining('通道凭据（最近 7 天）'), findsOneWidget);
    expect(find.textContaining('phone-hpa888'), findsWidgets);
    expect(find.textContaining('42 次'), findsOneWidget);
    expect(find.textContaining('hpa888 文件'), findsWidgets);
    expect(find.textContaining('（只读）'), findsWidgets, reason: 'ro- 前缀要标出来');
    expect(find.textContaining('（已撤销）'), findsWidgets, reason: '不在 htpasswd 里的要标出来');
    expect(find.textContaining('签了但没用过：phone-175'), findsOneWidget);

    // 这张卡是"凭据层"的视图，绝不能把这层的东西反露出来
    expect(find.textContaining(_token), findsNothing);
    expect(find.textContaining('apr1'), findsNothing);
    expect(find.textContaining('\$2'), findsNothing);
  });

  testWidgets('通道凭据：看不到日志的机器上说清"换哪条看"', (tester) async {
    final seen = <String>[];
    final client = MockClient((req) async {
      final action = req.url.path.split('/').where((s) => s.isNotEmpty).last;
      seen.add(action);
      if (action == 'channel') {
        return http.Response(
            jsonEncode({
              'available': false,
              'logPath': '/www/wwwlogs/box-ops-access.log',
              'reason': '这台机器上没有通道访问日志（它由边缘机写）',
              'hint': '换到 hpa888 那条看',
              'windowDays': 7,
            }),
            200,
            headers: _jsonHeaders);
      }
      if (action == 'capabilities') {
        return http.Response(jsonEncode({'admin': true, 'write': false}),
            200, headers: _jsonHeaders);
      }
      return http.Response('{}', 200, headers: _jsonHeaders);
    });
    await _pump(tester, _settings(), client);

    expect(find.textContaining('这台机器上没有通道访问日志'), findsOneWidget);
    expect(find.textContaining('换到 hpa888 那条看'), findsOneWidget);
  });

  testWidgets('切到另一台机器：按新机器的地址/令牌重新拉', (tester) async {
    final seenA = <String>[];
    await _pump(tester, _settings(), _api(seen: seenA));
    expect(seenA, isNotEmpty);

    // 同一台页签换成"另一台"（地址不同）→ didUpdateWidget 必须重拉。
    final seenB = <String>[];
    await _pump(
      tester,
      _settings(token: 'tok-other', apiUrl: 'https://box.hpa888.top/opsapi175'),
      _api(seen: seenB),
    );
    expect(seenB, contains('overview'));
  });
}
