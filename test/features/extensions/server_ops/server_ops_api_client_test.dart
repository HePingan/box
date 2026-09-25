// 服务器运维插件：只读 API 客户端用例（C2）。
//
// 这个文件守的是**身份模型与错误翻译**，不是 HTTP 细节：
//   * 令牌只进请求头，绝不进错误文案（面板会被截屏）；
//   * 401 的文案必须把"口令/令牌是两回事"讲清楚 —— 这是 291 那个真 bug
//     （地址和口令不是同一台）在 C2 上的同类坑；
//   * 服务端字段缺了/多了解析都不炸（旧包对新服务端）。
import 'dart:convert';

import 'package:box/features/extensions/plugins/server_ops/server_ops_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 记录请求并回固定响应的假客户端。
class _Recorder {
  final List<http.Request> requests = [];

  MockClient respond(
    Object? body, {
    int status = 200,
    Duration? delay,
  }) =>
      MockClient((req) async {
        requests.add(req);
        if (delay != null) await Future<void>.delayed(delay);
        return http.Response(
          body is String ? body : jsonEncode(body ?? const {}),
          status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
}

const String _token = 'tok-abcdefghijklmnop';

void main() {
  group('身份与地址', () {
    test('没填地址就不发请求，直接给引导', () async {
      final rec = _Recorder();
      final c = OpsApiClient(baseUrl: '', token: _token, client: rec.respond(const {}));
      await expectLater(c.overview(), throwsA(isA<OpsApiException>()));
      expect(rec.requests, isEmpty);
    });

    test('没填令牌就不发请求，且文案指向设置', () async {
      final rec = _Recorder();
      final c = OpsApiClient(baseUrl: 'https://x/opsapi', token: '  ', client: rec.respond(const {}));
      OpsApiException? e;
      try {
        await c.overview();
      } on OpsApiException catch (x) {
        e = x;
      }
      expect(e?.kind, OpsApiErrorKind.unauthorized);
      expect(e?.message, contains('设备令牌'));
      expect(rec.requests, isEmpty);
    });

    test('令牌放 Authorization 头，地址尾斜杠被去掉', () async {
      final rec = _Recorder();
      final c = OpsApiClient(
        baseUrl: 'https://box.hpa888.top/opsapi175///',
        token: _token,
        client: rec.respond({'hostname': 'h'}),
      );
      await c.overview();
      expect(rec.requests.single.url.toString(), 'https://box.hpa888.top/opsapi175/overview');
      expect(rec.requests.single.headers['Authorization'], 'Bearer $_token');
    });

    test('令牌不会出现在任何错误文案里', () async {
      for (final pair in [
        [401, '{"error":"令牌无效或缺失"}'],
        [403, '{"error":"需要 admin 令牌"}'],
        [500, '{"error":"boom"}'],
        ['x', 'not json'],
      ]) {
        final rec = _Recorder();
        final c = OpsApiClient(
          baseUrl: 'https://x/opsapi',
          token: _token,
          client: rec.respond(pair[1] as String, status: pair[0] is int ? pair[0] as int : 200),
        );
        try {
          await c.overview();
        } on OpsApiException catch (e) {
          expect(e.message.contains(_token), isFalse, reason: '文案里出现了令牌：${e.message}');
        }
      }
    });
  });

  group('错误翻译', () {
    Future<OpsApiErrorKind> kindOf(http.Client client) async {
      final c = OpsApiClient(baseUrl: 'https://x/opsapi', token: _token, client: client);
      try {
        await c.overview();
      } on OpsApiException catch (e) {
        return e.kind;
      }
      return OpsApiErrorKind.server;
    }

    test('401 → unauthorized，并点明口令与令牌是两回事', () async {
      final rec = _Recorder();
      final c = OpsApiClient(baseUrl: 'https://x/opsapi', token: _token, client: rec.respond('{"error":"令牌无效或缺失"}', status: 401));
      OpsApiException? e;
      try {
        await c.overview();
      } on OpsApiException catch (x) {
        e = x;
      }
      expect(e?.kind, OpsApiErrorKind.unauthorized);
      expect(e?.isAuth, isTrue);
      expect(e?.message, contains('令牌无效或已被撤销'));
      expect(e?.message, contains('不是一回事'));
    });

    test('403/404/429/500 各自归一', () async {
      expect(await kindOf(_Recorder().respond('{"error":"要 admin"}', status: 403)),
          OpsApiErrorKind.forbidden);
      expect(await kindOf(_Recorder().respond('{}', status: 404)), OpsApiErrorKind.notFound);
      expect(await kindOf(_Recorder().respond('{}', status: 429)), OpsApiErrorKind.rateLimited);
      expect(await kindOf(_Recorder().respond('{}', status: 502)), OpsApiErrorKind.server);
    });

    test('连不上 → network（文案不提 URL/令牌）', () async {
      final c = OpsApiClient(
        baseUrl: 'https://x/opsapi',
        token: _token,
        client: MockClient((_) async => throw const SocketLikeError()),
      );
      OpsApiException? e;
      try {
        await c.overview();
      } on OpsApiException catch (x) {
        e = x;
      }
      expect(e?.kind, OpsApiErrorKind.network);
      expect(e?.message, contains('连不上'));
    });

    test('超时 → timeout', () async {
      final rec = _Recorder();
      final c = OpsApiClient(
        baseUrl: 'https://x/opsapi',
        token: _token,
        timeout: const Duration(milliseconds: 30),
        client: rec.respond({'hostname': 'h'}, delay: const Duration(milliseconds: 300)),
      );
      OpsApiException? e;
      try {
        await c.overview();
      } on OpsApiException catch (x) {
        e = x;
      }
      expect(e?.kind, OpsApiErrorKind.timeout);
    });

    test('200 但不是 JSON → decode', () async {
      final rec = _Recorder();
      final c = OpsApiClient(baseUrl: 'https://x/opsapi', token: _token, client: rec.respond('<html>'));
      OpsApiException? e;
      try {
        await c.overview();
      } on OpsApiException catch (x) {
        e = x;
      }
      expect(e?.kind, OpsApiErrorKind.decode);
    });
  });

  group('解析', () {
    test('overview：完整字段 + 缺字段容错', () async {
      final rec = _Recorder();
      final c = OpsApiClient(
        baseUrl: 'https://x/opsapi',
        token: _token,
        client: rec.respond({
          'hostname': 'VM-175',
          'os': {'pretty': 'Debian GNU/Linux 12 (bookworm)', 'kernel': '6.6.0'},
          'uptimeSeconds': 90061,
          'load': {'load1': 0.52, 'load5': 0.4, 'load15': 0.3},
          'cpu': {'model': 'Intel Xeon', 'cores': 4},
          'memory': {'memTotal': 8000000000, 'memUsed': 3300000000, 'swapTotal': 0, 'swapUsed': 0},
          'disks': [{'mount': '/', 'size': '59G', 'used': '46G', 'avail': '10G', 'usePercent': '78%'}],
        }),
      );
      final ov = await c.overview();
      expect(ov.hostname, 'VM-175');
      expect(ov.osPretty, contains('Debian'));
      expect(ov.cores, 4);
      expect(ov.memUsedPercent, closeTo(41.25, 0.1));
      expect(ov.swapUsedPercent, 0);
      expect(ov.disks.single.usePercent, '78%');
      expect(ov.loadPerCore, closeTo(0.13, 0.001));

      final empty = OpsOverview.fromJson(const {});
      expect(empty.hostname, isEmpty);
      expect(empty.memUsedPercent, 0);
      expect(empty.disks, isEmpty);
    });

    test('列表动作：条数与字段都对', () async {
      final rec = _Recorder();
      final c = OpsApiClient(
        baseUrl: 'https://x/opsapi',
        token: _token,
        client: MockClient((req) async {
          rec.requests.add(req);
          switch (req.url.path.split('/').last) {
            case 'processes':
              return http.Response(
                jsonEncode({
                  'count': 2,
                  'processes': [
                    {'pid': 1, 'user': 'root', 'cpuPercent': 12.5, 'memPercent': 3.1, 'rssKb': 2048, 'elapsed': '10-01:02', 'name': 'systemd', 'args': '/sbin/init'},
                    {'pid': 42, 'user': 'www', 'cpuPercent': 9, 'memPercent': 1.5, 'rssKb': 1024, 'elapsed': '01:00', 'name': 'nginx', 'args': 'nginx: worker'},
                  ],
                }),
                200,
              );
            case 'ports':
              return http.Response(
                jsonEncode({
                  'count': 1,
                  'listeners': [{'proto': 'tcp', 'state': 'LISTEN', 'local': '127.0.0.1:8095', 'process': 'python3'}],
                }),
                200,
              );
            case 'diskusage':
              return http.Response(
                jsonEncode({'rows': [{'size': '1.2G', 'path': '/var/log'}, {'size': '900M', 'path': '/var/log/journal'}]}),
                200,
              );
            case 'audit':
              return http.Response(
                jsonEncode({
                  'items': [{'at': '2026-09-25T22:00:00+08:00', 'action': 'overview', 'token': 'box-app-175', 'ip': '1.2.3.4', 'status': 200, 'ms': 31}],
                }),
                200,
              );
            default:
              return http.Response('{}', 200);
          }
        }),
      );
      final procs = await c.processes(sort: 'mem', limit: 5);
      expect(procs.length, 2);
      expect(procs.first.pid, 1);
      expect(procs.first.cpuPercent, 12.5);
      expect(procs.first.args, contains('init'));
      expect(rec.requests.first.url.query, contains('sort=mem'));
      expect(rec.requests.first.url.query, contains('limit=5'));

      final ports = await c.ports();
      expect(ports.single.local, '127.0.0.1:8095');
      expect(ports.single.process, 'python3');

      final du = await c.diskUsage('/var/log');
      expect(du.length, 2);
      expect(du.first.size, '1.2G');

      final audit = await c.audit(limit: 10);
      expect(audit.single.isOk, isTrue);
      expect(audit.single.tokenLabel, 'box-app-175');
      expect(audit.single.note, isEmpty);
    });

    test('服务详情与日志 tail', () async {
      final c = OpsApiClient(
        baseUrl: 'https://x/opsapi',
        token: _token,
        client: MockClient((req) async {
          if (req.url.path.endsWith('service')) {
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
            );
          }
          return http.Response(
            jsonEncode({'path': '/var/log/nginx/access.log', 'lines': 3, 'truncated': false, 'content': 'a\nb\nc'}),
            200,
          );
        }),
      );
      final d = await c.service('nginx.service');
      expect(d.activeState, 'active');
      expect(d.memoryBytes, 45678901);
      expect(d.journal, contains('started'));

      final log = await c.logs('/var/log/nginx/access.log', lines: 3);
      expect(log.lines, 3);
      expect(log.truncated, isFalse);
      expect(log.content.split('\n'), ['a', 'b', 'c']);
    });

    test('services 支持过滤词，且带上限', () async {
      final rec = _Recorder();
      final c = OpsApiClient(
        baseUrl: 'https://x/opsapi',
        token: _token,
        client: rec.respond({'units': [{'unit': 'nginx.service', 'active': 'active', 'sub': 'running', 'enabled': 'enabled', 'description': 'nginx'}]}),
      );
      final units = await c.services(filter: ' nginx ', limit: 50);
      expect(units.single.unit, 'nginx.service');
      expect(rec.requests.single.url.queryParameters['q'], 'nginx');
      expect(rec.requests.single.url.queryParameters['limit'], '50');
    });

    test('sessions：登录与失败登录两种都解析', () async {
      final rec = _Recorder();
      final c = OpsApiClient(
        baseUrl: 'https://x/opsapi',
        token: _token,
        client: rec.respond({
          'logins': [{'user': 'root', 'tty': 'pts/0', 'from': '1.2.3.4', 'at': 'Fri Sep 25 20:00'}],
          'failedLogins': [{'user': 'admin', 'tty': 'ssh:notty', 'from': '9.9.9.9', 'at': 'Fri Sep 25 19:00'}],
        }),
      );
      final s = await c.sessions();
      expect(s.logins.single['user'], 'root');
      expect(s.failedLogins.single['user'], 'admin');
    });
  });

  group('格式化', () {
    test('formatBytes', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(2048), '2.0 KB');
      expect(formatBytes(1024 * 1024 * 1536), '1.5 GB');
      expect(formatBytes(8 * 1024 * 1024 * 1024), '8.0 GB');
    });

    test('formatUptime', () {
      expect(formatUptime(0), '刚起');
      expect(formatUptime(90061), '1 天 1 小时');
      expect(formatUptime(3700), '1 小时 1 分钟');
      expect(formatUptime(90), '1 分钟');
      expect(formatUptime(30), '0 分钟');
    });
  });

  group('写档（要 write 作用域）', () {
    OpsApiClient clientWith(Object body, {int status = 200}) {
      final rec = _Recorder();
      return OpsApiClient(
        baseUrl: 'https://box.hpa888.top/opsapi175',
        token: _token,
        client: rec.respond(body, status: status),
      );
    }

    test('capabilities：把"能不能写、哪些动作不能做"解析出来', () async {
      final c = clientWith(const {
        'hostname': 'VM-0-15-debian',
        'version': '1.1.0',
        'admin': true,
        'write': true,
        'writeActions': ['service', 'extract'],
        'selfDestructiveUnits': ['sshd.service'],
        'protectedPaths': ['/root/.secrets'],
      });

      final caps = await c.capabilities();
      expect(caps.hostname, 'VM-0-15-debian');
      expect(caps.write, isTrue);
      expect(caps.writeActions, contains('extract'));
      expect(caps.protectedPaths, contains('/root/.secrets'));
      // 自杀单元要在界面上就把按钮禁掉，而不是点了才知道。
      expect(caps.selfDestructiveUnits, contains('sshd.service'));
      expect(caps.stopBlockedReason('sshd.service'), isNotNull);
      expect(caps.stopBlockedReason('nginx.service'), isNull);
    });

    test('写动作发的是 POST，参数进 JSON 体，令牌仍在请求头', () async {
      final rec = _Recorder();
      final c = OpsApiClient(
        baseUrl: 'https://box.hpa888.top/opsapi175',
        token: _token,
        client: rec.respond(const {'unit': 'nginx.service', 'activeState': 'active'}),
      );

      await c.serviceOp('nginx.service', 'restart');
      final req = rec.requests.single;
      expect(req.method, 'POST');
      expect(req.url.path, endsWith('/service'));
      expect(jsonDecode(req.body)['unit'], 'nginx.service');
      expect(jsonDecode(req.body)['op'], 'restart');
      expect(req.headers['Authorization'], startsWith('Bearer '));
    });

    test('客户端封装与服务端参数一一对应：mkdir / chmod / chown / extract', () async {
      final rec = _Recorder();
      final c = OpsApiClient(
        baseUrl: 'https://box.hpa888.top/opsapi175',
        token: _token,
        client: rec.respond(const {'path': '/tmp/x', 'count': 1, 'mode': '700'}),
      );

      await c.mkdir('/tmp/x');
      await c.chmod('/tmp/x', '700', recursive: true);
      await c.chown('/tmp/x', owner: 'www', group: 'www');
      await c.extract('/tmp/x/a.zip', dest: '/tmp/x');

      final bodies = rec.requests
          .map((r) => jsonDecode(r.body) as Map<String, dynamic>)
          .toList();
      expect(bodies[0], {'path': '/tmp/x'});
      expect(bodies[1]['mode'], '700');
      expect(bodies[1]['recursive'], isTrue);
      expect(bodies[2]['owner'], 'www');
      expect(bodies[3]['path'], '/tmp/x/a.zip');
      expect(bodies[3]['dest'], '/tmp/x');
    });

    test('没有写作用域（403）时把服务端原话给出来，不吞成"网络错"', () async {
      final c = clientWith(
        const {'error': '这把令牌没有写作用域，写动作一律拒绝（要用 --write 重签）'},
        status: 403,
      );

      await expectLater(
        c.serviceOp('nginx.service', 'stop'),
        throwsA(isA<OpsApiException>().having(
          (e) => e.message,
          'message',
          contains('没有写作用域'),
        )),
      );
    });
  });
}

/// 假一个"连不上"的异常（不引 dart:io，widget 测试里也能用）。
class SocketLikeError implements Exception {
  const SocketLikeError();

}
