// 图片下载的**截止时间**：每一张图都必须以"拿到图"或"说出原因"结束。
//
// 为什么单独立一份（2026-10-01 用户报的）：封面在列表里"一直转圈"，阅读页第一张也
// 一直转圈，而两头都**没有原因**。当时查出来是两层原因：
//   1. `fetch()` 里的 `whenComplete(() => _inFlight.remove(key))` —— 回调的返回值正好
//      是"这个 Future 自己"，于是它永远在等自己完成：图片其实早下完落盘了，Future 也
//      永远不 complete（下面第一个用例就是钉这个）；
//   2. `_fetchOnce` 里那两处裸等待（`req.close()` / `resp.fold()`）没有任何超时：对端
//      把连接挂住（移动网上的常事）就永远不返回，转圈也就永远不停。
//
// 这里起一个**真的本地 HTTP 服务**（不是假 HttpClient）造出各种坏情况，就近用真 socket
// 测生产那条路。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/comic/domain/comic_image_cache.dart';

void main() {
  late Directory root;
  late HttpServer server;
  late String base;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('comic_img_timeout_');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      switch (req.uri.path) {
        case '/ok':
          req.response
            ..statusCode = 200
            ..add(const <int>[1, 2, 3]);
          await req.response.close();
        case '/stall':
          // 一个字节正文都不发、也不关连接（`req.close()` 就一直不返回）。
          req.response.headers.contentLength = 100;
          await req.response.flush();
        case '/stall-mid':
          // 先给 10 个字节、再挂住（对端"下到一半不动了"）。
          req.response.headers.contentLength = 100;
          req.response.add(List<int>.filled(10, 7));
          await req.response.flush();
        default:
          req.response.statusCode = 404;
          await req.response.close();
      }
    });
  });

  tearDown(() async {
    await server.close(force: true);
    if (await root.exists()) await root.delete(recursive: true);
  });

  ComicImageCache cacheFor() => ComicImageCache(
    tempDirProvider: () async => root,
    // 连接给足 2 秒：要测的是"连上了但对方不吐数据"，别让连接超时抢先报错。
    connectTimeout: const Duration(seconds: 2),
    idleTimeout: const Duration(milliseconds: 120),
    totalTimeout: const Duration(milliseconds: 600),
  );

  test('正常一张：落盘并带回本地文件（Future 必须真的 complete）', () async {
    // 这条同时是 whenComplete 死锁的回归用例：死锁时 fetch 永不返回，
    // 封面/阅读页就永远是转圈。
    final file = await cacheFor()
        .fetch('$base/ok')
        .timeout(const Duration(seconds: 5));
    expect(await file.exists(), isTrue);
    expect(await file.length(), 3);
    expect(file.path, contains('comic_online_images'));
  });

  test('连上了但一个字节都不来：到了截止时间就报原因，不是一直转圈', () async {
    await expectLater(
      cacheFor().fetch('$base/stall'),
      throwsA(
        isA<ComicImageException>().having(
          (e) => e.message,
          'message',
          allOf(contains('图床没响应'), contains('127.0.0.1')),
        ),
      ),
    );
  });

  test('下到一半挂住：闲着超时兜底，报"卡住 + 主机"', () async {
    await expectLater(
      cacheFor().fetch('$base/stall-mid'),
      throwsA(
        isA<ComicImageException>().having(
          (e) => e.message,
          'message',
          allOf(contains('图床卡住了'), contains('127.0.0.1')),
        ),
      ),
    );
  });

  test('图床回 404：如实写状态码与主机', () async {
    await expectLater(
      cacheFor().fetch('$base/nope'),
      throwsA(
        isA<ComicImageException>().having(
          (e) => e.message,
          'message',
          allOf(contains('HTTP 404'), contains('127.0.0.1')),
        ),
      ),
    );
  });

  test('连不上（连接被拒）：报"连不上 + 主机"，不是一直转圈', () async {
    // 先占一个端口再关掉：这个地址上一定没人监听。
    final dead = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = dead.port;
    await dead.close(force: true);

    await expectLater(
      cacheFor().fetch('http://127.0.0.1:$port/x.jpg'),
      throwsA(
        isA<ComicImageException>().having(
          (e) => e.message,
          'message',
          allOf(contains('连不上'), contains('127.0.0.1')),
        ),
      ),
    );
  });
}
