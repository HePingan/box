import 'package:box/video/utils/play_url_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlayUrlPolicy.shapeOf', () {
    test('媒体直链（含补过 index.m3u8 的）算 media', () {
      for (final raw in <String>[
        'https://bfikuncdn.com/20240523/6Z9jGK4r/index.m3u8',
        'https://hd.ijycnd.com/play/6dBlmVNa/index.m3u8',
        'https://cdn.example/video.mp4',
        'https://cdn.example/live/a.m3u8?sign=abc',
      ]) {
        expect(
          PlayUrlPolicy.shapeOf(Uri.parse(raw)),
          PlayUrlShape.media,
          reason: raw,
        );
      }
    });

    test('采集站的云播页/分享页分别识别为 playPage 与 sharePage', () {
      // 这两条是实测播不了的线路地址（2026-10-02）。
      expect(
        PlayUrlPolicy.shapeOf(Uri.parse('https://play.xluuss.com/play/9aAjlRPb')),
        PlayUrlShape.playPage,
      );
      expect(
        PlayUrlPolicy.shapeOf(
          Uri.parse('https://v.lzcdn28.com/share/f1e2b2c9255d552500a833ac828cd635'),
        ),
        PlayUrlShape.sharePage,
      );
    });

    test('普通接口地址、根路径、相对地址都不算云播页', () {
      for (final raw in <String>[
        'https://iqiyizyapi.com/api.php/provide/vod',
        'https://example.com/',
        'https://example.com/play/',
        'play/ep1.m3u8',
        'not a url',
      ]) {
        final uri = Uri.tryParse(raw);
        expect(PlayUrlPolicy.shapeOf(uri), PlayUrlShape.other, reason: raw);
        expect(PlayUrlPolicy.isCloudPage(uri), isFalse, reason: raw);
      }
    });
  });

  group('PlayUrlPolicy 归一化规则', () {
    test('/play/<id> 的候选是补 /index.m3u8', () {
      final candidates = PlayUrlPolicy.mediaCandidatesFor(
        Uri.parse('https://play.xluuss.com/play/9aAjlRPb'),
      );
      expect(candidates.single.toString(), 'https://play.xluuss.com/play/9aAjlRPb/index.m3u8');
    });

    test('/share/<id> 没有可拼的候选（必须拉页面）', () {
      expect(
        PlayUrlPolicy.mediaCandidatesFor(
          Uri.parse('https://v.lzcdn28.com/share/f1e2b2c9'),
        ),
        isEmpty,
      );
    });

    test('从分享页里取 var main 并还原成绝对地址', () {
      // 这段就是实测页面里的原样片段（注意里面的 \/ 转义）。
      const page = r'''
        <script>
          var     l = ''
          var     r= ''
          var     t= '15'
          var     u= ''
          var main = "\/20241130\/63415_866058d3\/index.m3u8?sign=495a8df5248";
          var xml = "\/20241130\/63415_866058d3\/index.m3u8?sign=x";
        </script>
      ''';

      expect(
        PlayUrlPolicy.extractShareMainUrl(
          page,
          Uri.parse('https://cdn.ryplay11.com/share/b88764f1c8'),
        ),
        'https://cdn.ryplay11.com/20241130/63415_866058d3/index.m3u8?sign=495a8df5248',
      );
      expect(PlayUrlPolicy.extractShareMainPath(page), r'\/20241130\/63415_866058d3\/index.m3u8?sign=495a8df5248');
    });

    test('页面里没有 var main 时返回 null，不猜地址', () {
      expect(
        PlayUrlPolicy.extractShareMainUrl(
          '<html><body>404</body></html>',
          Uri.parse('https://x.example/share/1'),
        ),
        isNull,
      );
    });
  });

  group('PlayUrlPolicy.classifyProbe', () {
    test('HLS 清单判定为 playable', () {
      expect(
        PlayUrlPolicy.classifyProbe(
          statusCode: 206,
          contentType: 'application/vnd.apple.mpegurl',
          body: '#EXTM3U\n#EXT-X-VERSION:3',
        ),
        PlayProbeVerdict.playable,
      );
    });

    test('答了 HTML / 404 判定为 answeredButNotMedia', () {
      expect(
        PlayUrlPolicy.classifyProbe(
          statusCode: 200,
          contentType: 'text/html; charset=utf-8',
          body: '<!DOCTYPE html><html>...',
        ),
        PlayProbeVerdict.answeredButNotMedia,
      );
      expect(
        PlayUrlPolicy.classifyProbe(
          statusCode: 404,
          contentType: 'text/html',
          body: '<html>404 Not Found</html>',
        ),
        PlayProbeVerdict.answeredButNotMedia,
      );
    });

    test('没有正文的 206 分片按 content-type 判定为 playable', () {
      expect(
        PlayUrlPolicy.classifyProbe(
          statusCode: 206,
          contentType: 'video/mp2t',
          body: '',
        ),
        PlayProbeVerdict.playable,
      );
    });

    test('没拿到响应判定为 unreachable（不算死）', () {
      expect(
        PlayUrlPolicy.classifyProbe(statusCode: 0, body: ''),
        PlayProbeVerdict.unreachable,
      );
    });
  });
}
