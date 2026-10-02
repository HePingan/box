// 图床"边缘 IP 记忆"的纯逻辑：记住哪个通、哪个不通、多久之后可以再用。
//
// 起因（2026-10-02 实测）：`tuer.justpic01pt.com` 解析出 10 个 IP，其中 5 个全死
// （`185.13.110.21~25` 整段）。走域名每次新建连接只有 10/15 成功，直连一个通着的
// IP 是 15/15。取图侧靠这份记忆优先直连好 IP（见 comic_image_cache.dart）。
library;

import 'dart:io';

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/comic/domain/comic_image_edges.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ComicImageEdges edgesWith(
    List<String> ips, {
    Duration badTtl = const Duration(minutes: 30),
    String ns = 'edges_unit',
  }) => ComicImageEdges(
    cacheStore: CacheStore.inMemory(ns),
    resolver: (host) async => ips,
    badTtl: badTtl,
  );

  test('记下"通"的 IP 就优先用它；标"不通"之后不再优先', () async {
    final edges = edgesWith(['1.1.1.1', '2.2.2.2']);
    expect(await edges.preferred('img.test'), isNull, reason: '没学过就没有');

    await edges.markGood('img.test', '1.1.1.1');
    expect(await edges.preferred('img.test'), '1.1.1.1');

    await edges.markBad('img.test', '1.1.1.1');
    expect(await edges.preferred('img.test'), isNull, reason: '坏的不能继续当好的');
  });

  test('fallbackIps：跳过试过的、跳过坏的，且受 limit 限制', () async {
    final edges = edgesWith(['1.1.1.1', '2.2.2.2', '3.3.3.3', '4.4.4.4']);
    await edges.markBad('img.test', '2.2.2.2');

    expect(await edges.fallbackIps('img.test', limit: 2), ['1.1.1.1', '3.3.3.3']);
    expect(
      await edges.fallbackIps('img.test', tried: {'1.1.1.1'}, limit: 2),
      ['3.3.3.3', '4.4.4.4'],
    );
  });

  test('坏 IP 到期之后还能再用（IP 会恢复，不该永久拉黑）', () async {
    final edges = edgesWith(
      ['1.1.1.1'],
      badTtl: Duration.zero,
      ns: 'edges_ttl',
    );
    await edges.markBad('img.test', '1.1.1.1');
    expect(await edges.fallbackIps('img.test'), ['1.1.1.1']);
  });

  test('通了就把它从坏名单里摘掉（同一个 IP 的坏记忆不该压住事实）', () async {
    final edges = edgesWith(['1.1.1.1'], ns: 'edges_unbad');
    await edges.markBad('img.test', '1.1.1.1');
    await edges.markGood('img.test', '1.1.1.1');
    expect(await edges.preferred('img.test'), '1.1.1.1');
    expect(await edges.fallbackIps('img.test'), ['1.1.1.1']);
  });

  test('存储读不出来（没平台实现）也不抛：当成"没有记忆"', () async {
    final edges = ComicImageEdges(); // 用默认 CacheStore，测试环境没有平台实现
    expect(await edges.preferred('img.test'), isNull);
    expect(await edges.fallbackIps('img.test'), isEmpty);
    // 写进去也不该抛
    await edges.markGood('img.test', '1.1.1.1');
    await edges.markBad('img.test', '1.1.1.1');
  });

  test('解析失败（域名没了）就老实返回空，不在取图路径上抛错', () async {
    final edges = ComicImageEdges(
      cacheStore: CacheStore.inMemory('edges_resolve_fail'),
      resolver: (host) async => throw const SocketException('解析不了'),
    );
    expect(await edges.fallbackIps('nope.invalid'), isEmpty);
  });
}
