@Tags(['live'])
library;

// 运维通道（box-ops WebDAV）真服务端契约测试。
//
// 为什么必须用"仓库里那个真客户端"跑：C1 的收益就是让「远端存储」插件当场能用，
// 而 curl 只能验证协议本身，验证不了客户端的 href 相对化（_relativizeHref）、
// MOVE 的 Destination 绝对 URL、Overwrite 语义这几条真实路径 —— 它们在 2026-09-25
// 的部署里各踩过一个坑（nginx 原生 DAV 对 https 绝对 URL 直接判 400）。
// DioWebdavTransport 就是插件生产用的传输层，这里不做替身。
//
//   OPS_BASE=https://box.hpa888.top/dav OPS_USER=boxops OPS_PASS=... \
//   flutter test --tags live test/features/extensions/remote_storage/ops_webdav_live_test.dart
//
// 凭据不进仓库、不进 CI：没给 OPS_* 环境变量时整组 skip。
import 'dart:convert';
import 'dart:io';

import 'package:box/features/extensions/plugins/remote_storage/application/remote_storage_service.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/webdav_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证用目录（服务端整盘可见，所以放在 /tmp 下，跑完即删）。
const verifyDir = '/tmp/box-ops-verify';

void main() {
  final base = Platform.environment['OPS_BASE'] ?? '';
  final user = Platform.environment['OPS_USER'] ?? '';
  final pass = Platform.environment['OPS_PASS'] ?? '';
  final missing = (base.isEmpty || user.isEmpty || pass.isEmpty)
      ? '未提供 OPS_BASE/OPS_USER/OPS_PASS —— 跳过运维通道 live 测试'
      : null;

  late WebdavClient dav;
  late Directory scratch;

  setUpAll(() async {
    dav = WebdavClient(
      baseUrl: base,
      username: user,
      password: pass,
      transport: DioWebdavTransport(allowBadCert: false, badCertHost: ''),
    );
    scratch = await Directory.systemTemp.createTemp('box-ops-verify-');
  });

  tearDownAll(() async {
    try {
      if (await dav.exists(verifyDir)) {
        await dav.delete(verifyDir);
      }
    } catch (_) {
      // 清理失败不该掩盖真正的断言结果。
    }
    if (scratch.existsSync()) await scratch.delete(recursive: true);
  });

  group('运维通道 WebDAV（真服务端）', () {
    test('probe 能列根目录且 DAV 头正常', () async {
      final probe = await dav.probe();
      expect(
        probe.rootListable,
        isTrue,
        reason: probe.errorMessage ?? '根目录列不出来',
      );
      expect(probe.rootEntryCount, greaterThan(0));
    });

    test('整盘根可见（/ 下应有 etc / home / root）', () async {
      final entries = await dav.list('/');
      final names = entries.map((e) => e.name).toSet();
      expect(names, containsAll(<String>['etc', 'home', 'root']));
    });

    test('root 身份才能读的路径也可读（/etc/shadow 与 /root 全树）', () async {
      // 这条是"整盘"与"只有 www 能看的半盘"的分界线：主 nginx worker 是 www 用户，
      // 这两处会 403；只有以 root 跑的专用实例才读得到。
      // /etc/shadow 是 0000，/root 是 0700 —— 都是 www 读不到的典型。
      expect(await dav.exists('/etc/shadow'), isTrue);
      final shadow = await dav.readUpTo('/etc/shadow', 512);
      expect(shadow.bytes, isNotEmpty, reason: '/etc/shadow 应能读出内容（root 身份）');

      // 顺带覆盖"目录不带尾斜杠会 301 → 客户端要能跟过去"这条（内层 nginx 曾把
      // 重定向写成 http://域名:8081/...，真机上就是导航进目录即超时）。
      final rootEntries = await dav.list('/root');
      expect(rootEntries, isNotEmpty, reason: '/root 下应能列出条目');
    });

    test('上传 → 列表/大小 → 下载逐字节一致 → 重命名 → 删除', () async {
      await dav.createDirectory(verifyDir);

      final payload = List<int>.generate(200000, (i) => i % 251);
      final local = File('${scratch.path}/payload.bin');
      await local.writeAsBytes(payload);

      await dav.uploadFrom(local, '$verifyDir/payload.bin');

      final entries = await dav.list(verifyDir);
      final uploaded = entries.where((e) => e.name == 'payload.bin').toList();
      expect(uploaded, hasLength(1), reason: '列表里应恰好有一条 payload.bin');
      expect(uploaded.single.size, payload.length);
      expect(uploaded.single.isDirectory, isFalse);

      final head = await dav.head('$verifyDir/payload.bin');
      expect(head.contentLength, payload.length);

      final back = File('${scratch.path}/back.bin');
      await dav.downloadTo('$verifyDir/payload.bin', back);
      expect(await back.readAsBytes(), equals(payload), reason: '下载必须逐字节一致');

      await dav.move('$verifyDir/payload.bin', '$verifyDir/renamed.bin');
      expect(await dav.exists('$verifyDir/payload.bin'), isFalse);
      expect(await dav.exists('$verifyDir/renamed.bin'), isTrue);

      await dav.delete('$verifyDir/renamed.bin');
      expect(await dav.exists('$verifyDir/renamed.bin'), isFalse);

      await dav.delete(verifyDir);
      expect(await dav.exists(verifyDir), isFalse);
    });

    test('特殊字符文件名（A5）：中文 / 空格 / + / # / % 往返不丢真名', () async {
      // 这几种字符漏编码时的真机表现最难自查：上传报 201、内容也对，但列表里
      // 名字变了（%25 显示成 %2525 这类双重编码），或者干脆 400。
      // 2026-09-25 的 curl 实测结论是"正确百分号编码后服务端存回原名"——
      // 这条用例就是把那个结论固化下来，防止 encodeRemotePath 被改坏。
      await dav.createDirectory(verifyDir);
      final names = <String>[
        '运维 测试 +.txt', // 中文 + 空格 + 加号
        'a#b.txt', // 井号：URL 里是 fragment 分隔符，漏编码会被截断
        'a%b.txt', // 百分号：漏编码 + 服务端再编码 = %25 变 %2525
        '空格 在 中间.txt',
      ];

      for (final name in names) {
        final text = 'content<$name>${DateTime.now().microsecondsSinceEpoch}';
        final local = File('${scratch.path}/special-up.txt');
        await local.writeAsString(text);
        await dav.uploadFrom(local, '$verifyDir/$name');

        // ① PROPFIND 列表里必须回读**原名**（不是编码后的形态）。
        final entries = await dav.list(verifyDir);
        final actual = entries.map((e) => e.name).toList();
        expect(
          actual.where((n) => n == name),
          hasLength(1),
          reason: '列表里应有原名「$name」，实际是 $actual',
        );
        expect(
          entries.firstWhere((e) => e.name == name).size,
          utf8.encode(text).length,
          reason: '「$name」的大小必须与上传字节数一致',
        );

        // ② GET 取回内容逐字节一致。
        final back = File('${scratch.path}/special-back.txt');
        await dav.downloadTo('$verifyDir/$name', back);
        expect(
          await back.readAsString(),
          text,
          reason: '「$name」取回内容必须与上传一致',
        );

        // ③ DELETE 用原名删得掉。
        await dav.delete('$verifyDir/$name');
        expect(
          await dav.exists('$verifyDir/$name'),
          isFalse,
          reason: '「$name」应当被删掉',
        );
      }

      expect(
        (await dav.list(verifyDir)).where((e) => e.name.endsWith('.txt')),
        isEmpty,
        reason: '每个名字都应删干净，不该留下编码后的残骸',
      );
      await dav.delete(verifyDir);
      expect(await dav.exists(verifyDir), isFalse);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('覆盖保护靠"先 exists() 预检"（服务端不一定实现 Overwrite:F）', () async {
      // 实测（rclone 后端）：MOVE 带 `Overwrite: F` 且目标已存在时仍返回 201 覆盖，
      // 不实现 RFC 4918 的 412。真正兜底的是服务层
      // （remote_storage_service.dart 的 renameEntry / moveEntry 都先 exists(target)
      //  再抛 conflict），所以这里验证的是**预检原语本身可靠**，而不是服务端语义。
      // 换服务端时这条仍应通过 —— 它断言的是我们自己依赖的那个能力。
      await dav.createDirectory(verifyDir);
      await File('${scratch.path}/a.txt').writeAsString('a');
      await File('${scratch.path}/b.txt').writeAsString('b');
      await dav.uploadFrom(File('${scratch.path}/a.txt'), '$verifyDir/a.txt');
      await dav.uploadFrom(File('${scratch.path}/b.txt'), '$verifyDir/b.txt');

      expect(await dav.exists('$verifyDir/b.txt'), isTrue,
          reason: '目标存在必须能被检测到（服务层据此拒绝重命名）');
      expect(await dav.exists('$verifyDir/nope.txt'), isFalse,
          reason: '不存在的目标必须为 false，否则用户永远改不了名');

      // 目录也要能探测（HEAD 对无尾斜杠的集合返回 405，客户端会退回 PROPFIND）。
      expect(await dav.exists(verifyDir), isTrue);

      await dav.delete('$verifyDir/a.txt');
      await dav.delete('$verifyDir/b.txt');
      await dav.delete(verifyDir);
    });
  }, skip: missing);
}
