// 图床换端口重试 + 限并发 + 连接复用。
//
// 起因（2026-10-01 用户报「图床连不上 (tuer.justpic01pt.com)：Connection reset by peer」）：
// 同一张图他在**手机浏览器里打得开**（带端口和不带端口都能开），App 却偶发被 reset ——
// 那就是"同一来源短时新建连接太多 / 偶发被掐"，而不是端口被封、更不是源坏了。
//
// 用**真的本地 HTTP 服务器**验（不 mock socket，要验的正是连接层）。
import 'dart:io';

import 'package:box/features/comic/domain/comic_image_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('comic_img_fallback_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  ComicImageCache cacheFor(
    Map<int, int> alternatePorts, {
    int maxParallel = 4,
  }) => ComicImageCache(
    tempDirProvider: () async => tmp,
    alternatePorts: alternatePorts,
    maxParallel: maxParallel,
    connectTimeout: const Duration(seconds: 3),
    idleTimeout: const Duration(seconds: 3),
    totalTimeout: const Duration(seconds: 10),
  );

  /// 坏服务器：接住连接立刻掐断（用户手机上看到的 Connection reset 就是这种形态）。
  Future<ServerSocket> startKiller({void Function()? onHit}) async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    s.listen((c) {
      onHit?.call();
      c.destroy();
    });
    return s;
  }

  const body = 'JPEG-BYTES-1234';

  /// 真会回图的服务器；`keepAlive` 时同一条连接可以连着回多个请求。
  Future<ServerSocket> startImageServer({
    List<String>? paths,
    void Function()? onConnection,
    void Function()? onRequestStart,
    void Function()? onRequestEnd,
    bool keepAlive = false,
  }) async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    s.listen((c) async {
      onConnection?.call();
      var buf = <int>[];
      await for (final chunk in c) {
        buf.addAll(chunk);
        final text = String.fromCharCodes(buf);
        if (!text.contains('\r\n\r\n')) continue;
        onRequestStart?.call();
        paths?.add(text.split('\r\n').first);
        c.write(
          'HTTP/1.1 200 OK\r\nContent-Type: image/jpeg\r\n'
          'Content-Length: ${body.length}\r\n'
          'Connection: ${keepAlive ? 'keep-alive' : 'close'}\r\n\r\n$body',
        );
        await c.flush();
        onRequestEnd?.call();
        buf = <int>[];
        if (!keepAlive) {
          await c.close();
          return;
        }
      }
    });
    return s;
  }

  test('原端口把连接掐断 → 自动换到备选端口把这张图取回来', () async {
    var badHits = 0;
    final bad = await startKiller(onHit: () => badHits++);
    final paths = <String>[];
    final good = await startImageServer(paths: paths);

    final cache = cacheFor({bad.port: good.port});
    final url = 'http://127.0.0.1:${bad.port}/pic.jpg';
    final f = await cache.fetch(url);

    expect(await f.readAsString(), body, reason: '换端口之后应当拿到完整的图');
    expect(badHits, greaterThanOrEqualTo(1), reason: '原端口先试过');
    expect(paths.single, startsWith('GET /pic.jpg'), reason: '备选端口用同一个路径');
    expect(
      cache.usedAddress(url),
      'http://127.0.0.1:${good.port}/pic.jpg',
      reason: '自检要拿它说清"是换了端口才通的"',
    );

    await bad.close();
    await good.close();
  });

  test('被掐断 → 同一个地址再试一次（共 3 次机会）', () async {
    var hits = 0;
    // 前两次掐断，第三次正常回图：模拟"偶发被掐"。
    final srv = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    srv.listen((c) async {
      hits++;
      if (hits <= 2) {
        c.destroy();
        return;
      }
      await c.cast<List<int>>().transform(const SystemEncoding().decoder).first;
      c.write(
        'HTTP/1.1 200 OK\r\nContent-Length: ${body.length}\r\n'
        'Connection: close\r\n\r\n$body',
      );
      await c.flush();
      await c.close();
    });

    final cache = cacheFor(const {});
    final f = await cache.fetch('http://127.0.0.1:${srv.port}/pic.jpg');

    expect(await f.readAsString(), body);
    expect(hits, 3, reason: '两次被掐之后按原地址再来一次才成');

    await srv.close();
  });

  test('两个端口都不通 → 说清「哪条路、试了几次」，不丢 errno', () async {
    final bad = await startKiller();
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final closedPort = probe.port;
    await probe.close();

    final cache = cacheFor({bad.port: closedPort});
    Object? err;
    try {
      await cache.fetch('http://127.0.0.1:${bad.port}/pic.jpg');
    } catch (e) {
      err = e;
    }

    expect(err, isA<ComicImageException>());
    final msg = (err! as ComicImageException).message;
    // 报错里必须同时看到：哪台主机、出在通信的哪一步、这条路试了几次。
    expect(msg, contains('127.0.0.1'), reason: '要说清是哪台主机');
    expect(
      msg,
      anyOf(contains('图床连不上'), contains('图片下载失败'), contains('图片下载中断')),
      reason: '要说清是通信哪一步出的问题',
    );
    expect(msg, contains(':${bad.port} 这条路'), reason: '试的是哪条路要写出来');
    expect(msg, contains('共试了'), reason: '试了几次也要写出来');
    expect(msg, isNot(contains('errno = ')), reason: '终端用户不该看见 errno');

    await bad.close();
  });

  test('HTTP 404 不重试：地址本身就没有，再试也是白费', () async {
    var hits = 0;
    final srv = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    srv.listen((c) async {
      hits++;
      await c.cast<List<int>>().transform(const SystemEncoding().decoder).first;
      c.write('HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n');
      await c.flush();
      await c.close();
    });
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final altPort = probe.port;
    await probe.close();

    final cache = cacheFor({srv.port: altPort});
    Object? err;
    try {
      await cache.fetch('http://127.0.0.1:${srv.port}/pic.jpg');
    } catch (e) {
      err = e;
    }

    expect((err as ComicImageException).message, contains('HTTP 404'));
    expect((err).retryable, isFalse);
    expect(hits, 1, reason: '404 只该请求一次');

    await srv.close();
  });

  test('并发被限在 maxParallel：一次放 8 张，服务器同时只看到 2 条', () async {
    var now = 0;
    var peak = 0;
    final srv = await startImageServer(
      keepAlive: true,
      onRequestStart: () {
        now++;
        if (now > peak) peak = now;
      },
      onRequestEnd: () => now--,
    );

    final cache = cacheFor(const {}, maxParallel: 2);
    final futures = [
      for (var i = 0; i < 8; i++)
        cache.fetch('http://127.0.0.1:${srv.port}/p$i.jpg'),
    ];
    final files = await Future.wait(futures);

    expect(files, hasLength(8));
    for (final f in files) {
      expect(await f.readAsString(), body);
    }
    expect(peak, lessThanOrEqualTo(2), reason: '同时最多 2 张在下载');

    await srv.close();
  });

  test('顺序取多张会复用同一条连接（不是每张各开一条）', () async {
    var connections = 0;
    final srv = await startImageServer(
      keepAlive: true,
      onConnection: () => connections++,
    );

    final cache = cacheFor(const {}, maxParallel: 2);
    for (var i = 0; i < 4; i++) {
      final f = await cache.fetch('http://127.0.0.1:${srv.port}/p$i.jpg');
      expect(await f.readAsString(), body);
    }

    // 少了这一条，一屏封面就是十几条新建 TLS 连接 —— 图床/网关正是这么掐的。
    expect(connections, lessThan(4), reason: '4 张图不该开 4 条连接');

    await srv.close();
  });

  test('缓存命中不再走网络（换端口逻辑不会把缓存弄丢）', () async {
    final paths = <String>[];
    final good = await startImageServer(paths: paths);
    final cache = cacheFor(const {});
    final url = 'http://127.0.0.1:${good.port}/pic.jpg';

    await cache.fetch(url);
    await cache.fetch(url);

    expect(paths, hasLength(1), reason: '第二张应当直接用本地那份');

    await good.close();
  });
}
