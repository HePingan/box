// 缩略图取用器单测：缓存命中不取、同键去重、并发上限、失败静默。
//
// 并发上限那几条是本文件的重点：它是"列表滚动时别把带宽占满"的唯一保证，
// 而队列类代码最容易写出的 bug 就是"释放时唤醒"与"新请求直接通过"撞在一起，
// 把并发数顶到上限之上。

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:box/features/extensions/plugins/remote_storage/application/thumbnail_loader.dart';
import 'package:box/features/extensions/plugins/remote_storage/data/remote_thumbnail_cache.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytesOf(int n) => Uint8List.fromList(List<int>.filled(n, 3));

/// 等条件成立。缩略图取用器先查磁盘缓存（真实文件 IO），所以"取图开始"不是
/// 同步发生的——用固定次数的 Duration.zero 会让用例变成看运气。
Future<void> waitFor(
  bool Function() condition, {
  String describe = '条件',
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail('等待$describe超时');
}

void main() {
  late Directory root;
  late RemoteThumbnailCache cache;
  late ThumbnailLoader loader;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('thumb_loader_test_');
    cache = RemoteThumbnailCache(root: root);
    loader = ThumbnailLoader(cache: cache, maxConcurrent: 2);
  });

  tearDown(() async {
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  test('缓存命中：第二次不再取', () async {
    var fetches = 0;
    Future<Uint8List?> fetch() async {
      fetches += 1;
      return bytesOf(4);
    }

    final first = await loader.load('k', fetch);
    final second = await loader.load('k', fetch);

    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(fetches, 1, reason: '第二次应命中缓存');
  });

  test('同键去重：并发两次只发一次请求，两边拿到同一结果', () async {
    var fetches = 0;
    final gate = Completer<void>();
    Future<Uint8List?> fetch() async {
      fetches += 1;
      await gate.future;
      return bytesOf(6);
    }

    final a = loader.load('same', fetch);
    final b = loader.load('same', fetch);
    gate.complete();
    final results = await Future.wait([a, b]);

    expect(fetches, 1, reason: '同一张图不该同时取两遍');
    expect(results[0]!.length, 6);
    expect(results[1]!.length, 6);
  });

  test('并发上限：同时在跑的取图数不超过 maxConcurrent', () async {
    var active = 0;
    var maxSeen = 0;
    final gates = <Completer<void>>[];

    Future<Uint8List?> fetchFor(int i) async {
      active += 1;
      maxSeen = active > maxSeen ? active : maxSeen;
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
      active -= 1;
      return bytesOf(2);
    }

    final futures = <Future<Uint8List?>>[
      for (var i = 0; i < 5; i++) loader.load('k$i', () => fetchFor(i)),
    ];
    // 注意：5 个 load 里的 cache.get 会各创建一次目录（IO），下面统一等条件。

    // 让前两个跑起来，其余排队
    await waitFor(() => gates.length == 2, describe: '两个取图开始');
    expect(loader.activeCount, 2, reason: '上限 2：前两个在跑');
    expect(gates.length, 2, reason: '只有两个真正开始取');

    // 逐个放行：每放一个，队列里才轮到下一个开始（放行顺序即 FIFO）。
    for (var i = 0; i < 5; i++) {
      await waitFor(
        () => gates.length > i && !gates[i].isCompleted,
        describe: '第 ${i + 1} 个取图开始',
      );
      gates[i].complete();
    }
    await Future.wait(futures);

    expect(maxSeen, lessThanOrEqualTo(2), reason: '并发数不能超过上限');
    expect(maxSeen, 2, reason: '应该真的用满并发（不是退化成串行）');
    expect(loader.activeCount, 0);
  });

  test('槽位转交时来了新请求，也不会超过上限', () async {
    // 上限 1：A 在跑 → B 排队 → A 释放的瞬间 C 也来排队。
    final single = ThumbnailLoader(cache: cache, maxConcurrent: 1);
    final gates = <Completer<void>>[];
    var active = 0;
    var maxSeen = 0;

    Future<Uint8List?> fetch() async {
      active += 1;
      maxSeen = active > maxSeen ? active : maxSeen;
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
      active -= 1;
      return bytesOf(1);
    }

    final a = single.load('a', fetch);
    await waitFor(() => gates.length == 1, describe: 'a 开始取图');
    final b = single.load('b', fetch);
    final c = single.load('c', fetch);
    await waitFor(() => single.activeCount == 1, describe: '并发稳定在 1');
    expect(gates.length, 1, reason: '上限 1：只有 a 在跑');

    // a 释放 → 槽位转交 b（c 已在队列里）；这正是"转交 + 新请求"最容易顶破上限的时序
    gates[0].complete();
    await waitFor(() => gates.length == 2, describe: 'b 拿到转交的槽位');
    gates[1].complete();
    await waitFor(() => gates.length == 3, describe: 'c 拿到转交的槽位');
    gates[2].complete();
    await Future.wait([a, b, c]);

    expect(maxSeen, 1, reason: '上限 1 时任何时刻都只能有一个在跑');
  });

  test('取不到（null）→ 返回 null 且不写缓存', () async {
    var fetches = 0;
    Future<Uint8List?> fetch() async {
      fetches += 1;
      return null;
    }

    expect(await loader.load('miss', fetch), isNull);
    expect(await loader.load('miss', fetch), isNull);
    expect(fetches, 2, reason: '失败结果不缓存，下次仍会尝试');
  });

  test('空字节按取不到处理（不写缓存、不显示空图）', () async {
    expect(await loader.load('empty', () async => Uint8List(0)), isNull);
    expect(cache.memoryCount, 0);
  });

  test('fetch 抛异常 → 静默返回 null（列表不该因此报错）', () async {
    final result = await loader.load('boom', () async {
      throw const FileSystemException('磁盘炸了');
    });
    expect(result, isNull);
    expect(loader.activeCount, 0, reason: '异常也要释放槽位，否则队列会卡死');
  });
}
