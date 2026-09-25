// C2 只读运维 API 的 **live** 用例：直接打两台真机的公网入口。
//
// 与文件通道那条 live 用例同一个口径：跑它要显式给地址与令牌（CI 默认 --exclude-tags live）：
//
//   OPS_API_BASE=https://box.hpa888.top/opsapi175 \
//   OPS_API_TOKEN=$(cat /root/.secrets/box-ops-api-token-175) \
//   flutter test --tags live test/features/extensions/server_ops/ops_api_live_test.dart
//
// 守的是"服务器上真的收口了、真的在用令牌"：正常动作要通，**拒绝路径必须拒绝**
// （错令牌 401、白名单外日志 403、密钥目录 403、未知动作 404）。
@Tags(['live'])
library;

import 'dart:io';

import 'package:box/features/extensions/plugins/server_ops/server_ops_api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final base = Platform.environment['OPS_API_BASE'] ?? '';
  final token = Platform.environment['OPS_API_TOKEN'] ?? '';
  final missing = base.isEmpty || token.isEmpty;

  OpsApiClient client({String? tokenOverride, String? baseOverride}) => OpsApiClient(
        baseUrl: baseOverride ?? base,
        token: tokenOverride ?? token,
      );

  group('C2 只读接口 live（$base）', () {
    test('health 通，且带回版本', () async {
      final c = client();
      addTearDown(c.close);
      final d = await c.call('health');
      expect(d['ok'], isTrue);
      expect(d['version'], isNotEmpty);
    }, timeout: const Timeout(Duration(seconds: 40)));

    test('overview：内核/负载/内存/磁盘都在', () async {
      final c = client();
      addTearDown(c.close);
      final ov = await c.overview();
      expect(ov.hostname, isNotEmpty);
      expect(ov.cores, greaterThan(0));
      expect(ov.memTotal, greaterThan(0));
      expect(ov.disks, isNotEmpty);
    }, timeout: const Timeout(Duration(seconds: 40)));

    test('进程 / 服务 / 端口 / 目录占用 / 登录记录：都能取到', () async {
      final c = client();
      addTearDown(c.close);
      expect((await c.processes(limit: 5)).length, lessThanOrEqualTo(5));
      final services = await c.services(limit: 30);
      expect(services, isNotEmpty, reason: 'systemd 机器上至少能列到一些服务');
      expect((await c.ports()).isNotEmpty, isTrue);
      expect((await c.diskUsage('/var/log')), isNotEmpty);
      final sessions = await c.sessions();
      expect(sessions.logins.length + sessions.failedLogins.length,
          greaterThanOrEqualTo(0));
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('错令牌 / 没令牌：一律 401（不能给出半个字的数据）', () async {
      for (final bad in ['', 'not-a-real-token']) {
        final c = client(tokenOverride: bad);
        addTearDown(c.close);
        await expectLater(
          c.overview(),
          throwsA(isA<OpsApiException>()
              .having((e) => e.kind, 'kind', OpsApiErrorKind.unauthorized)),
          reason: '令牌="$bad" 必须被拒',
        );
      }
    }, timeout: const Timeout(Duration(seconds: 40)));

    test('拒绝路径：白名单外日志 403、密钥目录 403、未知动作 404', () async {
      final c = client();
      addTearDown(c.close);
      for (final path in ['/etc/shadow', '/root/.secrets/box-ops-api-tokens.json']) {
        await expectLater(
          c.logs(path),
          throwsA(isA<OpsApiException>()
              .having((e) => e.kind, 'kind', OpsApiErrorKind.forbidden)),
          reason: '$path 不该能读',
        );
      }
      await expectLater(
        c.diskUsage('/root/.secrets'),
        throwsA(isA<OpsApiException>()
            .having((e) => e.kind, 'kind', OpsApiErrorKind.forbidden)),
      );
      await expectLater(
        c.call('rm-rf'),
        throwsA(isA<OpsApiException>()
            .having((e) => e.kind, 'kind', OpsApiErrorKind.notFound)),
      );
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('审计里留了痕迹：刚才那几次调用都在（含被拒的）', () async {
      final c = client();
      addTearDown(c.close);
      final items = await c.audit(limit: 50);
      expect(items, isNotEmpty, reason: 'admin 令牌才读得到审计；这里给的应该是 admin');
      expect(items.any((e) => e.action == 'overview'), isTrue);
      expect(items.any((e) => e.status == 401 || e.status == 403), isTrue,
          reason: '被拒绝的调用也要留痕，否则审计等于没做');
      // 审计里不该出现令牌本身。
      for (final e in items) {
        expect(e.tokenLabel.contains(token), isFalse);
      }
    }, timeout: const Timeout(Duration(seconds: 40)));
  }, skip: missing ? '需要 OPS_API_BASE / OPS_API_TOKEN（live）' : null);

  test('写档：这台机器的令牌能写，且拒绝路径都挡得住（不真写东西）', () async {
    final c = client();
    addTearDown(c.close);

    final caps = await c.capabilities();
    expect(caps.write, isTrue, reason: 'App 用的令牌要带 write 作用域');
    expect(caps.writeActions, contains('service'));
    expect(caps.writeActions, contains('extract'));

    // 受保护路径：一律拒绝（不会真改任何东西）。
    await expectLater(
      c.mkdir('/root/.secrets/box-ops-live-should-never-exist'),
      throwsA(isA<OpsApiException>()),
    );

    // 自杀单元：停 sshd 要被拒。
    await expectLater(
      c.serviceOp('sshd.service', 'stop'),
      throwsA(isA<OpsApiException>()),
    );

    // 参数不合规：单元名带路径 → 直接 400（不是"执行了才发现"）。
    await expectLater(
      c.serviceOp('../../etc/passwd', 'restart'),
      throwsA(isA<OpsApiException>()),
    );

    // 不存在的单元 → 404。
    await expectLater(
      c.serviceOp('no-such-unit-xyz.service', 'restart'),
      throwsA(isA<OpsApiException>()),
    );
  });

}
