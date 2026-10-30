import 'package:box/video/models/history_item.dart';
import 'package:box/video/pages/detail/watched_episodes.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「这集看过没有」的判定护栏。
///
/// 判错的代价是**误导**（标了"看过"其实是没看过的一集），比不标更糟，
/// 所以这里把三条判据（同一部片 / 同一集 / 真看过）逐条钉住。
HistoryItem item({
  String vodId = '1',
  String sourceId = 'q',
  String episodeUrl = 'https://m.test/1.m3u8',
  int position = 300000,
  int duration = 2700000,
}) {
  return HistoryItem(
    vodId: vodId,
    vodName: '初次爱你',
    vodPic: '',
    sourceId: sourceId,
    sourceName: '量子资源',
    episodeName: '第01集',
    episodeUrl: episodeUrl,
    position: position,
    duration: duration,
    updateTime: 0,
  );
}

void main() {
  group('episodeKeyOf：同一集要归一到同一个键', () {
    test('去掉 query 与 fragment', () {
      expect(
        episodeKeyOf('https://m.test/1.m3u8?from=abc'),
        'https://m.test/1.m3u8',
      );
      expect(
        episodeKeyOf('https://m.test/1.m3u8#t=10'),
        'https://m.test/1.m3u8',
      );
      expect(episodeKeyOf('  https://m.test/1.m3u8  '), 'https://m.test/1.m3u8');
    });

    test('空串仍然是空串（不能变成能命中一切的键）', () {
      expect(episodeKeyOf(''), '');
      expect(episodeKeyOf('   '), '');
      expect(episodeKeyOf('?x=1'), '');
    });

    test('不同集必须得到不同键', () {
      expect(
        episodeKeyOf('https://m.test/1.m3u8'),
        isNot(episodeKeyOf('https://m.test/2.m3u8')),
      );
    });
  });

  group('watchedEpisodeKeys：三条判据', () {
    test('同一部片 + 同一集 + 进度够 → 算看过', () {
      final keys = watchedEpisodeKeys(
        [item(episodeUrl: 'https://m.test/1.m3u8', position: 200000)],
        vodId: '1',
      );
      expect(keys, contains('https://m.test/1.m3u8'));
      expect(isEpisodeWatched(keys, 'https://m.test/1.m3u8'), isTrue);
      expect(isEpisodeWatched(keys, 'https://m.test/2.m3u8'), isFalse);
    });

    test('别的片子的历史不算（vodId 不同）', () {
      final keys = watchedEpisodeKeys(
        [item(vodId: '999', episodeUrl: 'https://m.test/1.m3u8')],
        vodId: '1',
      );
      expect(keys, isEmpty);
    });

    test('只点进去看一眼（< 1 分钟）不算看过', () {
      final keys = watchedEpisodeKeys(
        [item(position: 2000)],
        vodId: '1',
      );
      expect(keys, isEmpty, reason: '播放器一初始化就会落记录，门槛太低等于全标');
    });

    test('恰好 1 分钟算看过（边界）', () {
      final keys = watchedEpisodeKeys(
        [item(position: watchedThreshold)],
        vodId: '1',
      );
      expect(keys, isNotEmpty);
    });

    test('换源看过的集也要标出来（不按 sourceId 过滤）', () {
      // 用户在 A 源看过第 8 集，换到 B 源同一部片，同一集地址相同 → 该标。
      final keys = watchedEpisodeKeys(
        [
          item(sourceId: 'sourceA', episodeUrl: 'https://a.test/8.m3u8'),
          item(sourceId: 'sourceB', episodeUrl: 'https://b.test/8.m3u8'),
        ],
        vodId: '1',
      );
      expect(keys, containsAll(<String>[
        'https://a.test/8.m3u8',
        'https://b.test/8.m3u8',
      ]));
    });

    test('脏数据：地址带查询串、前后有空格、vodId 带空格也要认得', () {
      final keys = watchedEpisodeKeys(
        [
          item(
            vodId: ' 1 ',
            episodeUrl: ' https://m.test/1.m3u8?from=web ',
          ),
        ],
        vodId: '1',
      );
      expect(isEpisodeWatched(keys, 'https://m.test/1.m3u8'), isTrue);
    });

    test('地址为空的历史不参与匹配', () {
      final keys = watchedEpisodeKeys(
        [item(episodeUrl: '   ')],
        vodId: '1',
      );
      expect(keys, isEmpty);
      expect(isEpisodeWatched(keys, '   '), isFalse);
    });

    test('vodId 为空时一律不标（避免"任何片都命中"）', () {
      final keys = watchedEpisodeKeys(
        [item(vodId: '', episodeUrl: 'https://m.test/1.m3u8')],
        vodId: '',
      );
      expect(keys, isEmpty);
    });

    test('多集历史只收齐，不互相覆盖', () {
      final keys = watchedEpisodeKeys(
        [
          item(episodeUrl: 'https://m.test/1.m3u8'),
          item(episodeUrl: 'https://m.test/2.m3u8'),
          item(episodeUrl: 'https://m.test/3.m3u8'),
        ],
        vodId: '1',
      );
      expect(keys.length, 3);
    });
  });

  group('isEpisodeWatched：空集合要安全', () {
    test('空集合对任何地址都返回 false', () {
      expect(isEpisodeWatched(<String>{}, 'https://m.test/1.m3u8'), isFalse);
    });

    test('空前地址不会被误判为命中', () {
      expect(isEpisodeWatched(<String>{'a'}, ''), isFalse);
    });
  });
}
