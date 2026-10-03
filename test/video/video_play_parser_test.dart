import 'package:box/video/models/video_source.dart';
import 'package:box/video/models/vod_item.dart';
import 'package:box/video/models/vod_item_play_parser.dart';
import 'package:box/video/pages/detail/detail_models.dart';
import 'package:box/video/pages/detail/detail_play_parser.dart';
import 'package:box/video/widgets/player/player_stream_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VodItemPlayParser', () {
    test('parses multi-line sources and keeps urls after first dollar sign', () {
      final groups = VodItemPlayParser.parse(
        vodPlayFrom: r' 线路A $$$线路B ',
        vodPlayUrl:
            r'第1集$https://cdn.example/a.m3u8?token=a$b#第2集$ /relative/b.m3u8 $$$ https://cdn.example/c.mp4',
      );

      expect(groups, hasLength(2));
      expect(groups.first.name, '线路A');
      expect(groups.first.episodes.map((e) => e.name), ['第1集', '第2集']);
      expect(
        groups.first.episodes.first.url,
        'https://cdn.example/a.m3u8?token=a\$b',
      );
      expect(groups.first.episodes.last.url, '/relative/b.m3u8');
      expect(groups.last.name, '线路B');
      expect(groups.last.episodes.single.name, '第1集');
      expect(groups.last.episodes.single.url, 'https://cdn.example/c.mp4');
    });

    test('falls back to generated line names and drops empty url entries', () {
      final groups = VodItemPlayParser.parse(
        vodPlayFrom: null,
        vodPlayUrl: '   #空标题\$  #https://cdn.example/only-url.mp4',
      );

      expect(groups, hasLength(1));
      expect(groups.single.name, '线路1');
      expect(groups.single.episodes, hasLength(1));
      expect(groups.single.episodes.single.name, '第3集');
      expect(
        groups.single.episodes.single.url,
        'https://cdn.example/only-url.mp4',
      );
    });
  });

  group('DetailPlayParser', () {
    const source = VideoSource(
      id: 'demo',
      name: 'Demo',
      url: 'https://api.example.com/api.php/provide/vod/',
      detailUrl: 'https://site.example.com/detail/movie/123.html',
    );

    test('builds detail play lines and resolves relative episode urls', () {
      final detail = VodItem(
        vodId: 1,
        vodName: '测试影片',
        vodPlayFrom: '主线',
        vodPlayUrl: '第1集\$play/ep1.m3u8#第2集\$//cdn.example/ep2.m3u8',
      );

      final lines = DetailPlayParser.buildPlayLines(detail, source);

      expect(lines, hasLength(1));
      expect(lines.single.name, '主线');
      expect(lines.single.episodes.map((e) => e.name), ['第1集', '第2集']);
      expect(
        lines.single.episodes.first.url,
        'https://site.example.com/detail/movie/play/ep1.m3u8',
      );
      expect(lines.single.episodes.last.url, 'https://cdn.example/ep2.m3u8');
    });

    test('picks initial episode by canonical url ignoring fragments', () {
      const lines = [
        DetailPlayLine(
          name: '主线',
          episodes: [
            DetailPlayEpisode(
              name: '第1集',
              url: 'https://cdn.example/a.m3u8#mobile',
            ),
            DetailPlayEpisode(name: '第2集', url: 'https://cdn.example/b.m3u8'),
          ],
        ),
      ];

      final selection = DetailPlayParser.pickDefaultSelection(
        lines,
        initialEpisodeUrl: 'https://cdn.example/a.m3u8#tv',
      );

      expect(selection.lineIndex, 0);
      expect(selection.episodeIndex, 0);
      expect(selection.name, '第1集');
      expect(selection.url, 'https://cdn.example/a.m3u8#mobile');
    });

    test('formats playback position as mm:ss or hh:mm:ss', () {
      expect(DetailPlayParser.formatPosition(61 * 1000), '01:01');
      expect(DetailPlayParser.formatPosition(3661 * 1000), '01:01:01');
    });

    test('默认线路优先选真媒体，而不是云播网页线路', () {
      // 实测：21 部影片里 10 部的第一条线路是云播网页，默认选中点开就是失败。
      const lines = [
        DetailPlayLine(
          name: 'xlyun',
          episodes: [
            DetailPlayEpisode(
              name: '第1集',
              url: 'https://play.xluuss.com/play/9aAjlRPb',
            ),
          ],
        ),
        DetailPlayLine(
          name: 'xlm3u8',
          episodes: [
            DetailPlayEpisode(
              name: '第1集',
              url: 'https://play.xluuss.com/20240523/x/index.m3u8',
            ),
          ],
        ),
      ];

      final selection = DetailPlayParser.pickDefaultSelection(lines);
      expect(selection.lineIndex, 1);
      expect(selection.url, 'https://play.xluuss.com/20240523/x/index.m3u8');
    });

    test('全部是网页线路时退回第一条（不改变旧行为）', () {
      const lines = [
        DetailPlayLine(
          name: '线路1',
          episodes: [
            DetailPlayEpisode(
              name: '第1集',
              url: 'https://play.xluuss.com/play/9aAjlRPb',
            ),
          ],
        ),
        DetailPlayLine(
          name: '线路2',
          episodes: [
            DetailPlayEpisode(
              name: '第1集',
              url: 'https://v.lzcdn28.com/share/abc',
            ),
          ],
        ),
      ];

      final selection = DetailPlayParser.pickDefaultSelection(lines);
      expect(selection.lineIndex, 0);
    });
  });

  group('player stream pure helpers', () {
    test('normalizes escaped and protocol-relative playable urls', () {
      expect(
        normalizePlayableUrl('  \\//cdn.example/video.m3u8  '),
        'https://cdn.example/video.m3u8',
      );
    });

    test(
      'detects known platform web pages that are not direct media files',
      () {
        expect(
          isInvalidWebPageUrl(Uri.parse('https://v.qq.com/x/cover/demo.html')),
          isTrue,
        );
        expect(
          isInvalidWebPageUrl(Uri.parse('https://www.iqiyi.com/v_abc')),
          isTrue,
        );
        expect(
          isInvalidWebPageUrl(Uri.parse('https://v.qq.com/video/demo.m3u8')),
          isFalse,
        );
        expect(
          isInvalidWebPageUrl(Uri.parse('https://cdn.example/video.mp4')),
          isFalse,
        );
      },
    );
  });

  group('matchEpisodeByName（跨源续播）', () {
    List<DetailPlayLine> lines() => [
      const DetailPlayLine(
        name: '云播',
        episodes: [
          DetailPlayEpisode(name: '第3集', url: 'https://x.example.com/play/3'),
        ],
      ),
      const DetailPlayLine(
        name: 'm3u8',
        episodes: [
          DetailPlayEpisode(name: '第03集', url: 'https://x.example.com/3.m3u8'),
          DetailPlayEpisode(name: '第04集', url: 'https://x.example.com/4.m3u8'),
        ],
      ),
    ];

    test('按剧集名认同一集，且优先落在真媒体线路上（第03集 == 第3集）', () {
      final hit = DetailPlayParser.matchEpisodeByName(
        lines(),
        '第3集',
        preferLineIndex: 1,
      );
      expect(hit, isNotNull);
      expect(hit!.lineIndex, 1, reason: '首选线路是真媒体线路时不该认到云播网页那条');
      expect(hit.episodeIndex, 0);
    });

    test('没有同名剧集就返回 null（交给默认选片逻辑）', () {
      expect(DetailPlayParser.matchEpisodeByName(lines(), '第09集'), isNull);
      expect(DetailPlayParser.matchEpisodeByName(lines(), '   '), isNull);
    });

    test('传了剧集名但地址命中时，地址优先（片源内续播行为不变）', () {
      final selection = DetailPlayParser.pickDefaultSelection(
        lines(),
        initialEpisodeUrl: 'https://x.example.com/play/3',
        initialEpisodeName: '第03集',
      );
      expect(selection.lineIndex, 0, reason: '地址命中优先，仍然是原来那一集');
      expect(selection.name, '第3集');
    });

    test('路径撞上时 sameUrl 就会命中（它按路径比，不管主机）', () {
      final selection = DetailPlayParser.pickDefaultSelection(
        lines(),
        initialEpisodeUrl: 'https://old-source.example.com/3.m3u8',
        initialEpisodeName: '第04集',
      );
      expect(
        selection.name,
        '第03集',
        reason: '路径一致（/3.m3u8）就算命中，哪怕主机不同 —— 这是 sameUrl 的既有口径',
      );
      expect(selection.lineIndex, 1);
    });

    test('地址对不上时按剧集名选（换源场景）', () {
      // 注意：sameUrl 是**按路径**比的（不管主机）——路径撞上时会走地址命中，
      // 所以这里故意换一条不同形态的路径，才是真正的「换源」场景。
      final selection = DetailPlayParser.pickDefaultSelection(
        lines(),
        initialEpisodeUrl: 'https://old-source.example.com/oldpath/4/seg.m3u8',
        initialEpisodeName: '第04集',
      );
      expect(selection.lineIndex, 1);
      expect(selection.name, '第04集');
    });
  });
}
