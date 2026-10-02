import 'package:box/video/services/cloud_play_url_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// 造一份「按地址回答」的假探测：不联网也能把归一化规则钉住。
MediaProbe _probeOf(Map<String, MediaProbeResult> table, List<Uri> calls) {
  return (Uri uri) async {
    calls.add(uri);
    return table[uri.toString()] ??
        const MediaProbeResult(statusCode: 0);
  };
}

MediaProbeResult _playlist() => const MediaProbeResult(
  statusCode: 200,
  contentType: 'application/vnd.apple.mpegurl',
  body: '#EXTM3U\n#EXT-X-TARGETDURATION:10',
);

MediaProbeResult _html(String body) =>
    MediaProbeResult(statusCode: 200, contentType: 'text/html', body: body);

void main() {
  const resolver = CloudPlayUrlResolver();
  const headers = <String, String>{'User-Agent': 'box-test'};

  test('/play/<id> 补 /index.m3u8 命中就直接用它', () async {
    final calls = <Uri>[];
    final page = Uri.parse('https://play.xluuss.com/play/9aAjlRPb');

    final resolved = await resolver.resolve(
      page,
      headers: headers,
      probe: _probeOf(<String, MediaProbeResult>{
        'https://play.xluuss.com/play/9aAjlRPb/index.m3u8': _playlist(),
      }, calls),
    );

    expect(
      resolved.toString(),
      'https://play.xluuss.com/play/9aAjlRPb/index.m3u8',
    );
    expect(calls, hasLength(1));
  });

  test('/play/<id> 补路径不成时，回退到页面里的 var main', () async {
    final page = Uri.parse('https://v.gsuus.com/play/kazVzrma');
    final calls = <Uri>[];

    final resolved = await resolver.resolve(
      page,
      headers: headers,
      probe: _probeOf(<String, MediaProbeResult>{
        'https://v.gsuus.com/play/kazVzrma/index.m3u8': _html('<html>nope</html>'),
        '$page': _html(
          r'''<script>var main = "\/20241130\/63415\/index.m3u8?sign=abc";</script>''',
        ),
        'https://v.gsuus.com/20241130/63415/index.m3u8?sign=abc': _playlist(),
      }, calls),
    );

    expect(
      resolved.toString(),
      'https://v.gsuus.com/20241130/63415/index.m3u8?sign=abc',
    );
  });

  test('/share/<id> 走页面 var main（补 /index.m3u8 是 404）', () async {
    final page = Uri.parse('https://cdn.ryplay11.com/share/b88764f1c8');
    final calls = <Uri>[];

    final resolved = await resolver.resolve(
      page,
      headers: headers,
      probe: _probeOf(<String, MediaProbeResult>{
        'https://cdn.ryplay11.com/20241130/63415/index.m3u8?sign=xyz': _playlist(),
        '$page': _html(
          r'''var main = "\/20241130\/63415\/index.m3u8?sign=xyz";''',
        ),
      }, calls),
    );

    expect(
      resolved.toString(),
      'https://cdn.ryplay11.com/20241130/63415/index.m3u8?sign=xyz',
    );
  });

  test('什么规则都不命中时原样返回，绝不猜地址', () async {
    final page = Uri.parse('https://ukzy.ukubf4.com/share/cUrgOEtJKRvcLBDn');

    final resolved = await resolver.resolve(
      page,
      headers: headers,
      probe: _probeOf(<String, MediaProbeResult>{
        '$page': _html('<html>站点首页</html>'),
      }, <Uri>[]),
    );

    expect(resolved, page);
  });

  test('已经是媒体直链时一次探测都不做', () async {
    final calls = <Uri>[];
    final media = Uri.parse('https://cdn.example/a/index.m3u8');

    final resolved = await resolver.resolve(
      media,
      headers: headers,
      probe: _probeOf(<String, MediaProbeResult>{}, calls),
    );

    expect(resolved, media);
    expect(calls, isEmpty);
  });

  test('探测抛异常也不能把播放路径带崩', () async {
    final page = Uri.parse('https://play.xluuss.com/play/9aAjlRPb');

    final resolved = await resolver.resolve(
      page,
      headers: headers,
      probe: (Uri uri) async => throw const SocketExceptionStub(),
    );

    expect(resolved, page);
  });
}

/// 只是为了让上面那条用例抛出一个真实异常类型（不引入 dart:io）。
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
