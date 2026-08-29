import 'package:box/novel/core/novel_cache_keys.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归：章节缓存键必须对 URL 做 trim 归一化。
///
/// 缺陷：`NovelCacheKeys.chapter()` 内部不 trim，而 `search()` / `detail()` 都 trim。
/// 写入侧 `novel_repository.dart:163` 传原始 URL，读取/删除侧
/// `offline_cache_service.dart:142/300/360` 传 `.trim()` 后的 URL。
/// 源返回带尾空格的章节 URL 时（部分小说源确实如此）：
///   - fetchChapter 写到 key `chapter:http://x/c1 `
///   - countCachedChapters 查 key `chapter:http://x/c1` → null
/// 症状：UI 显示「已缓存 0/300 章」但磁盘已有数据，且 _clearChapterCache
/// 删不掉那些文件 —— 假未缓存 + 永久垃圾文件叠加。
void main() {
  group('章节缓存键归一化', () {
    test('尾部空格不影响键（核心回归）', () {
      expect(
        NovelCacheKeys.chapter('http://example.com/c1 '),
        NovelCacheKeys.chapter('http://example.com/c1'),
      );
    });

    test('首部空格不影响键', () {
      expect(
        NovelCacheKeys.chapter('  http://example.com/c1'),
        NovelCacheKeys.chapter('http://example.com/c1'),
      );
    });

    test('首尾混合空白（含 \\n \\t）不影响键', () {
      expect(
        NovelCacheKeys.chapter('\t http://example.com/c1 \n'),
        NovelCacheKeys.chapter('http://example.com/c1'),
      );
    });

    test('URL 内部空格保留，不同 URL 仍是不同键', () {
      expect(
        NovelCacheKeys.chapter('http://example.com/a b'),
        isNot(NovelCacheKeys.chapter('http://example.com/ab')),
      );
    });

    test('键前缀仍为 chapter:', () {
      expect(
        NovelCacheKeys.chapter(' http://example.com/c1 '),
        'chapter:http://example.com/c1',
      );
    });

    test('与 search/detail 的 trim 行为一致', () {
      expect(NovelCacheKeys.search(' 斗罗 ', 1), NovelCacheKeys.search('斗罗', 1));
      expect(
        NovelCacheKeys.detail(bookId: 'b', detailUrl: ' /d1 '),
        NovelCacheKeys.detail(bookId: 'b', detailUrl: '/d1'),
      );
    });
  });
}
