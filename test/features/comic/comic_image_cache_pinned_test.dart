// 「直连边缘 IP」这条路本身的回归用例（2026-10-02）。
//
// 起因：348 里直连那条路**从来没真的通过** —— `HttpClient.connectionFactory` 返回的是
// "已经连好的裸连接"，dart:io 不会再替它做 TLS 握手。于是直连 IP 的请求是**明文 HTTP
// 发到 HTTPS 端口**，服务端一句 `400 Client sent an HTTP request to an HTTPS server.`
// 打回来；而 400 又被当成"换个地址也没用"直接整张判死，域名兜底那一步根本走不到。
// 用户那头的观感就是"每张图都下失败（HTTP 400）"。
//
// 这两条用一个真的本地服务器把两个坑钉住（不 mock socket：要验的正是连接层）：
//   1. 直连候选撞 4xx 时**必须继续换地址**，不能整张判死；
//   2. https 的直连候选**必须真的是 TLS**，不能把明文请求发给对端。
import 'dart:io';

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/comic/domain/comic_image_cache.dart';
import 'package:box/features/comic/domain/comic_image_edges.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('comic_img_pinned_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  ComicImageCache cacheFor(Map<int, int> alternatePorts) => ComicImageCache(
    tempDirProvider: () async => tmp,
    alternatePorts: alternatePorts,
    // 直连候选从"记忆"里来：这里注入一个假的解析器，等于"域名解析出这几个 IP"。
    edges: ComicImageEdges(
      cacheStore: CacheStore(namespace: 'comic_img_edges_test'),
      resolver: (host) async => const ['127.0.0.1'],
    ),
    connectTimeout: const Duration(seconds: 3),
    idleTimeout: const Duration(seconds: 3),
    totalTimeout: const Duration(seconds: 10),
  );

  test('直连候选撞 400（"明文发到 HTTPS 端口"那种）要换下一个地址，而不是整张判死', () async {
    // A：直连会撞到的那个地址 —— 复刻图床原话，4xx 且**只代表这个地址有问题**。
    final bad = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    bad.listen((req) async {
      req.response
        ..statusCode = HttpStatus.badRequest
        ..write('Client sent an HTTP request to an HTTPS server.');
      await req.response.close();
    });
    // B：换端口以后是好的（App 里 `:666` 换 `:443` 就是这么来的）。
    final good = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    good.listen((req) async {
      req.response
        ..statusCode = HttpStatus.ok
        ..add(List<int>.filled(128, 7));
      await req.response.close();
    });
    addTearDown(() async {
      await bad.close(force: true);
      await good.close(force: true);
    });

    final cache = cacheFor({bad.port: good.port});
    final file = await cache.fetch(
      'http://127.0.0.1:${bad.port}/picbed/x.jpg',
      dest: File('${tmp.path}/a.jpg'),
    );
    expect(await file.length(), 128, reason: '撞 400 之后应该接着试下一个地址并成功');
  });

  test('https 的直连候选必须是真 TLS：明文请求不该被服务端当正常请求收下', () async {
    // 一个"只会说 HTTP"的服务器。老写法（裸 Socket 交给 dart:io）会把明文请求发过来，
    // 它会老老实实回 200 —— 那就等于暴露了"没有 TLS"；修好后这里应该是握手失败。
    final plain = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var served = 0;
    plain.listen((req) async {
      served++;
      req.response
        ..statusCode = HttpStatus.ok
        ..add(List<int>.filled(64, 1));
      await req.response.close();
    });
    addTearDown(() async => plain.close(force: true));

    final cache = cacheFor(const {});
    await expectLater(
      cache.fetch(
        'https://127.0.0.1:${plain.port}/picbed/x.jpg',
        dest: File('${tmp.path}/b.jpg'),
      ),
      throwsA(isA<Object>()),
      reason: '对端不是 TLS 服务器，直连这条路必须失败（说明我们发了 TLS 握手，而不是明文）',
    );
    expect(served, 0, reason: '明文 HTTP 请求一个字节都不该被当成正常请求处理');
  });
}
