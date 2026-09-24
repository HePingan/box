// 缩略图磁盘缓存单测：内存 LRU、磁盘往返、修剪、清空。
//
// 全程用注入的临时目录，不碰 path_provider、不碰真实应用目录。

import 'dart:io';
import 'dart:typed_data';

import 'package:box/features/extensions/plugins/remote_storage/data/remote_thumbnail_cache.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytesOf(int n, [int fill = 7]) =>
    Uint8List.fromList(List<int>.filled(n, fill));

void main() {
  late Directory root;
  late RemoteThumbnailCache cache;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('thumb_cache_test_');
    cache = RemoteThumbnailCache(root: root);
  });

  tearDown(() async {
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  group('内存层', () {
    test('put 后 get 命中内存（不再读盘）', () async {
      await cache.put('k1', bytesOf(10));
      expect(cache.memoryCount, 1);

      // 把磁盘文件删掉：仍然能取到 → 证明走的是内存。
      final file = File('${root.path}/${RemoteThumbnailCache.fileNameFor('k1')}');
      expect(await file.exists(), isTrue);
      await file.delete();

      final got = await cache.get('k1');
      expect(got, isNotNull);
      expect(got!.length, 10);
    });

    test('内存 LRU：超过上限淘汰最久未使用的', () async {
      final small = RemoteThumbnailCache(root: root, memoryEntries: 2);
      await small.put('a', bytesOf(1));
      await small.put('b', bytesOf(1));
      // 访问 a，让它变成"最近使用"
      await small.get('a');
      await small.put('c', bytesOf(1));

      // b 被挤出内存（磁盘上仍在——所以不能用 get('b') == null 断言：
      // 那会从磁盘读回来，属于正常且期望的行为）。
      expect(small.memoryCount, 2);
      expect(small.memoryKeys, ['a', 'c'], reason: 'b 最久未用，被挤出内存');
      expect(await small.get('b'), isNotNull, reason: '磁盘缓存仍在，能读回');
      // 读回 b 会把它插到队尾（最近使用），于是轮到 a 被挤出（上限 2）。
      expect(small.memoryKeys, ['c', 'b'], reason: 'b 变最近使用，a 被挤出');
    });

    test('clearMemory 只清内存，磁盘仍可读回', () async {
      await cache.put('k1', bytesOf(10));
      cache.clearMemory();
      expect(cache.memoryCount, 0);

      final got = await cache.get('k1');
      expect(got, isNotNull, reason: '磁盘缓存还在');
      expect(cache.memoryCount, 1, reason: '读回后提进内存');
    });
  });

  group('磁盘层', () {
    test('换一个实例（模拟重启）仍能读到磁盘缓存', () async {
      await cache.put('acct|a.jpg|100|2023-01-30T11:22:00.000', bytesOf(20, 9));

      final reopened = RemoteThumbnailCache(root: root);
      final got = await reopened.get('acct|a.jpg|100|2023-01-30T11:22:00.000');
      expect(got, isNotNull);
      expect(got!.length, 20);
      expect(got.first, 9);
    });

    test('未命中返回 null（不抛）', () async {
      expect(await cache.get('不存在'), isNull);
    });

    test('文件名按 UTF-8 取 sha1：中文/斜杠路径也安全', () {
      final name = RemoteThumbnailCache.fileNameFor('账户|相册/中文 图.jpg|100|x');
      expect(name, matches(RegExp(r'^[0-9a-f]{40}\.bin$')));
      // 同样的键必须得到同样的名字（跨会话命中），不同的键不能撞名。
      expect(
        RemoteThumbnailCache.fileNameFor('账户|相册/中文 图.jpg|100|x'),
        name,
      );
      expect(RemoteThumbnailCache.fileNameFor('另一个键'), isNot(name));
    });

    test('clear 清掉磁盘目录，之后 miss', () async {
      await cache.put('k1', bytesOf(10));
      await cache.clear();
      expect(await cache.get('k1'), isNull);
      final reopened = RemoteThumbnailCache(root: root);
      expect(await reopened.get('k1'), isNull);
    });
  });

  group('修剪', () {
    test('文件数超限 → 按最久未修改先删', () async {
      final small = RemoteThumbnailCache(root: root, maxFiles: 2, maxBytes: 1 << 20);
      // 手工造三个文件并给不同 mtime（老 → 新）
      for (var i = 0; i < 3; i++) {
        final file = File('${root.path}/f$i.bin');
        await file.writeAsBytes(bytesOf(5));
        await file.setLastModified(DateTime(2020, 1, 1 + i));
      }
      await small.prune();

      final left = root
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList()
        ..sort();
      expect(left, ['f1.bin', 'f2.bin'], reason: '最老的 f0 被删');
    });

    test('总字节超限 → 删到限额以内', () async {
      final small = RemoteThumbnailCache(root: root, maxBytes: 12);
      for (var i = 0; i < 3; i++) {
        final file = File('${root.path}/g$i.bin');
        await file.writeAsBytes(bytesOf(10));
        await file.setLastModified(DateTime(2020, 1, 1 + i));
      }
      await small.prune();

      final files = root.listSync().whereType<File>().toList();
      final total = files.fold<int>(0, (sum, f) => sum + f.lengthSync());
      expect(total, lessThanOrEqualTo(12));
      expect(files, isNotEmpty, reason: '至少留最新的一个（12 字节限不住一个 10 字节文件时也保留一个）');
    });

    test('未超限时不动文件', () async {
      await cache.put('k1', bytesOf(10));
      await cache.prune();
      expect(
        File('${root.path}/${RemoteThumbnailCache.fileNameFor('k1')}').existsSync(),
        isTrue,
      );
    });
  });
}
