// 图床换端口重试 + 限并发 + 连接复用。
//
// 起因（2026-10-01 用户报「图床连不上 (tuer.justpic01pt.com)：Connection reset by peer」）：
// 同一张图他在**手机浏览器里打得开**（带端口和不带端口都能开），App 却偶发被 reset ——
// 那就是"同一来源短时新建连接太多 / 偶发被掐"，而不是端口被封、更不是源坏了。
//
// 用**真的本地 HTTP 服务器**验（不 mock socket，要验的正是连接层）。
import 'dart:io';

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/comic/domain/comic_image_cache.dart';
import 'package:box/features/comic/domain/comic_image_edges.dart';
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
    ComicImageEdges? edges,
  }) => ComicImageCache(
    tempDirProvider: () async => tmp,
    alternatePorts: alternatePorts,
    maxParallel: maxParallel,
    edges: edges,
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

  // ── 边缘 IP 直连（2026-10-02 实测：域名解析出的 10 个 IP 里 5 个全死）──
  //
  // 走域名每次新建连接是 10/15，直连一个通着的 IP 是 15/15。这里用**真的本地
  // HTTP 服务器**验：用一个**根本解析不了**的域名（.invalid）当"域名的 A 记录是死的"，
  // 能不能靠直连拿到图。
  group('边缘 IP 直连', () {
    test('学过好 IP：域名解析不了也能直连把图取回来', () async {
      final paths = <String>[];
      final srv = await startImageServer(paths: paths);
      final edges = ComicImageEdges(
        cacheStore: CacheStore.inMemory('edges_learned'),
        resolver: (h) async => ['127.0.0.1'],
      );
      final cache = cacheFor(const {}, edges: edges);
      await edges.markGood('img.invalid', '127.0.0.1');

      final f = await cache.fetch('http://img.invalid:${srv.port}/a.jpg');

      expect(await f.readAsString(), body, reason: '直连好 IP 应当拿到完整的图');
      expect(paths.single, startsWith('GET /a.jpg'));
      expect(
        cache.usedAddress('http://img.invalid:${srv.port}/a.jpg'),
        contains('@127.0.0.1'),
        reason: '自检要能说清"是直连某个 IP 才通的"',
      );
      await srv.close();
    });

    test('还没学过：试的过程中自己学会（下次直接走它）', () async {
      final srv = await startImageServer();
      final edges = ComicImageEdges(
        cacheStore: CacheStore.inMemory('edges_learn'),
        resolver: (h) async => ['127.0.0.1'],
      );
      final cache = cacheFor(const {}, edges: edges);

      final url = 'http://img.invalid:${srv.port}/b.jpg';
      expect(await (await cache.fetch(url)).readAsString(), body);
      expect(
        await edges.preferred('img.invalid'),
        '127.0.0.1',
        reason: '通了就该记住它，下次先走它',
      );

      // 第二次：直接命中学到的 IP（再取一张，服务器照样回）
      expect(await (await cache.fetch(url)).readAsString(), body);
      await srv.close();
    });

    test('哪个 IP 都不通：如实报错，不假装成功', () async {
      final edges = ComicImageEdges(
        cacheStore: CacheStore.inMemory('edges_none'),
        resolver: (h) async => const <String>[],
      );
      final cache = cacheFor(const {}, edges: edges);
      await expectLater(
        cache.fetch('http://nowhere.invalid:9/x.jpg'),
        throwsA(isA<ComicImageException>()),
      );
    });

    test('直连过的 IP 坏掉：标坏之后不再先试它', () async {
      var goodHits = 0;
      final dead = await startKiller(onHit: () => goodHits++);
      final edges = ComicImageEdges(
        cacheStore: CacheStore.inMemory('edges_demote'),
        resolver: (h) async => ['127.0.0.1'],
      );
      final cache = cacheFor(const {}, edges: edges);
      // 先"学会"一个其实已经不通的 IP
      await edges.markGood('img.invalid', '127.0.0.1');

      await expectLater(
        cache.fetch('http://img.invalid:${dead.port}/c.jpg'),
        throwsA(isA<ComicImageException>()),
      );
      expect(goodHits, greaterThanOrEqualTo(1), reason: '先试过它');
      expect(
        await edges.preferred('img.invalid'),
        isNull,
        reason: '不通的 IP 不能继续当"好 IP"',
      );
      await dead.close();
    });
  });

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
      startsWith('http://127.0.0.1:${good.port}/pic.jpg'),
      reason: '自检要拿它说清"是换了端口才通的"（现在会优先直连 IP，标签可能带 @IP）',
    );

    await bad.close();
    await good.close();
  });

  // ── 自己挑 IP + 下载要更多机会（2026-10-02）──
  group('自己挑 IP，不交给系统掷硬币', () {
    test('候选顺序：解析出的 IP 排前面，域名只当兜底', () async {
      final edges = ComicImageEdges(
        cacheStore: CacheStore.inMemory('order_none'),
        resolver: (h) async => ['10.0.0.1', '10.0.0.2', '10.0.0.3'],
      );
      final labels = await cacheFor(
        const {},
        edges: edges,
      ).debugCandidateLabels('http://img.test:666/a.jpg');

      expect(labels, [
        'http://img.test:666/a.jpg @10.0.0.1',
        'http://img.test:666/a.jpg @10.0.0.2',
        'http://img.test:666/a.jpg @10.0.0.3',
        'http://img.test:666/a.jpg',
      ], reason: '走域名等于掷硬币（实测 30 张失败 9 成），所以 IP 全排前面');
    });

    test('学过的好 IP 排第一（其余 IP 仍留着当备份，域名仍垫底）', () async {
      final edges = ComicImageEdges(
        cacheStore: CacheStore.inMemory('order_good'),
        resolver: (h) async => ['10.0.0.1', '10.0.0.2', '10.0.0.3'],
      );
      await edges.markGood('img.test', '10.0.0.2');
      final labels = await cacheFor(
        const {},
        edges: edges,
      ).debugCandidateLabels('http://img.test:666/a.jpg');

      expect(labels.first, 'http://img.test:666/a.jpg @10.0.0.2');
      expect(labels.last, 'http://img.test:666/a.jpg');
      expect(labels, contains('http://img.test:666/a.jpg @10.0.0.1'));
    });

    test('解析不出来就退回域名老路（不因为"记不住"取不到图）', () async {
      final edges = ComicImageEdges(
        cacheStore: CacheStore.inMemory('order_fail'),
        resolver: (h) async => throw const SocketException('解析不了'),
      );
      final labels = await cacheFor(
        const {},
        edges: edges,
      ).debugCandidateLabels('http://img.test:666/a.jpg');

      expect(labels, ['http://img.test:666/a.jpg']);
    });

    test('下载要更多机会：maxAttempts 覆写前 3 次不够、覆写后够（同一台服务器分开比）', () async {
      // 两个阶段各用一台服务器 + 一份全新的记忆，否则第一阶段的"坏 IP 标记"
      // 会漏到第二阶段，测出来的就不是"预算"了（自己给自己放水）。
      Future<ServerSocket> killer(int kills, {required List<int> counter}) async {
        final srv = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
        srv.listen((c) async {
          counter[0]++;
          if (counter[0] <= kills) {
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
        return srv;
      }

      ComicImageEdges freshEdges(String ns) => ComicImageEdges(
        cacheStore: CacheStore.inMemory(ns),
        resolver: (h) async => ['127.0.0.1', '127.0.0.2', '127.0.0.3', '127.0.0.4'],
      );

      // 阶段一：全部掐断，默认 3 次机会 → 失败（这就是用户截图里的形态）。
      final hitsA = [0];
      final srvA = await killer(99, counter: hitsA);
      final urlA = 'http://127.0.0.1:${srvA.port}/pic.jpg';
      await expectLater(
        cacheFor(const {}, edges: freshEdges('budget_fore')).fetch(urlA),
        throwsA(isA<ComicImageException>()),
      );
      expect(hitsA[0], 3, reason: '前台默认就试 3 个地址');
      await srvA.close();

      // 阶段二：前 4 条掐断、第 5 条回图。下载传 6 → 必须成，而且真的试到第 5 个。
      final hitsB = [0];
      final srvB = await killer(4, counter: hitsB);
      final urlB = 'http://127.0.0.1:${srvB.port}/pic.jpg';
      final f = await cacheFor(
        const {},
        edges: freshEdges('budget_dl'),
      ).fetch(urlB, maxAttempts: 6);

      expect(await f.readAsString(), body);
      expect(hitsB[0], 5, reason: '前 4 个地址死了，第 5 个才通 —— 默认的 3 次到这里就没了');
      await srvB.close();
    });
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
