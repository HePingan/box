import 'package:flutter_test/flutter_test.dart';

import 'package:box/video/models/aggregate_grouped_result.dart';
import 'package:box/video/models/aggregate_result.dart';
import 'package:box/video/models/video_source.dart';
import 'package:box/video/models/vod_item.dart';

/// 构造一个最小可用的 VideoSource（仅 id 影响去重与命中源计数）。
VideoSource _source(String id) =>
    VideoSource(id: id, name: '源$id', url: 'http://$id', detailUrl: 'http://$id');

/// 构造一个最小可用的 VodItem。vodName / vodYear 参与归并与排序。
VodItem _vod(String name, {String year = '', int id = 1}) => VodItem(
  vodId: id,
  vodName: name,
  vodPic: 'http://pic/$name.jpg',
  vodYear: year,
);

AggregateResult _result(String sourceId, String name, {String year = ''}) =>
    AggregateResult(source: _source(sourceId), video: _vod(name, year: year));

void main() {
  group('groupResultsByFilmName', () {
    test('同片名多源归并为一组，命中源数正确', () {
      final results = [
        _result('a', '流浪地球'),
        _result('b', '流浪地球'),
        _result('c', '沙丘'),
      ];
      final groups = groupResultsByFilmName(results);
      expect(groups.length, 2);
      // 命中源多的排前面
      expect(groups.first.title, '流浪地球');
      expect(groups.first.hitCount, 2);
      expect(groups.last.hitCount, 1);
    });

    test('同源同片名去重，只保留一条', () {
      final results = [
        _result('a', '沙丘'),
        _result('a', '沙丘'), // 同源重复
      ];
      final groups = groupResultsByFilmName(results);
      expect(groups.length, 1);
      expect(groups.first.hitCount, 1);
      expect(groups.first.results.length, 1);
    });

    test('清晰度/括号尾缀归一化后视为同片', () {
      final results = [
        _result('a', '沙丘'),
        _result('b', '沙丘(高清)'),
        _result('c', '沙丘 1080P'),
      ];
      final groups = groupResultsByFilmName(results);
      expect(groups.length, 1);
      expect(groups.first.hitCount, 3);
    });
  });

  group('latestYear', () {
    test('从 vodYear 取组内最大年份', () {
      final group = groupResultsByFilmName([
        _result('a', '某剧', year: '2021'),
        _result('b', '某剧', year: '2023'),
      ]).first;
      expect(group.latestYear, 2023);
    });

    test('vodYear 缺失时回退到片名中的年份', () {
      final group = groupResultsByFilmName([
        _result('a', '某片 2019'),
      ]).first;
      expect(group.latestYear, 2019);
    });

    test('无任何年份返回 0', () {
      final group = groupResultsByFilmName([
        _result('a', '无年片'),
      ]).first;
      expect(group.latestYear, 0);
    });
  });

  group('sortAndFilterGroups', () {
    List<AggregateGroupedResult> baseGroups() => groupResultsByFilmName([
      // A: 单源, 2023
      _result('a', 'Alpha', year: '2023'),
      // B: 双源, 2020
      _result('a', 'Beta', year: '2020'),
      _result('b', 'Beta', year: '2020'),
      // C: 三源, 2019
      _result('a', 'Gamma', year: '2019'),
      _result('b', 'Gamma', year: '2019'),
      _result('c', 'Gamma', year: '2019'),
    ]);

    test('默认 hitCount 排序：命中源多的在前', () {
      final sorted = sortAndFilterGroups(baseGroups());
      expect(sorted.map((g) => g.title).toList(), ['Gamma', 'Beta', 'Alpha']);
    });

    test('year 排序：最新年份在前', () {
      final sorted = sortAndFilterGroups(
        baseGroups(),
        mode: AggregateSortMode.year,
      );
      expect(sorted.first.title, 'Alpha'); // 2023
      expect(sorted.last.title, 'Gamma'); // 2019
    });

    test('title 排序：字典序', () {
      final sorted = sortAndFilterGroups(
        baseGroups(),
        mode: AggregateSortMode.title,
      );
      expect(sorted.map((g) => g.title).toList(), ['Alpha', 'Beta', 'Gamma']);
    });

    test('multiSourceOnly 过滤掉单源组', () {
      final sorted = sortAndFilterGroups(
        baseGroups(),
        multiSourceOnly: true,
      );
      expect(sorted.map((g) => g.title).toList(), ['Gamma', 'Beta']);
      expect(sorted.every((g) => g.hitCount >= 2), isTrue);
    });

    test('排序不改动原始列表', () {
      final groups = baseGroups();
      final before = groups.map((g) => g.title).toList();
      sortAndFilterGroups(groups, mode: AggregateSortMode.title);
      expect(groups.map((g) => g.title).toList(), before);
    });
  });

  group('AggregateSortModeLabel', () {
    test('每个模式都有中文标签', () {
      expect(AggregateSortMode.hitCount.label, '综合');
      expect(AggregateSortMode.year.label, '最新');
      expect(AggregateSortMode.title.label, '片名');
    });
  });
}
