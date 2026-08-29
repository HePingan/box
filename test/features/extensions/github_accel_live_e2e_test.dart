@Tags(['live'])
library;

import 'dart:io';

import 'package:box/features/extensions/plugins/github_accel/github_accel_probe.dart';
import 'package:box/features/extensions/plugins/github_accel/github_accel_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真联网端到端验证，默认随 `flutter test` 一起跑会受网络影响，
/// 因此打了 `live` 标签，用下面命令单独跑：
///
///   flutter test --tags live test/features/extensions/github_accel_live_e2e_test.dart
///
/// 验证目标：用户截图里那条 RikkaHub 签名长链，经多通道查询后
/// 能还原成真实可下载的加速地址，并且下载回来的确实是 APK 字节。
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

  test('签名长链 → 真实可下载的加速地址', () async {
    final svc = GithubAccelService(fetch: fetch);
    final r = await svc.resolve(signed);

    expect(r.ok, isTrue, reason: '实测应能查到 rikkahub/rikkahub：${r.message}');
    expect(
      r.accelUrl,
      'https://gh-proxy.com/https://github.com/rikkahub/rikkahub'
      '/releases/latest/download/RikkaHub-2.4.15-arm64-v8a.apk',
    );

    // 真下前 256KB，确认是 APK（ZIP 魔数 50 4B 03 04）而不是错误页。
    final req = await client.getUrl(Uri.parse(r.accelUrl!));
    req.headers.set('Range', 'bytes=0-262143');
    final resp = await req.close();
    final bytes = <int>[];
    // break 出 await-for 会自动取消订阅，不能再 drain（Stream 已被监听）。
    await for (final chunk in resp) {
      bytes.addAll(chunk);
      if (bytes.length >= 4) break;
    }

    expect(resp.statusCode, anyOf(200, 206));
    expect(
      bytes.take(4).toList(),
      [0x50, 0x4B, 0x03, 0x04],
      reason: '应下到真实 APK 字节',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));

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
    expect(usable, isNotEmpty, reason: '至少要有一条线路测通');

    // 排序必须真的成立：可用的按中位耗时升序，不可用的垫底。
    for (var i = 1; i < usable.length; i++) {
      expect(
        usable[i - 1].medianMs,
        lessThanOrEqualTo(usable[i].medianMs),
      );
    }
    expect(ranked.last.usable, anyOf(isTrue, isFalse));
    if (ranked.any((r) => !r.usable)) {
      expect(ranked.last.usable, isFalse, reason: '不可用的必须排最后');
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
