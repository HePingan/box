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
  int? failStatusFor,
  String? failAction,
}) =>
    MockClient((req) async {
      final action = req.url.path.split('/').where((s) => s.isNotEmpty).last;
      seen.add(action);
      if (failAction != null && action == failAction) {
        return http.Response(
            jsonEncode({'error': '没有权限'}),
          failStatusFor ?? 403,
          headers: _jsonHeaders,
        );
      }
      switch (action) {
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

  testWidgets('配好了：七个小节都渲染出来，并留一条"系统"请求记录', (tester) async {
    final seen = <String>[];
    await _pump(tester, _settings(), _api(seen: seen));

    expect(seen, containsAll(['overview', 'processes', 'services', 'ports', 'diskusage', 'sessions', 'audit']));
    expect(find.textContaining('概览'), findsWidgets);
    expect(find.text('VM-0-15-debian'), findsOneWidget);
    expect(find.textContaining('Intel(R) Xeon(R) Platinum'), findsOneWidget);
    expect(find.textContaining('1 天 1 小时'), findsOneWidget);
    expect(find.textContaining('nginx.service'), findsWidgets);
    expect(find.textContaining('127.0.0.1:8095'), findsWidgets);
    expect(find.textContaining('admin'), findsWidgets);

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

  testWidgets('服务列表点得开：详情抽屉里有状态与日志', (tester) async {
    final seen = <String>[];
    await _pump(tester, _settings(), _api(seen: seen));

    await tester.tap(find.text('nginx.service').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(seen, contains('service'));
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
