@Tags(['live'])
library;

import 'dart:io';

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
}
