import 'dart:async';

import 'archive_video_source.dart';
import 'licensed_catalog_video_source.dart';
import 'models.dart';
import 'sample_video_source.dart';
import 'video_source.dart';

class CompositeVideoSource implements VideoSource {
  CompositeVideoSource({
    ArchiveVideoSource? archive,
    SampleVideoSource? sample,
    List<VideoSource>? sources,
    this.displayName = '聚合影视源',
    this.aggregateSameTitle = true,
    this.maxAggregatedCandidates = 8,
  }) : sources = List<VideoSource>.unmodifiable(
          sources ??
              [
                if (archive != null) archive,
                if (sample != null) sample,
              ],
        ) {
    if (this.sources.isEmpty) {
      throw ArgumentError('CompositeVideoSource.sources 不能为空');
    }
  }

  final List<VideoSource> sources;
  final String displayName;
  final bool aggregateSameTitle;
  final int maxAggregatedCandidates;

  static const String _aggregateProviderKey = 'aggregate';

  @override
  String get sourceName => displayName;

  @override
  List<VideoCategory> get categories {
    final grouped = <String, List<_SourceCategoryRef>>{};

    for (var i = 0; i < sources.length; i++) {
      final source = sources[i];
      for (final category in source.categories) {
        final key = '${category.id}|${category.title}|${category.query}';
        grouped.putIfAbsent(key, () => []).add(
              _SourceCategoryRef(
                sourceIndex: i,
                category: category,
              ),
            );
      }
    }

    final result = <VideoCategory>[];

    for (final refs in grouped.values) {
      final first = refs.first.category;
      if (refs.length > 1) {
        result.add(first);
        continue;
      }

      final ref = refs.first;
      result.add(
        VideoCategory(
          id: first.id,
          title: first.title,
          query: _encodeRoutedQuery(ref.sourceIndex, first.query),
          description: first.description,
        ),
      );
    }
    return result;
  }

  // ----- Stream 流式返回（边搜索边返回聚合去重数据） -----

  Stream<List<VideoItem>> searchVideosStream(String keyword, {int page = 1}) {
    return _streamAllSources(
      (s) => s.searchVideos(keyword, page: page),
      (s) {
        if (s is LicensedCatalogVideoSource) return s.searchVideosStream(keyword, page: page);
        if (s is CompositeVideoSource) return s.searchVideosStream(keyword, page: page);
        return Stream.fromFuture(s.searchVideos(keyword, page: page));
      },
    );
  }

  Stream<List<VideoItem>> fetchByPathStream(String path, {int page = 1}) async* {
    final routed = _decodeRoutedQuery(path);

    if (routed != null) {
      final sourceIndex = routed.sourceIndex;
      if (sourceIndex >= 0 && sourceIndex < sources.length) {
        final source = sources[sourceIndex];
        Stream<List<VideoItem>> targetStream;
        
        if (source is LicensedCatalogVideoSource) {
           targetStream = source.fetchByPathStream(routed.rawQuery, page: page);
        } else if (source is CompositeVideoSource) {
           targetStream = source.fetchByPathStream(routed.rawQuery, page: page);
        } else {
           targetStream = Stream.fromFuture(source.fetchByPath(routed.rawQuery, page: page));
        }

        await for (final items in targetStream) {
          yield _mergeItems(items);
        }
        return;
      }
    }

    yield* _streamAllSources(
      (s) => s.fetchByPath(path, page: page),
      (s) {
        if (s is LicensedCatalogVideoSource) return s.fetchByPathStream(path, page: page);
        if (s is CompositeVideoSource) return s.fetchByPathStream(path, page: page);
        return Stream.fromFuture(s.fetchByPath(path, page: page));
      },
    );
  }

  Stream<List<VideoItem>> _streamAllSources(
    Future<List<VideoItem>> Function(VideoSource source) futureCall,
    Stream<List<VideoItem>> Function(VideoSource source) streamCall,
  ) async* {
    final sourceResults = List<List<VideoItem>>.generate(sources.length, (_) => []);
    final controller = StreamController<List<VideoItem>>();
    int pending = sources.length;

    if (sources.isEmpty) {
      controller.close();
      yield* controller.stream;
      return;
    }

    void emit() {
      if (controller.isClosed) return;
      final combined = sourceResults.expand((e) => e).toList();
      controller.add(_mergeItems(combined));
    }

    for (var i = 0; i < sources.length; i++) {
      final source = sources[i];
      Future<void>(() async {
        try {
          if (source is LicensedCatalogVideoSource || source is CompositeVideoSource) {
            await for (final partial in streamCall(source)) {
              sourceResults[i] = partial;
              emit();
            }
          } else {
            final res = await futureCall(source);
            sourceResults[i] = res;
            emit();
          }
        } catch (_) {
        } finally {
          pending--;
          if (pending == 0) controller.close();
        }
      });
    }

    yield* controller.stream;
  }

  // ----- 兼容底层接口 -----

  @override
  Future<List<VideoItem>> searchVideos(String keyword, {int page = 1}) async {
    List<VideoItem> result = [];
    await for (final items in searchVideosStream(keyword, page: page)) {
      result = items;
    }
    return result;
  }

  @override
  Future<List<VideoItem>> fetchByPath(String path, {int page = 1}) async {
    List<VideoItem> result = [];
    await for (final items in fetchByPathStream(path, page: page)) {
      result = items;
    }
    return result;
  }

  // ----- 详情页与去重聚合核心 -----

  @override
  Future<VideoDetail> fetchDetail({
    required VideoItem item,
  }) async {
    final candidates = item.detailCandidates
        .where((e) => e.title.trim().isNotEmpty || e.id.trim().isNotEmpty)
        .take(maxAggregatedCandidates)
        .toList();

    if (candidates.length <= 1) {
      return _fetchSingleDetail(candidates.isNotEmpty ? candidates.first : item);
    }

    final results = await Future.wait(
      candidates.map((candidate) async {
        try {
          return await _fetchSingleDetail(candidate);
        } catch (_) {
          return null;
        }
      }),
    );

    final details = results.whereType<VideoDetail>().toList();
    if (details.isEmpty) {
      throw Exception('聚合详情失败，当前所有候选片源都不可用');
    }

    final mergedPlaySources = _mergePlaySources(details);
    final preferred = _pickPreferredDetail(details, fallback: item);

    final mergedItem = preferred.item.copyWith(
      id: item.id.isNotEmpty ? item.id : preferred.item.id,
      title: item.title.isNotEmpty ? item.title : preferred.item.title,
      detailUrl: preferred.sourceUrl.isNotEmpty ? preferred.sourceUrl : preferred.item.detailUrl,
      cover: _pickFirstNonEmpty([
        preferred.cover, preferred.item.cover, item.cover,
        ...details.map((e) => e.cover), ...details.map((e) => e.item.cover),
      ]),
      intro: _pickLongestText([
        preferred.description, preferred.item.intro, item.intro,
        ...details.map((e) => e.description), ...details.map((e) => e.item.intro),
      ]),
      subtitle: item.subtitle.isNotEmpty ? item.subtitle : preferred.item.subtitle,
      category: item.category.isNotEmpty ? item.category : preferred.item.category,
      yearText: item.yearText.isNotEmpty ? item.yearText : preferred.item.yearText,
      sourceName: details.length > 1 ? '多源聚合' : preferred.item.sourceName,
      providerKey: details.length > 1 ? _aggregateProviderKey : preferred.item.providerKey,
      area: item.area.isNotEmpty ? item.area : preferred.item.area,
      remark: item.remark.isNotEmpty ? item.remark : preferred.item.remark,
      mergedItems: candidates.map((e) => e.copyWith(mergedItems: const [])).toList(),
    );

    return VideoDetail(
      item: mergedItem,
      cover: mergedItem.cover,
      creator: _pickFirstNonEmpty([preferred.creator, ...details.map((e) => e.creator)]),
      description: _pickLongestText([preferred.description, ...details.map((e) => e.description), mergedItem.intro]),
      tags: details.expand((e) => e.tags).map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList(),
      playSources: mergedPlaySources,
      sourceUrl: preferred.sourceUrl,
    );
  }

  Future<VideoDetail> _fetchSingleDetail(VideoItem item) async {
    Object? lastError;
    final prioritized = <VideoSource>[];
    final seen = <int>{};

    void addSource(VideoSource source) {
      if (seen.add(identityHashCode(source))) prioritized.add(source);
    }

    for (final source in sources) {
      if (item.sourceName.isNotEmpty && source.sourceName == item.sourceName) addSource(source);
    }
    for (final source in sources) addSource(source);

    for (final source in prioritized) {
      try {
        return await source.fetchDetail(item: item);
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('获取详情失败：$lastError');
  }

  List<VideoItem> _mergeItems(List<VideoItem> raw) {
    final dedup = <String, VideoItem>{};

    for (final item in raw) {
      if (item.title.trim().isEmpty && item.id.trim().isEmpty) continue;
      dedup.putIfAbsent(
        _identityKey(item),
        () => item.copyWith(mergedItems: const []),
      );
    }

    final distinct = dedup.values.toList();
    if (!aggregateSameTitle) {
      distinct.sort(_compareItemForList);
      return distinct;
    }

    final groups = <String, List<VideoItem>>{};
    for (final item in distinct) {
      groups.putIfAbsent(_aggregateKey(item), () => []).add(item);
    }

    final result = groups.values.map(_mergeGroupToRepresentative).toList();
    result.sort(_compareItemForList);
    return result;
  }

  VideoItem _mergeGroupToRepresentative(List<VideoItem> group) {
    if (group.length == 1) return group.first;
    final sorted = [...group]..sort((a, b) => _qualityScore(b).compareTo(_qualityScore(a)));
    final best = sorted.first;

    return best.copyWith(
      sourceName: '多源聚合',
      providerKey: _aggregateProviderKey,
      cover: _pickFirstNonEmpty(group.map((e) => e.cover).toList()),
      intro: _pickLongestText(group.map((e) => e.intro).toList()),
      subtitle: _pickFirstNonEmpty([...group.map((e) => e.subtitle), ...group.map((e) => e.remark)]),
      category: _pickFirstNonEmpty(group.map((e) => e.category).toList()),
      yearText: _pickFirstNonEmpty(group.map((e) => e.yearText).toList()),
      area: _pickFirstNonEmpty(group.map((e) => e.area).toList()),
      remark: _pickFirstNonEmpty(group.map((e) => e.remark).toList()),
      mergedItems: group.map((e) => e.copyWith(mergedItems: const [])).toList(),
    );
  }

  List<VideoPlaySource> _mergePlaySources(List<VideoDetail> details) {
    final result = <VideoPlaySource>[];
    final nameCount = <String, int>{};

    for (final detail in details) {
      final siteName = detail.item.sourceName.trim().isNotEmpty
          ? detail.item.sourceName.trim()
          : detail.item.providerKey.trim();

      for (final playSource in detail.playSources) {
        final episodes = _dedupEpisodes(playSource.episodes);
        if (episodes.isEmpty) continue;

        final baseName = siteName.isNotEmpty ? '$siteName · ${playSource.name}' : playSource.name;
        final count = (nameCount[baseName] ?? 0) + 1;
        nameCount[baseName] = count;
        final finalName = count == 1 ? baseName : '$baseName #$count';

        result.add(
          VideoPlaySource(
            name: finalName,
            episodes: episodes.asMap().entries.map((e) => e.value.copyWith(index: e.key)).toList(),
          ),
        );
      }
    }
    return result;
  }

  List<VideoEpisode> _dedupEpisodes(List<VideoEpisode> episodes) {
    final seen = <String>{};
    final result = <VideoEpisode>[];
    for (final episode in episodes) {
      final url = episode.url.trim();
      if (url.isEmpty) continue;
      if (!seen.add('${episode.title.trim()}|$url')) continue;
      result.add(episode.copyWith(index: result.length));
    }
    return result;
  }

  VideoDetail _pickPreferredDetail(List<VideoDetail> details, {required VideoItem fallback}) {
    final sorted = [...details]..sort((a, b) => _detailQualityScore(b).compareTo(_detailQualityScore(a)));
    return sorted.isNotEmpty ? sorted.first : VideoDetail(item: fallback, playSources: const []);
  }

  int _compareItemForList(VideoItem a, VideoItem b) {
    final sourceCompare = b.mergedSourceCount.compareTo(a.mergedSourceCount);
    if (sourceCompare != 0) return sourceCompare;
    final scoreCompare = _qualityScore(b).compareTo(_qualityScore(a));
    if (scoreCompare != 0) return scoreCompare;
    return a.title.compareTo(b.title);
  }

  int _qualityScore(VideoItem item) {
    var score = 0;
    if (item.cover.trim().isNotEmpty) score += 4;
    if (item.intro.trim().isNotEmpty) score += 3;
    if (item.yearText.trim().isNotEmpty) score += 2;
    if (item.category.trim().isNotEmpty) score += 1;
    if (item.remark.trim().isNotEmpty || item.subtitle.trim().isNotEmpty) score += 1;
    score += item.mergedSourceCount * 2;
    return score;
  }

  int _detailQualityScore(VideoDetail detail) {
    var score = 0;
    if (detail.cover.trim().isNotEmpty) score += 2;
    if (detail.description.trim().isNotEmpty) score += 3;
    if (detail.creator.trim().isNotEmpty) score += 1;
    score += detail.playSources.length * 3;
    score += detail.playSources.fold<int>(0, (sum, e) => sum + e.episodes.length);
    return score;
  }

  String _identityKey(VideoItem item) => '${item.providerKey}|${item.id}|${item.detailUrl}';

  String _aggregateKey(VideoItem item) {
    final title = _normalizeTitle(item.title);
    if (title.isEmpty) return _identityKey(item);
    final year = _normalizeText(item.yearText);
    if (year.isNotEmpty) return '$title|$year';
    final category = _normalizeText(item.category);
    if (category.isNotEmpty) return '$title|$category';
    return title;
  }

  String _normalizeTitle(String input) => input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r'[【】\[\]\(\)（）《》·\-_.:,，。：；!！?？]'), '');
  String _normalizeText(String input) => input.trim().toLowerCase();

  String _pickFirstNonEmpty(List<String> values) {
    for (final value in values) {
      if (value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  String _pickLongestText(List<String> values) {
    String best = '';
    for (final value in values) {
      if (value.trim().length > best.length) best = value.trim();
    }
    return best;
  }

  String _encodeRoutedQuery(int sourceIndex, String rawQuery) => '__composite_route__:$sourceIndex:${Uri.encodeComponent(rawQuery)}';

  _RoutedQuery? _decodeRoutedQuery(String query) {
    const prefix = '__composite_route__:';
    if (!query.startsWith(prefix)) return null;
    final rest = query.substring(prefix.length);
    final firstColon = rest.indexOf(':');
    if (firstColon <= 0) return null;
    final index = int.tryParse(rest.substring(0, firstColon).trim());
    if (index == null) return null;
    return _RoutedQuery(sourceIndex: index, rawQuery: Uri.decodeComponent(rest.substring(firstColon + 1)));
  }
}

class _RoutedQuery {
  final int sourceIndex;
  final String rawQuery;
  const _RoutedQuery({required this.sourceIndex, required this.rawQuery});
}

class _SourceCategoryRef {
  final int sourceIndex;
  final VideoCategory category;
  const _SourceCategoryRef({required this.sourceIndex, required this.category});
}
