import 'models.dart';
import 'video_source.dart';

class SampleVideoSource implements VideoSource {
  const SampleVideoSource();

  static const String _providerKey = 'sample';

  static const List<VideoItem> _items = [
    VideoItem(
      id: 'sample::sample_big_buck_bunny',
      title: 'Big Buck Bunny',
      intro: '开放版权示例视频，适合测试播放、拖动、倍速和进度记忆。',
      cover: '',
      detailUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
      category: '示例视频',
      yearText: '2008',
      sourceName: '免费样例',
      providerKey: _providerKey,
    ),
    VideoItem(
      id: 'sample::sample_elephants_dream',
      title: 'Elephants Dream',
      intro: '开放版权动画短片，适合测试播放器。',
      cover: '',
      detailUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
      category: '示例视频',
      yearText: '2006',
      sourceName: '免费样例',
      providerKey: _providerKey,
    ),
    VideoItem(
      id: 'sample::sample_sintel',
      title: 'Sintel',
      intro: '开放版权短片，画面和音轨都适合播放器测试。',
      cover: '',
      detailUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
      category: '示例视频',
      yearText: '2010',
      sourceName: '免费样例',
      providerKey: _providerKey,
    ),
    VideoItem(
      id: 'sample::sample_tears_of_steel',
      title: 'Tears of Steel',
      intro: 'Blender 开放版权短片，可用于测试长视频播放。',
      cover: '',
      detailUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4',
      category: '示例视频',
      yearText: '2012',
      sourceName: '免费样例',
      providerKey: _providerKey,
    ),
    VideoItem(
      id: 'sample::sample_for_bigger_blazes',
      title: 'For Bigger Blazes',
      intro: 'Google 提供的公开视频样例。',
      cover: '',
      detailUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
      category: '示例视频',
      yearText: '2016',
      sourceName: '免费样例',
      providerKey: _providerKey,
    ),
  ];

  @override
  String get sourceName => '免费样例';

  @override
  List<VideoCategory> get categories => const [
        VideoCategory(
          id: 'sample',
          title: '示例视频',
          query: 'sample',
          description: '稳定可播放的免费样例',
        ),
      ];

  @override
  Future<List<VideoItem>> searchVideos(String keyword, {int page = 1}) async {
    if (page > 1) return const [];

    final q = keyword.trim().toLowerCase();
    if (q.isEmpty) return _items;

    return _items.where((item) {
      return item.title.toLowerCase().contains(q) ||
          item.intro.toLowerCase().contains(q) ||
          item.category.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Future<List<VideoItem>> fetchByPath(String path, {int page = 1}) async {
    if (page > 1) return const [];

    final q = path.trim().toLowerCase();
    if (q.isEmpty || q.contains('sample') || q.contains('示例')) {
      return _items;
    }
    return searchVideos(path, page: page);
  }

  @override
  Future<VideoDetail> fetchDetail({
    required VideoItem item,
  }) async {
    final target = _items.firstWhere(
      (e) => e.id == item.id || e.detailUrl == item.detailUrl,
      orElse: () => throw StateError('未找到示例视频：${item.id}'),
    );

    return VideoDetail(
      item: target,
      cover: target.cover,
      creator: 'Open Sample',
      description: target.intro,
      tags: const ['示例', '公开视频'],
      playSources: [
        VideoPlaySource(
          name: '默认线路',
          episodes: [
            VideoEpisode(
              title: '${target.title} 正片',
              url: target.detailUrl,
              index: 0,
            ),
          ],
        ),
      ],
      sourceUrl: target.detailUrl,
    );
  }
}