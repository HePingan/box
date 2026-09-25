@Tags(['live'])

// C4：运维通道收口的 live 守卫 —— "密钥类路径"必须不可达。
//
// 为什么必须有这条：C4 的收益全在"看不到"上，而"看不到"是**没有别的证据**的那类结论
// （没人会去检查一个自己看不见的东西）。所以把清单固化成用例，任何一次 rgclone 参数、
// 单元文件、接入脚本的改动都会被它抓到。
//
// 背景（2026-09-25 实测）：整盘 serve 意味着任一口令都能下载
//   * 175：box-release.p12（**发布签名库**）+ 其口令 + 清单签名密钥 + **主服务端那只口令**
//     + /root/.ssh/hermes-target（**连主服务端的私钥**）
//   * 主服务端：update-server 管理员口令 / .env / 清单密钥 / /etc/shadow
//   → 能签一个假 APK 发给全部用户（整条发布链失守）。
//
//   OPS_BASE=https://box.hpa888.top/dav      OPS_USER=boxops OPS_PASS=... \
//   flutter test --tags live test/features/extensions/server_ops/ops_webdav_denylist_live_test.dart
//   （175 那条把 OPS_BASE 换成 .../dav175、口令换成 175 的）
//
// 凭据不进仓库、不进 CI：没给 OPS_* 时整组 skip。
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:box/features/extensions/plugins/remote_storage/application/remote_storage_service.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/webdav_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// 该被挡住的（两台机器上真实存在过、且都属"密钥类"）。
const denyPaths = <String>[
  '/root/.secrets/box-release.p12',
  '/root/.secrets/box-release-keystore-password',
  '/root/.secrets/box-ops-webdav.password',
  '/root/.secrets/box-ops175-webdav.password',
  '/root/.secrets/box-monitor-snapshot-token',
  '/root/.secrets/box-update-server.admin_password',
  '/root/.secrets/box-update-server.env',
  '/root/.secrets/box-update-manifest-sign-secret',
  '/root/.ssh/hermes-target',
  '/root/.ssh/id_ed25519',
  '/root/.ssh/id_target_175',
  '/root/.hermes/.env',
  '/etc/shadow',
  '/etc/gshadow',
];

/// 不该被挡的对照：整盘的其余部分照旧（这是"整个盘"这条需求的守门人）。
const allowPaths = <String>[
  '/etc/hostname',
  '/etc/passwd',
  '/etc/sudoers',
  '/root/.bashrc',
];

/// 列表里也不该出现这些名字（挡的是路径，而名字本身也是信息）。
const hiddenNames = <String>['.secrets', '.ssh', '.hermes', '.acme.sh', '.docker'];

void main() {
  final base = Platform.environment['OPS_BASE'] ?? '';
  final user = Platform.environment['OPS_USER'] ?? '';
  final pass = Platform.environment['OPS_PASS'] ?? '';
  final missing = (base.isEmpty || user.isEmpty || pass.isEmpty)
      ? '未提供 OPS_BASE/OPS_USER/OPS_PASS —— 跳过收口 live 测试'
      : null;

  late WebdavClient dav;

  setUpAll(() {
    dav = WebdavClient(
      baseUrl: base,
      username: user,
      password: pass,
      transport: DioWebdavTransport(allowBadCert: false, badCertHost: ''),
    );
  });

  group('运维通道收口（C4）', () {
    test('密钥类路径一律不可达', () async {
      final leaked = <String>[];
      for (final p in denyPaths) {
        if (await dav.exists(p)) leaked.add(p);
      }
      expect(leaked, isEmpty, reason: '这些路径还能读到：$leaked');
    }, skip: missing);

    test('整盘的其余部分照旧（对照，防止收口收过头）', () async {
      final blocked = <String>[];
      for (final p in allowPaths) {
        if (!await dav.exists(p)) blocked.add(p);
      }
      expect(blocked, isEmpty, reason: '这些普通路径被误挡了：$blocked');
    }, skip: missing);

    test('目录列表不泄露密钥类名字', () async {
      for (final parent in <String>['/root', '/etc']) {
        final names = (await dav.list(parent)).map((e) => e.name).toSet();
        final hits = hiddenNames.where(names.contains).toList();
        expect(hits, isEmpty, reason: '$parent 列表里还看得到：$hits');
      }
    }, skip: missing);

    test('根目录仍可列举（收口没把通道本身弄坏）', () async {
      final probe = await dav.probe();
      expect(probe.rootListable, isTrue, reason: probe.errorMessage ?? '根目录列不出来');
      expect(probe.rootEntryCount, greaterThan(0));
    }, skip: missing);
  });
}
