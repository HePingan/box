import 'package:box/video/models/video_source.dart';
import 'package:box/video/services/source_match.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归「该视频的片源已失效或被移除」的误报：
/// 目录 JSON 里没有 id 字段，源的 id 就是接口地址；上游改过一次地址，
/// 本地历史里那条记录就再也匹配不上，界面只好报「片源已失效」。
VideoSource sourceOf(String id, String name) => VideoSource(
  id: id,
  name: name,
  url: 'https://$id/api.php/provide/vod',
  detailUrl: '',
);

void main() {
  final sources = <VideoSource>[
    sourceOf('cj.lzcaiji.com', '🎬量子资源'),
    sourceOf('iqiyizyapi.com', '🎬-爱奇艺-'),
    sourceOf('caiji.dbzy5.com', '🎬豆瓣资源'),
  ];

  test('id 精确命中优先', () {
    final hit = findVideoSourceForHistory(
      sources,
      sourceId: 'cj.lzcaiji.com',
      sourceName: '🎬量子资源',
    );
    expect(hit?.id, 'cj.lzcaiji.com');
  });

  test('id 漂了（上游换了地址）时按 url 兜住', () {
    final hit = findVideoSourceForHistory(
      sources,
      sourceId: 'https://cj.lzcaiji.com/api.php/provide/vod',
    );
    expect(hit?.id, 'cj.lzcaiji.com');
  });

  test('id 完全对不上时按归一化名字救回来（emoji/前缀差异不影响）', () {
    final hit = findVideoSourceForHistory(
      sources,
      sourceId: 'old.dead.host',
      sourceName: '量子资源',
    );
    expect(hit?.id, 'cj.lzcaiji.com', reason: '名字是同一家，这是那一整类误报的解法');
    expect(
      findVideoSourceForHistory(
        sources,
        sourceId: 'old.dead.host',
        sourceName: '🎬 量子资源 ',
      )?.id,
      'cj.lzcaiji.com',
    );
  });

  test('同名多个时不乱猜', () {
    final dup = <VideoSource>[
      sourceOf('a.example.com', '量子资源'),
      sourceOf('b.example.com', '🎬量子资源'),
    ];
    expect(
      findVideoSourceForHistory(dup, sourceId: 'x', sourceName: '量子资源'),
      isNull,
      reason: '两家同名，猜错就是放错片源',
    );
  });

  test('确实找不到就返回 null（不硬凑）', () {
    expect(
      findVideoSourceForHistory(
        sources,
        sourceId: 'gone.example.com',
        sourceName: '已经下线的源',
      ),
      isNull,
    );
    expect(findVideoSourceForHistory(sources, sourceId: ''), isNull);
  });

  test('归一化：只留字母数字与中日韩字符，统一小写', () {
    expect(normalizeSourceName('🎬量子资源'), '量子资源');
    expect(normalizeSourceName('🎬-爱奇艺-'), '爱奇艺');
    expect(normalizeSourceName('  AAA 视频 '), 'aaa视频');
    expect(normalizeSourceName('🎬'), '');
  });
}
