/// 详情页播放模型：选集、线路、默认播放定位

class DetailPlayEpisode {
  final String name;
  final String url;

  const DetailPlayEpisode({
    required this.name,
    required this.url,
  });
}

class DetailPlayLine {
  final String name;
  final List<DetailPlayEpisode> episodes;

  const DetailPlayLine({
    required this.name,
    required this.episodes,
  });

  bool get isEmpty => episodes.isEmpty;
  bool get isNotEmpty => episodes.isNotEmpty;
}

class DetailPlaybackSelection {
  final int lineIndex;
  final int episodeIndex;
  final String? url;
  final String? name;

  const DetailPlaybackSelection({
    required this.lineIndex,
    required this.episodeIndex,
    required this.url,
    required this.name,
  });

  const DetailPlaybackSelection.none()
      : lineIndex = 0,
        episodeIndex = 0,
        url = null,
        name = null;
}