// 图片下载的**优先级池**：预取（下一话开头几张）不能让正在读的那一话排队。
//
// 2026-10-01：预取与正文共用同一个 `ComicImageCache` 实例 → 同一个并发池（4 个名额），
// 翻到下一话前预取正跑着 3 张，正文的图就排在它们后面。现在把预取标成低优先级：
// 最多占 `maxParallel - foregroundReserved`（默认 4-2=2）个名额，且**有前台在排队时不抢**。
import 'dart:async';
import 'dart:io';

import 'package:box/features/comic/domain/comic_image_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('comic_img_prio_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  const body = 'JPEG-BYTES-1234';

  test('预取最多占 2 个名额；前台在排队时不被预取堵住', () async {
    final gate = Completer<void>();
    var lowRunning = 0;
    var lowPeak = 0;
    var highDone = 0;

    final srv = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    srv.listen((c) async {
      var buf = <int>[];
      await for (final chunk in c) {
        buf.addAll(chunk);
        final text = String.fromCharCodes(buf);
        if (!text.contains('\r\n\r\n')) continue;
        buf = <int>[];
        final path = text.split('\r\n').first;
        final isLow = path.contains('/low');
        if (isLow) {
          lowRunning++;
          if (lowRunning > lowPeak) lowPeak = lowRunning;
          // 预取的图"挂着不动"：模拟它正在慢吞吞地占着名额。
          await gate.future;
          lowRunning--;
        } else {
          highDone++;
        }
        c.write(
          'HTTP/1.1 200 OK\r\nContent-Type: image/jpeg\r\n'
          'Content-Length: ${body.length}\r\nConnection: keep-alive\r\n\r\n$body',
        );
        await c.flush();
        if (!isLow) {
          await c.close();
          return;
        }
      }
    });

    final cache = ComicImageCache(
      tempDirProvider: () async => tmp,
      maxParallel: 4,
      foregroundReserved: 2,
      connectTimeout: const Duration(seconds: 3),
      idleTimeout: const Duration(seconds: 5),
      totalTimeout: const Duration(seconds: 20),
    );

    // 5 张预取（低优先级）：只该有 2 张真的在跑，其余排队。
    final lows = <Future<File>>[
      for (var i = 0; i < 5; i++)
        cache.fetch('http://127.0.0.1:${srv.port}/low$i.jpg', lowPriority: true),
    ];
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    expect(lowRunning, 2, reason: '低优先级同时只该占 2 个名额');
    expect(lowPeak, lessThanOrEqualTo(2));

    // 前台 2 张（还剩 2 个名额）：必须**当场完成** —— 队里还有 3 张预取在等，
    // 前台要是排在它们后面，这里就永远回不来。
    await Future.wait(<Future<File>>[
      cache.fetch('http://127.0.0.1:${srv.port}/high0.jpg'),
      cache.fetch('http://127.0.0.1:${srv.port}/high1.jpg'),
    ]);
    expect(highDone, 2, reason: '前台的两张都下下来了');
    expect(gate.isCompleted, isFalse, reason: '预取这时还挂在那里');
    expect(lowRunning, 2, reason: '前台拿名额不该把正在跑的预取算错');

    // 放行预取：全部收尾，且低优先级始终没超过 2。
    gate.complete();
    final files = await Future.wait(lows);
    expect(files, hasLength(5));
    for (final f in files) {
      expect(await f.readAsString(), body);
    }
    expect(lowPeak, lessThanOrEqualTo(2));

    await srv.close();
  });

  test('前台自己不受低优先级限制：一起放 6 张前台，照样按 maxParallel 跑满', () async {
    var running = 0;
    var peak = 0;
    final srv = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    srv.listen((c) async {
      var buf = <int>[];
      await for (final chunk in c) {
        buf.addAll(chunk);
        final text = String.fromCharCodes(buf);
        if (!text.contains('\r\n\r\n')) continue;
        buf = <int>[];
        running++;
        if (running > peak) peak = running;
        await Future<void>.delayed(const Duration(milliseconds: 60));
        running--;
        c.write(
          'HTTP/1.1 200 OK\r\nContent-Type: image/jpeg\r\n'
          'Content-Length: ${body.length}\r\nConnection: keep-alive\r\n\r\n$body',
        );
        await c.flush();
      }
    });

    final cache = ComicImageCache(
      tempDirProvider: () async => tmp,
      maxParallel: 4,
      foregroundReserved: 2,
    );
    final files = await Future.wait(<Future<File>>[
      for (var i = 0; i < 6; i++)
        cache.fetch('http://127.0.0.1:${srv.port}/p$i.jpg'),
    ]);

    expect(files, hasLength(6));
    expect(peak, lessThanOrEqualTo(4), reason: '前台也照样不超过 maxParallel');
    expect(peak, greaterThan(2), reason: '前台能用满 4 个名额，不被 foregroundReserved 卡住');

    await srv.close();
  });
}
