// 漫画图片缓存的上限与清理。
//
// 为什么单独立一份：这套图**不归** `DefaultCacheManager` 管（自己落在临时目录里），
// 单话最多 209 张 ≈ 10MB，翻几本书就上百 MB —— 没有上限、也没有界面能清，
// 用户的手机空间会被悄悄吃掉，而且以前「清理缓存」完全覆盖不到它。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/comic/domain/comic_image_cache.dart';

/// 造一份缓存目录：`名字 → 字节数`，mtime 按顺序往后排（越靠后越新）。
Future<Directory> _seedCacheDir(Map<String, (int, Duration)> spec) async {
  final root = await Directory.systemTemp.createTemp('cim_');
  final dir = Directory('${root.path}/comic_online_images');
  await dir.create(recursive: true);
  final now = DateTime.now();
  for (final e in spec.entries) {
    final f = File('${dir.path}/${e.key}');
    await f.writeAsBytes(List<int>.filled(e.value.$1, 7));
    await f.setLastModified(now.subtract(e.value.$2));
  }
  return dir;
}

void main() {
  test('超出文件数上限时删最旧的，但**最近 5 分钟内的一个都不动**', () async {
    // 4 张旧的（越来越新：a1 最旧）+ 3 张"刚下好"的（1 分钟内）。
    final dir = await _seedCacheDir({
      'a1': (10, const Duration(hours: 5)),
      'a2': (10, const Duration(hours: 4)),
      'a3': (10, const Duration(hours: 3)),
      'a4': (10, const Duration(hours: 2)),
      'n1': (10, const Duration(minutes: 1)),
      'n2': (10, const Duration(minutes: 1)),
      'n3': (10, const Duration(minutes: 1)),
    });
    final cache = ComicImageCache(
      tempDirProvider: () async => dir.parent,
      maxFiles: 4,
      maxBytes: 1024 * 1024,
    );

    await cache.pruneNow();

    final left = dir.listSync().whereType<File>().map((f) => f.uri.pathSegments.last).toSet();
    expect(left, containsAll(<String>['n1', 'n2', 'n3', 'a4']),
        reason: '刚下好的图可能正显示在屏幕上，删了会闪破图标');
    expect(left, isNot(contains('a1')), reason: '最旧的先删');
    expect(left.length, 4, reason: '删到刚好不超过上限（3 新 + 最近的那张旧图）');
  });

  test('超出字节上限时也按最旧的先删', () async {
    final dir = await _seedCacheDir({
      'big1': (1000, const Duration(hours: 3)),
      'big2': (1000, const Duration(hours: 2)),
      'big3': (1000, const Duration(hours: 1)),
      'big4': (1000, const Duration(minutes: 30)),
    });
    final cache = ComicImageCache(
      tempDirProvider: () async => dir.parent,
      maxFiles: 100,
      maxBytes: 2500,
    );

    await cache.pruneNow();

    final left = dir.listSync().whereType<File>().toList();
    final leftBytes = left.fold<int>(0, (s, f) => s + f.lengthSync());
    expect(leftBytes, lessThanOrEqualTo(2500));
    final names = left.map((f) => f.uri.pathSegments.last).toSet();
    expect(names, containsAll(<String>['big3', 'big4']), reason: '近的留着');
    expect(names, isNot(contains('big1')), reason: '最旧的先走');
  });

  test('没超上限就一点都不删（控制组）', () async {
    final dir = await _seedCacheDir({
      'a': (10, const Duration(hours: 5)),
      'b': (10, const Duration(hours: 5)),
    });
    final cache = ComicImageCache(
      tempDirProvider: () async => dir.parent,
      maxFiles: 100,
      maxBytes: 1024 * 1024,
    );

    await cache.pruneNow();

    expect(dir.listSync().whereType<File>().length, 2);
  });

  test('diskUsage / clearAll 报得出清了多少，清完目录不在', () async {
    final dir = await _seedCacheDir({
      'x': (2048, const Duration(hours: 1)),
      'y': (1024, const Duration(hours: 1)),
    });

    expect(await ComicImageCache.diskUsage(inDir: dir), 3072);

    final freed = await ComicImageCache.clearAll(inDir: dir);

    expect(freed, 3072, reason: '界面要靠这个数字说人话（清出多少）');
    expect(await dir.exists(), isFalse);
  });

  test('实例的 sizeBytes 只算自己那个目录（设置页显示占用用）', () async {
    final dir = await _seedCacheDir({'z': (512, const Duration(hours: 1))});
    final cache = ComicImageCache(tempDirProvider: () async => dir.parent);

    expect(await cache.sizeBytes(), 512);
  });
}
