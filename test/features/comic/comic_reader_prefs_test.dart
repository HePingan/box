// 阅读器偏好的用例（翻页方式：竖向连续 / 左右翻页）。
//
// 锁住两件事：
//   ① 默认是**竖向连续**（条漫更顺）；读不出来也当竖向 —— 默认值不能选"看起来像卡住"的那个；
//   ② 用户改了就记住（下次进来还是他选的那个）。
library;

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/comic/domain/comic_reader_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('默认竖向连续；改了就记住', () async {
    // 同一个存储实例 = 同一份偏好（inMemory 每个实例各存各的）
    final cache = CacheStore.inMemory('comic_reader_prefs_test');
    final prefs = ComicReaderPrefs(cacheStore: cache);

    expect(await prefs.pageTurn(), isFalse, reason: '默认竖向（条漫更顺）');

    await prefs.setPageTurn(true);
    expect(await prefs.pageTurn(), isTrue);

    // 换一个实例读同一份存储：偏好是"全 App 一份"，不是某本书的属性
    final again = ComicReaderPrefs(cacheStore: cache);
    expect(await again.pageTurn(), isTrue);

    await prefs.setPageTurn(false);
    expect(await prefs.pageTurn(), isFalse);
  });
}
