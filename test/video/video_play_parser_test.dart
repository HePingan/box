import 'package:box/video-Pro/models/video_source.dart';
import 'package:box/video-Pro/models/vod_item.dart';
import 'package:box/video-Pro/models/vod_item_play_parser.dart';
import 'package:box/video-Pro/pages/detail/detail_models.dart';
import 'package:box/video-Pro/pages/detail/detail_play_parser.dart';
import 'package:box/video-Pro/widgets/player/player_stream_resolver.dart';
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
}
