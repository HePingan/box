@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:box/features/extensions/plugins/github_accel/github_accel_link.dart';
import 'package:box/features/extensions/plugins/github_accel/github_accel_probe.dart';
import 'package:box/features/extensions/plugins/github_accel/github_accel_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真联网端到端验证。默认不随 `flutter test` 跑（带 `live` 标签），
/// CI 口径用 `--exclude-tags live`；要单独跑：
///
///   flutter test --tags live test/features/extensions/github_accel_live_e2e_test.dart
///
/// 285 P3 重写要点（原版为什么一直红）：
///  1. 原版把 `releases/latest/download/RikkaHub-2.4.15-...apk` 写死并断言 200 ——
///     上游一发新版本，这个文件名就不再属于 latest，镜像回 404/403，
///     于是"仓库一切正常"却红了一条。**外部变化不该伪装成本仓回归**。
///  2. 现在拆成两条：结构解析（只依赖 GitHub API）+ 真下字节（附件名从 API 现取，
///     经镜像线路下载），并做**分级判定**：
///     - 所有线路都连不上（DNS/连接/超时）→ `markTestSkipped` 并列出原因；
///     - 线路可达但没有一路给出真实字节 → 失败，但错误信息里逐条列出每条线路的
///       状态码/异常 —— 明确是外部行为。
void main() {
  late HttpClient client;

  setUpAll(() {
    client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  });

  tearDownAll(() => client.close(force: true));

  Future<String> fetch(String url) async {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', 'box-app');
    req.headers.set('Accept', 'application/vnd.github+json');
    final resp = await req.close();
    return resp.transform(const SystemEncoding().decoder).join();
  }

  // rikkahub/rikkahub 的真实 repo id（api.github.com 查得）。
  const signed =
      'https://release-assets.githubusercontent.com/github-production-release-asset/'
      '946702247/aaaaaaaa-bbbb-cccc-dddd-eeeeffff0000'
      '?sp=r&sig=xxx&se=2026-08-29T09%3A00%3A00Z'
      '&response-content-disposition=attachment%3B%20filename%3D'
      'RikkaHub-2.4.15-arm64-v8a.apk'
      '&response-content-type=application%2Fvnd.android.package-archive';

  test('签名长链 → 解析出可下载的稳定地址（结构，不依赖镜像可用性）', () async {
    final svc = GithubAccelService(fetch: fetch);
    final r = await svc.resolve(signed);

    // 查询失败属于外部行为（api.github.com 不可达 / gh-proxy 共享账号限流），
    // 用 message 明确写出来，而不是丢一个"期望 true 实际 false"。
    expect(r.ok, isTrue, reason: '外部原因导致查询失败: ${r.message}');

    // ignore: avoid_print
    print('  stableUrl: ${r.stableUrl}');
    // ignore: avoid_print
    print('  message: ${r.message}');

    expect(r.accelUrl, startsWith('https://gh-proxy.com/'));
    expect(r.accelUrl, contains('rikkahub/rikkahub'));
    expect(r.accelUrl, contains('RikkaHub-2.4.15-arm64-v8a.apk'));
    expect(
      r.stableUrl,
      anyOf(
        contains('/releases/latest/download/'),
        matches(RegExp(r'/releases/download/[^/]+/')),
      ),
      reason: '要么是 latest 地址，要么（更稳）是 tag 固定地址',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('真下字节：至少一条镜像线路能拿到真实 APK 字节（分级判定）', () async {
    // 1) 现取"当前最新 release"的附件名，别写死某个版本的文件名。
    const repo = 'rikkahub/rikkahub';
    String tag = '';
    String asset = '';
    try {
      final body = await fetch('https://api.github.com/repos/$repo/releases/latest');
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        tag = '${decoded['tag_name']}';
        final assets = decoded['assets'];
        if (assets is List) {
          for (final a in assets) {
            if (a is Map && '${a['name']}'.endsWith('.apk')) {
              asset = '${a['name']}';
              break;
            }
          }
        }
      }
    } catch (e) {
      markTestSkipped('取最新 release 失败（外部网络/限流），本次跳过: $e');
      return;
    }
    if (tag.isEmpty || asset.isEmpty) {
      markTestSkipped('最新 release 里没有 apk 附件（上游变了），本次跳过: tag=$tag');
      return;
    }

    final upstream = 'https://github.com/$repo/releases/download/$tag/$asset';
    final report = <String, String>{};
    var gotRealBytes = false;

    for (final mirror in GithubAccelLink.mirrors) {
      final url = '${mirror.url}/$upstream';
      try {
        final req = await client.getUrl(Uri.parse(url));
        req.headers.set('Range', 'bytes=0-262143');
        req.headers.set('User-Agent', 'box-app');
        final resp = await req.close();
        final bytes = <int>[];
        await for (final chunk in resp) {
          bytes.addAll(chunk);
          if (bytes.length >= 4) break;
        }
        final isZip = bytes.length >= 4 &&
            bytes[0] == 0x50 &&
            bytes[1] == 0x4B &&
            bytes[2] == 0x03 &&
            bytes[3] == 0x04;
        report[mirror.label] = 'HTTP ${resp.statusCode}${isZip ? ' · ZIP 魔数 ✅' : ''}';
        if (isZip) gotRealBytes = true;
      } catch (e) {
        report[mirror.label] = '连接失败: $e';
      }
    }

    // ignore: avoid_print
    print('  附件: $tag/$asset');
    for (final entry in report.entries) {
      // ignore: avoid_print
      print('  ${entry.key.padRight(18)} ${entry.value}');
    }

    if (gotRealBytes) return;

    final allUnreachable = report.values.every((v) => v.startsWith('连接失败'));
    if (allUnreachable) {
      markTestSkipped('所有镜像线路都连不上（外部网络），本次跳过: $report');
      return;
    }
    fail('镜像线路可达，但没有一路给出真实 APK 字节 —— 这是外部行为（镜像改规则/限流），'
        '不是本仓回归。逐条结果: $report');
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('真联网测速：选出的镜像确实是最快可用的那条', () async {
    // 固定 tag 的 release 资产，支持 Range，不随上游发版变化。
    const target =
        'https://github.com/rikkahub/rikkahub/releases/download/2.4.15/'
        'RikkaHub-2.4.15-arm64-v8a.apk';

    Future<MirrorSample> probeOnce(String mirror, String url) async {
      final m = mirror.endsWith('/')
          ? mirror.substring(0, mirror.length - 1)
          : mirror;
      final sw = Stopwatch()..start();
      try {
        final req = await client.getUrl(Uri.parse('$m/$url'));
        req.headers.set('Range', 'bytes=0-65535');
        req.headers.set('User-Agent', 'box-app');
        final resp = await req.close();
        var got = 0;
        await for (final chunk in resp) {
          got += chunk.length;
          if (got >= 65536) break;
        }
        sw.stop();
        if (got <= 0) {
          return MirrorSample(mirror: mirror, ok: false, error: '空响应');
        }
        return MirrorSample(mirror: mirror, ok: true, elapsed: sw.elapsed);
      } catch (e) {
        sw.stop();
        return MirrorSample(mirror: mirror, ok: false, error: '$e');
      }
    }

    final ranked = await MirrorProbe(rounds: 3, probe: probeOnce).rank(target);

    for (final r in ranked) {
      // ignore: avoid_print
      print('  ${r.label.padRight(22)} ${r.summary}');
    }

    final usable = ranked.where((r) => r.usable).toList();
    if (usable.isEmpty) {
      markTestSkipped('所有线路都不可用（外部网络），本次跳过');
      return;
    }

    // 排序必须真的成立：可用的按中位耗时升序，不可用的垫底。
    for (var i = 1; i < usable.length; i++) {
      expect(
        usable[i - 1].medianMs,
        lessThanOrEqualTo(usable[i].medianMs),
      );
    }
    if (ranked.any((r) => !r.usable)) {
      expect(ranked.last.usable, isFalse, reason: '不可用的必须排最后');
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
