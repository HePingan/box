// test/features/home/continue_repository_test.dart
//
// 「继续使用」数据层契约。
//
// 这个区块此前是硬编码的两张卡（「小说书架」「影视搜索」），跟用户真实
// 进度无关。这里锁住接真实进度后的行为：跨来源统一按时间倒序、同一作品
// 只留最近一条、无历史时返回空（首页据此隐藏区块）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/home/data/continue_item.dart';
import 'package:box/features/home/data/continue_repository.dart';
import 'package:box/novel/core/models.dart';
import 'package:box/video/models/history_item.dart';

HistoryItem _history({
  required String vodId,
  required String name,
  String sourceId = 's1',
  String sourceName = '源A',
  String episodeName = '第1集',
  String episodeUrl = 'http://e/1',
  int position = 300,
  int duration = 1200,
  required int updateTime,
}) {
  return HistoryItem(
    vodId: vodId,
    vodName: name,
    vodPic: 'http://pic/$vodId.jpg',
    sourceId: sourceId,
    sourceName: sourceName,
    episodeName: episodeName,
    episodeUrl: episodeUrl,
    position: position,
    duration: duration,
    updateTime: updateTime,
  );
}

NovelBook _book(String id, String title) {
  return NovelBook(
    id: id,
    title: title,
    author: '作者$id',
    intro: '',
    coverUrl: 'http://cover/$id.jpg',
    detailUrl: 'http://detail/$id',
    category: '',
    status: '',
    wordCount: '',
  );
}

ReadingProgress _progress(String bookId, {required int updatedAt, String chapterTitle = '第十章 山雨'}) {
  return ReadingProgress(
    bookId: bookId,
    chapterIndex: 9,
    chapterTitle: chapterTitle,
    scrollOffset: 0,
    updatedAt: updatedAt,
  );
}

void main() {
  group('ContinueRepository 合并真实进度', () {
    test('无任何历史时返回空列表，首页据此隐藏区块', () async {
      final repo = ContinueRepository(
        loadVideoHistory: () async => const <HistoryItem>[],
        loadBookshelf: () async => const <NovelBook>[],
        loadNovelProgress: (_) async => null,
      );

      expect(await repo.load(), isEmpty);
    });

    test('影视与小说混合后按 updatedAt 倒序，不分来源', () async {
      final repo = ContinueRepository(
        loadVideoHistory: () async => [
          _history(vodId: '1', name: '剧A', updateTime: 3000),
          _history(vodId: '2', name: '剧B', updateTime: 1000),
        ],
        loadBookshelf: () async => [_book('b1', '书A'), _book('b2', '书B')],
        loadNovelProgress: (bookId) async => switch (bookId) {
          'b1' => _progress('b1', updatedAt: 4000),
          'b2' => _progress('b2', updatedAt: 2000),
          _ => null,
        },
      );

      final items = await repo.load();

      expect(
        items.map((e) => e.title).toList(),
        ['书A', '剧A', '书B', '剧B'],
        reason: '必须跨来源统一排序，不能先排完影视再排小说',
      );
    });

    test('书架里没有阅读进度的书不进「继续使用」', () async {
      final repo = ContinueRepository(
        loadVideoHistory: () async => const <HistoryItem>[],
        loadBookshelf: () async => [_book('b1', '读过的'), _book('b2', '只收藏没读')],
        loadNovelProgress: (bookId) async =>
            bookId == 'b1' ? _progress('b1', updatedAt: 5000) : null,
      );

      final items = await repo.load();

      expect(items.map((e) => e.title), ['读过的']);
    });

    test('同一部剧的多集只保留最近一条', () async {
      final repo = ContinueRepository(
        loadVideoHistory: () async => [
          _history(
            vodId: '1',
            name: '剧A',
            episodeName: '第3集',
            episodeUrl: 'http://e/3',
            updateTime: 9000,
          ),
          _history(
            vodId: '1',
            name: '剧A',
            episodeName: '第2集',
            episodeUrl: 'http://e/2',
            updateTime: 8000,
          ),
        ],
        loadBookshelf: () async => const <NovelBook>[],
        loadNovelProgress: (_) async => null,
      );

      final items = await repo.load();

      expect(items, hasLength(1));
      expect(items.single.subtitle, contains('第3集'));
    });

    test('超过上限时只取最近的若干条', () async {
      final repo = ContinueRepository(
        loadVideoHistory: () async => [
          for (var i = 0; i < 20; i++)
            _history(
              vodId: '$i',
              name: '剧$i',
              episodeUrl: 'http://e/$i',
              updateTime: i * 100,
            ),
        ],
        loadBookshelf: () async => const <NovelBook>[],
        loadNovelProgress: (_) async => null,
      );

      final items = await repo.load();

      expect(items, hasLength(ContinueRepository.maxItems));
      expect(items.first.title, '剧19', reason: '保留的应是最近的，不是最早的');
    });

    test('影视条目带封面、源名与集名，并算出进度', () async {
      final repo = ContinueRepository(
        loadVideoHistory: () async => [
          _history(
            vodId: '7',
            name: '剧七',
            sourceName: '甲源',
            episodeName: '第5集',
            position: 600,
            duration: 1200,
            updateTime: 100,
          ),
        ],
        loadBookshelf: () async => const <NovelBook>[],
        loadNovelProgress: (_) async => null,
      );

      final item = (await repo.load()).single;

      expect(item.kind, ContinueKind.video);
      expect(item.title, '剧七');
      expect(item.subtitle, '甲源 · 第5集');
      expect(item.coverUrl, 'http://pic/7.jpg');
      expect(item.progress, closeTo(0.5, 1e-9));
      expect(item.progressLabel, '50%');
    });

    test('小说条目用章节名作副标题，且不伪造整书百分比', () async {
      final repo = ContinueRepository(
        loadVideoHistory: () async => const <HistoryItem>[],
        loadBookshelf: () async => [_book('b1', '某书')],
        loadNovelProgress: (_) async =>
            _progress('b1', updatedAt: 100, chapterTitle: '第十章 山雨'),
      );

      final item = (await repo.load()).single;

      expect(item.kind, ContinueKind.novel);
      expect(item.title, '某书');
      expect(item.subtitle, '第十章 山雨');
      expect(
        item.progress,
        isNull,
        reason: 'ReadingProgress 不含总章数，算不出可信百分比就不能给一个假的',
      );
      expect(item.progressLabel, isNull);
    });

    test('任一侧读取抛异常时不拖垮另一侧', () async {
      final repo = ContinueRepository(
        loadVideoHistory: () async => throw StateError('Hive 打不开'),
        loadBookshelf: () async => [_book('b1', '书还在')],
        loadNovelProgress: (_) async => _progress('b1', updatedAt: 100),
      );

      final items = await repo.load();

      expect(items.map((e) => e.title), ['书还在']);
    });

    test('两侧都抛异常时返回空而不是抛给 UI', () async {
      final repo = ContinueRepository(
        loadVideoHistory: () async => throw StateError('x'),
        loadBookshelf: () async => throw StateError('y'),
        loadNovelProgress: (_) async => null,
      );

      expect(await repo.load(), isEmpty);
    });
  });

  group('ContinueItem 进度展示阈值', () {
    ContinueItem withProgress(double? p) => ContinueItem(
      kind: ContinueKind.video,
      id: 'x',
      title: 't',
      subtitle: 's',
      updatedAt: 0,
      progress: p,
    );

    test('刚开始看（<1%）不画进度条', () {
      expect(withProgress(0.004).hasMeaningfulProgress, isFalse);
      expect(withProgress(0.004).progressLabel, isNull);
    });

    test('已看完（>99%）不画进度条', () {
      expect(withProgress(0.999).hasMeaningfulProgress, isFalse);
    });

    test('中段进度正常展示并四舍五入', () {
      expect(withProgress(0.376).hasMeaningfulProgress, isTrue);
      expect(withProgress(0.376).progressLabel, '38%');
    });

    test('进度为 null 时不画', () {
      expect(withProgress(null).hasMeaningfulProgress, isFalse);
    });
  });
}
