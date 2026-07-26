import 'aggregate_result.dart';

/// 聚合搜索按片名归并后的结果组。
///
/// 同一片名可能来自多个视频源、或同源多个条目，这里归并为一个组：
/// - [title]：展示用片名（取首个非空原始片名）
/// - [hitCount]：命中的源数量（去重后），用于排序，越多越靠前
/// - [results]：该片名下的全部结果（已按源去重）
class AggregateGroupedResult {
  final String title;
  final List<AggregateResult> results;

  const AggregateGroupedResult({required this.title, required this.results});

  /// 命中的不同源数量（去重后）。
  int get hitCount {
    final sourceKeys = <String>{};
    for (final r in results) {
      sourceKeys.add(_sourceKeyOf(r));
    }
    return sourceKeys.length;
  }

  /// 首选展示结果：优先带封面，其次首个。
  AggregateResult get primary {
    for (final r in results) {
      final pic = r.video.vodPic?.trim() ?? '';
      if (pic.isNotEmpty) return r;
    }
    return results.first;
  }

  static String _sourceKeyOf(AggregateResult r) {
    final id = r.source.id.trim();
    if (id.isNotEmpty && id.toLowerCase() != 'null') return id;
    final url = r.source.url.trim();
    if (url.isNotEmpty) return url;
    return r.source.name.trim();
  }

  /// 组内最大年份（从 vodYear 解析，取首个 1900~2099 的四位数）。
  /// 无有效年份返回 0，用于「最新年份」排序时垫底。
  int get latestYear {
    var best = 0;
    for (final r in results) {
      final y = _parseYear(r.video.vodYear) ?? _parseYear(r.video.vodName);
      if (y != null && y > best) best = y;
    }
    return best;
  }

  static int? _parseYear(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return null;
    final match = RegExp(r'(19|20)\d{2}').firstMatch(text);
    if (match == null) return null;
    return int.tryParse(match.group(0)!);
  }
}

/// 聚合结果组的排序方式。
enum AggregateSortMode {
  /// 命中源数最多优先（默认，越多越可能是热门/资源全）。
  hitCount,

  /// 最新年份优先。
  year,

  /// 片名拼音/字典序。
  title,
}

extension AggregateSortModeLabel on AggregateSortMode {
  String get label {
    switch (this) {
      case AggregateSortMode.hitCount:
        return '综合';
      case AggregateSortMode.year:
        return '最新';
      case AggregateSortMode.title:
        return '片名';
    }
  }
}

/// 对已归并的结果组按给定方式排序，并可选只保留多源命中的组。
///
/// - [mode]：排序方式，见 [AggregateSortMode]。
/// - [multiSourceOnly]：为 true 时只保留 hitCount >= 2 的组（过滤单源冷门）。
/// 排序稳定：比较键相等时保持原有（命中源数倒序）顺序。
List<AggregateGroupedResult> sortAndFilterGroups(
  List<AggregateGroupedResult> groups, {
  AggregateSortMode mode = AggregateSortMode.hitCount,
  bool multiSourceOnly = false,
}) {
  var list = groups;
  if (multiSourceOnly) {
    list = list.where((g) => g.hitCount >= 2).toList();
  } else {
    list = List<AggregateGroupedResult>.of(list);
  }

  // 记录原始下标做稳定回退。
  final indexOf = <AggregateGroupedResult, int>{};
  for (var i = 0; i < list.length; i++) {
    indexOf[list[i]] = i;
  }

  int cmp(AggregateGroupedResult a, AggregateGroupedResult b) {
    switch (mode) {
      case AggregateSortMode.hitCount:
        final byHit = b.hitCount.compareTo(a.hitCount);
        return byHit != 0 ? byHit : indexOf[a]!.compareTo(indexOf[b]!);
      case AggregateSortMode.year:
        final byYear = b.latestYear.compareTo(a.latestYear);
        return byYear != 0 ? byYear : indexOf[a]!.compareTo(indexOf[b]!);
      case AggregateSortMode.title:
        final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        return byTitle != 0 ? byTitle : indexOf[a]!.compareTo(indexOf[b]!);
    }
  }

  list.sort(cmp);
  return list;
}

/// 片名归一化：去除空白、全角/半角括号内容与常见修饰后缀，用于归并判重。
String normalizeFilmTitle(String rawTitle) {
  var title = rawTitle.trim();
  if (title.isEmpty) return '';

  // 去掉括号及其内容（版本/清晰度/年份等修饰）
  title = title.replaceAll(RegExp(r'[（(【\[].*?[）)】\]]'), '');

  // 去掉常见清晰度/版本尾缀
  title = title.replaceAll(
    RegExp(
      r'(高清|超清|蓝光|国语|粤语|中字|抢先版|TC|HD|BD|4K|1080P|720P|完结|未删减版?)',
      caseSensitive: false,
    ),
    '',
  );

  // 折叠所有空白与常见分隔符
  title = title.replaceAll(RegExp(r'[\s·:：\-_/|]+'), '');

  return title.toLowerCase();
}

/// 将聚合结果按归一化片名归并、去重、按命中源数排序。
///
/// - 同一片名下，同一源只保留第一条（去重）。
/// - 组间按 [AggregateGroupedResult.hitCount] 倒序；相同命中数保持稳定顺序。
List<AggregateGroupedResult> groupResultsByFilmName(
  List<AggregateResult> results,
) {
  final buckets = <String, List<AggregateResult>>{};
  final titleOf = <String, String>{};
  final order = <String>[];

  for (final result in results) {
    final rawName = result.video.vodName.trim();
    if (rawName.isEmpty) continue;

    final key = normalizeFilmTitle(rawName);
    if (key.isEmpty) continue;

    if (!buckets.containsKey(key)) {
      buckets[key] = <AggregateResult>[];
      titleOf[key] = rawName;
      order.add(key);
    }

    final bucket = buckets[key]!;
    final sourceKey = AggregateGroupedResult._sourceKeyOf(result);
    final alreadyHasSource = bucket.any(
      (r) => AggregateGroupedResult._sourceKeyOf(r) == sourceKey,
    );
    if (!alreadyHasSource) {
      bucket.add(result);
    }
  }

  final groups = <AggregateGroupedResult>[];
  for (final key in order) {
    groups.add(
      AggregateGroupedResult(title: titleOf[key]!, results: buckets[key]!),
    );
  }

  // 稳定排序：命中源数倒序
  for (var i = 0; i < groups.length; i++) {
    for (var j = 0; j < groups.length - 1 - i; j++) {
      if (groups[j].hitCount < groups[j + 1].hitCount) {
        final tmp = groups[j];
        groups[j] = groups[j + 1];
        groups[j + 1] = tmp;
      }
    }
  }

  return groups;
}
