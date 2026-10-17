// AI 生图下载残留（box_downloads）的用例。
//
// 背景：图下载到 `应用文档目录/box_downloads` 再交给「保存到相册 / 分享」，
// 而 Gal.putImage 只是把文件复制进相册 —— 源文件一直留着，用户看不见、
// 设置里的「清理缓存」也清不到（那是文档目录，不是缓存）。
//
// 这里只测 store 这一层的契约（注入临时目录，不碰 path_provider）：
//   1. create：目录不存在时建出来，文件名不重复；
//   2. deleteQuietly：删掉、重复删不抛；
//   3. clear：全清并报出释放字节；
//   4. prune：超上限按 mtime 先删最旧的，降到 60%，不超限时一个不动。
import 'dart:io';

import 'package:box/features/image_generator/data/ai_image_download_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory base;
  late AiImageDownloadStore store;
  late Directory downloads;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('box_ai_dl_test_');
    store = AiImageDownloadStore(dirProvider: () async => base);
    downloads = Directory('${base.path}/${AiImageDownloadStore.subdirName}');
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  /// 造一个指定大小与修改时间的文件。
  Future<File> seed(String name, int bytes, DateTime mtime) async {
    if (!await downloads.exists()) {
      await downloads.create(recursive: true);
    }
    final f = File('${downloads.path}/$name');
    await f.writeAsBytes(List<int>.filled(bytes, 0));
    await f.setLastModified(mtime);
    return f;
  }

  test('create：目录不存在时自动建，且两次不会拿到同一个文件', () async {
    expect(await downloads.exists(), isFalse);

    final a = await store.create();
    final b = await store.create();

    expect(await downloads.exists(), isTrue);
    expect(a.path, isNot(b.path));
    expect(a.path, startsWith('${downloads.path}/ai_img_'));
    expect(a.path, endsWith('.png'));
  });

  test('create：前缀可换（截屏兜底用 ai_original_）', () async {
    final f = await store.create(prefix: 'ai_original_');
    expect(f.path, contains('ai_original_'));
  });

  test('deleteQuietly：真删；重复删不抛', () async {
    final f = await store.create();
    await f.writeAsBytes([1, 2, 3]);
    expect(await f.exists(), isTrue);

    await store.deleteQuietly(f);
    expect(await f.exists(), isFalse);

    // 再删一次不能把调用点（「已保存到相册」之后）炸掉。
    await store.deleteQuietly(f);
  });

  test('deleteQuietly：文件不存在也不抛', () async {
    await store.deleteQuietly(File('${base.path}/nope.png'));
  });

  test('clear：清空目录并报出释放的字节数', () async {
    await seed('ai_img_1.png', 100, DateTime(2026, 1, 1));
    await seed('ai_img_2.png', 200, DateTime(2026, 1, 2));

    final freed = await store.clear();

    expect(freed, 300);
    expect(await downloads.list().toList(), isEmpty);
  });

  test('clear：空目录返回 0', () async {
    expect(await store.clear(), 0);
  });

  test('prune：没超上限时一个都不删', () async {
    await seed('a.png', 10, DateTime(2026, 1, 1));
    await seed('b.png', 10, DateTime(2026, 1, 2));

    expect(await store.prune(), 0);
    expect(await downloads.list().length, 2);
  });

  test('prune：超过文件数上限时按 mtime 先删最旧的，降到 60%', () async {
    // 造 maxFiles + 10 个，mtime 递增：最旧的是 i=0。
    const total = AiImageDownloadStore.maxFiles + 10;
    for (var i = 0; i < total; i++) {
      await seed(
        'ai_img_$i.png',
        10,
        DateTime(2026, 1, 1).add(Duration(minutes: i)),
      );
    }

    final freed = await store.prune();
    final all = await downloads.list().toList();
    final left = all.whereType<File>().toList();

    expect(freed, greaterThan(0));
    expect(
      left.length,
      lessThanOrEqualTo(AiImageDownloadStore.maxFiles),
      reason: '收完必须在上限内',
    );
    expect(
      left.length,
      greaterThanOrEqualTo((AiImageDownloadStore.maxFiles * 0.6).floor()),
      reason: '一次删到 60% 就够，不该清空',
    );
    // 最旧的那批应该没了，最新的还在。
    expect(await File('${downloads.path}/ai_img_0.png').exists(), isFalse);
    expect(
      await File('${downloads.path}/ai_img_${total - 1}.png').exists(),
      isTrue,
    );
  });

  test('prune：文件数没超但字节数超了，也按 mtime 删最旧的', () async {
    const big = 30 * 1024 * 1024; // 30MB × 4 = 120MB > 80MB 上限
    for (var i = 0; i < 4; i++) {
      await seed(
        'ai_img_$i.png',
        big,
        DateTime(2026, 1, 1).add(Duration(minutes: i)),
      );
    }

    final freed = await store.prune();

    expect(freed, greaterThan(0));
    expect(
      await File('${downloads.path}/ai_img_0.png').exists(),
      isFalse,
      reason: '最旧的先走',
    );
  });
}
