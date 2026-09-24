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

  group('占用统计（283 D3）', () {
    test('空缓存：0 张 0 字节', () async {
      final usage = await cache.usage();
      expect(usage.files, 0);
      expect(usage.bytes, 0);
      expect(usage.isEmpty, isTrue);
    });

    test('put 之后能报出文件数与总字节（含内存张数）', () async {
      await cache.put('k1', bytesOf(100));
      await cache.put('k2', bytesOf(250));

      final usage = await cache.usage();
      expect(usage.files, 2);
      expect(usage.bytes, 350);
      expect(usage.memoryCount, 2);
      expect(usage.isEmpty, isFalse);
    });

    test('文件被外部删掉后统计跟着变（数的是磁盘实况，不是记账）', () async {
      await cache.put('k1', bytesOf(100));
      await File(
        '${root.path}/${RemoteThumbnailCache.fileNameFor('k1')}',
      ).delete();

      final usage = await cache.usage();
      expect(usage.files, 0);
      expect(usage.bytes, 0);
      expect(usage.memoryCount, 1, reason: '内存里还有一份（没读盘不算丢）');
    });

    test('清空后占用归零', () async {
      await cache.put('k1', bytesOf(100));
      await cache.clear();

      final usage = await cache.usage();
      expect(usage.files, 0);
      expect(usage.bytes, 0);
      expect(usage.memoryCount, 0);
      expect(usage.isEmpty, isTrue);
    });

    test('修剪后统计反映真实剩余（数的是磁盘实况）', () async {
      // 直接铺文件而不是走 put：put 会顺手触发一次异步修剪，
      // 与本用例显式调用的 prune 交错时删除次数不可预期。
      final dir = Directory(root.path);
      if (!await dir.exists()) await dir.create(recursive: true);
      for (var i = 0; i < 8; i++) {
        await File(
          '${dir.path}/${RemoteThumbnailCache.fileNameFor('k$i')}',
        ).writeAsBytes(bytesOf(64));
      }

      final small = RemoteThumbnailCache(
        root: dir,
        maxFiles: 5,
        maxBytes: 1 << 20,
      );
      await small.prune();

      final usage = await small.usage();
      expect(usage.files, 5, reason: '修剪到上限');
      expect(usage.bytes, 5 * 64);
    });
  });

  group('账户作用域与按账户清理（284 P1）', () {
    test('带作用域存取：落在子目录，get 仍命中', () async {
      await cache.put('accA|/photo.jpg|100', bytesOf(12), scope: 'accA');
      final scopeDir = Directory(
        '${root.path}/${RemoteThumbnailCache.scopeDirName('accA')}',
      );
      expect(
        await scopeDir.exists(),
        isTrue,
        reason: '作用域必须落在目录上：文件名是键的 sha1，反推不出账户',
      );
      expect(
        (await scopeDir.list().toList()).whereType<File>(),
        hasLength(1),
      );

      cache.clearMemory();
      final got = await cache.get('accA|/photo.jpg|100', scope: 'accA');
      expect(got, isNotNull);
      expect(got!.length, 12);
    });

    test('不传作用域仍落根目录（无账户/测试场景）', () async {
      await cache.put('k1', bytesOf(8));
      final file = File(
        '${root.path}/${RemoteThumbnailCache.fileNameFor('k1')}',
      );
      expect(await file.exists(), isTrue);
    });

    test('占用统计含子目录（否则 32MB 上限会被绕过）', () async {
      await cache.put('accA|/a.jpg|1', bytesOf(64), scope: 'accA');
      await cache.put('accB|/b.jpg|1', bytesOf(32), scope: 'accB');
      await cache.put('plain', bytesOf(16));

      final usage = await cache.usage();
      expect(usage.files, 3);
      expect(usage.bytes, 64 + 32 + 16);
    });

    test('修剪也扫子目录', () async {
      final small = RemoteThumbnailCache(
        root: root,
        maxFiles: 2,
        maxBytes: 1 << 20,
      );
      for (var i = 0; i < 4; i++) {
        await cache.put('accA|/$i.jpg|1', bytesOf(32), scope: 'accA');
      }
      await small.prune();

      final usage = await small.usage();
      expect(usage.files, 2, reason: '子目录里的图也要被修剪');
    });

    test('clearScope 只清该账户：别的账户与根目录条目保留', () async {
      await cache.put('accA|/a.jpg|1', bytesOf(10), scope: 'accA');
      // EXIF 变体（键是 `...|exif`）也要一起清掉。
      await cache.put('accA|/a.jpg|1|exif', bytesOf(11), scope: 'accA');
      await cache.put('accB|/b.jpg|1', bytesOf(20), scope: 'accB');
      await cache.put('plain', bytesOf(30));

      expect(await cache.clearScope('accA'), 2);

      expect(await cache.get('accA|/a.jpg|1', scope: 'accA'), isNull);
      expect(await cache.get('accA|/a.jpg|1|exif', scope: 'accA'), isNull);
      expect(await cache.get('accB|/b.jpg|1', scope: 'accB'), isNotNull);
      expect(await cache.get('plain'), isNotNull);
      expect((await cache.usage()).files, 2);
    });

    test('clearScope 对不存在的账户返回 0 且不动别人', () async {
      await cache.put('accB|/b.jpg|1', bytesOf(20), scope: 'accB');
      expect(await cache.clearScope('accA'), 0);
      expect(await cache.get('accB|/b.jpg|1', scope: 'accB'), isNotNull);
    });

    test('作用域按 | 收边：accA 不会清到 accAA', () async {
      await cache.put('accA|/a.jpg|1', bytesOf(10), scope: 'accA');
      await cache.put('accAA|/a.jpg|1', bytesOf(10), scope: 'accAA');
      expect(await cache.clearScope('accA'), 1);
      expect(await cache.get('accAA|/a.jpg|1', scope: 'accAA'), isNotNull);
    });
  });
}
