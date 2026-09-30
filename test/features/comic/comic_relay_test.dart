// 中转客户端的用例：请求地址 / 请求头 / 错误映射。**不联网**（假 http client）。
//
// 三条底线各有用例：
//   * 令牌**只在请求头**里（地址、参数、错误文案里都不许出现）；
//   * 401/403/502 分得清（用户要能自己判断"是令牌不对"还是"站点取不到"）；
//   * 只有 http/https 才包中转，本中转自己的地址不重复包。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:box/features/comic/domain/comic_relay.dart';
import 'package:box/features/comic/domain/comic_source_engine.dart'
    show ComicProbeException;

const String _endpoint = 'https://box.hpa888.top/comicrelay/fetch';
const String _token = 'tok-test-0123456789abcdef';

ComicRelay _relay(http.Client client) =>
    ComicRelay(endpoint: _endpoint, token: _token, client: client);

/// 带 UTF-8 声明（不写 charset 时 `http.Response` 会按 latin1 编码中文而直接抛错）。
http.Response _json(String body, int status) => http.Response(
  body,
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  group('取文本', () {
    test('GET：原始地址进 u 参数，令牌只在请求头里', () async {
      late http.Request seen;
      final relay = _relay(
        MockClient((req) async {
          seen = req;
          return http.Response(
            '<html>ok</html>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }),
      );

      final body = await relay.getText(
        'https://yemancomic.com/search?searchkey=%E6%B5%B7%E8%B4%BC',
      );

      expect(body, '<html>ok</html>');
      expect(seen.method, 'GET');
      expect(seen.url.origin + seen.url.path, _endpoint);
      expect(
        seen.url.queryParameters['u'],
        'https://yemancomic.com/search?searchkey=%E6%B5%B7%E8%B4%BC',
      );
      expect(seen.headers['X-Box-Token'], _token);
      // 令牌绝不进地址（地址会进代理日志/审计）
      expect(seen.url.toString(), isNot(contains(_token)));
    });

    test('POST 表单：方法、表单体、令牌都对得上', () async {
      late http.Request seen;
      final relay = _relay(
        MockClient((req) async {
          seen = req;
          return _json(jsonEncode({'data': {'pic': []}}), 200);
        }),
      );

      final body = await relay.postForm(
        'https://yemancomic.com/api/comic/read/pics',
        {'id': '772668', 'aid': '7530', 'offset': '5'},
      );

      expect(seen.method, 'POST');
      expect(seen.headers['X-Box-Token'], _token);
      expect(seen.bodyFields, {
        'id': '772668',
        'aid': '7530',
        'offset': '5',
      });
      expect(
        seen.url.queryParameters['u'],
        'https://yemancomic.com/api/comic/read/pics',
      );
      expect(body, contains('"pic"'));
    });

    test('中文响应按 UTF-8 解（不写成乱码）', () async {
      final relay = _relay(
        MockClient((req) async => _json('{"error":"取不到"}', 502)),
      );
      try {
        await relay.getText('https://yemancomic.com/');
        fail('502 必须抛错');
      } on ComicProbeException catch (e) {
        expect(e.message, contains('取不到'));
      }
    });
  });

  group('错误映射', () {
    test('403：带上服务器给的原因（白名单）', () async {
      final relay = _relay(
        MockClient(
          (req) async => _json('{"error":"不在白名单：evil.example:443"}', 403),
        ),
      );
      await expectLater(
        relay.getText('https://evil.example/x'),
        throwsA(
          isA<ComicProbeException>().having(
            (e) => e.message,
            'message',
            allOf(contains('白名单'), contains('evil.example')),
          ),
        ),
      );
    });

    test('401 与 502 各有各的人话（用户要能自查）', () async {
      final r401 = _relay(
        MockClient((req) async => _json('{"error":"令牌无效"}', 401)),
      );
      await expectLater(
        r401.getText('https://yemancomic.com/'),
        throwsA(
          isA<ComicProbeException>().having(
            (e) => e.message,
            'message',
            contains('设备令牌'),
          ),
        ),
      );

      final r502 = _relay(
        MockClient((req) async => _json('{"error":"取不到（URLError）"}', 502)),
      );
      await expectLater(
        r502.getText('https://yemancomic.com/'),
        throwsA(
          isA<ComicProbeException>().having(
            (e) => e.message,
            'message',
            allOf(contains('中转取不到'), contains('URLError')),
          ),
        ),
      );
    });

    test('响应体不是 JSON：也给一句人话，且**不**把整个体塞进文案', () async {
      final relay = _relay(
        MockClient(
          (req) async => http.Response('<html>502 Bad Gateway</html>', 502),
        ),
      );
      try {
        await relay.getText('https://yemancomic.com/');
        fail('必须抛错');
      } on ComicProbeException catch (e) {
        expect(e.message, contains('中转取不到'));
        expect(e.message, isNot(contains('<html>')));
      }
    });

    test('错误文案里绝不出现令牌', () async {
      final relay = _relay(MockClient((req) async => _json('boom', 500)));
      try {
        await relay.getText('https://yemancomic.com/');
        fail('必须抛错');
      } on ComicProbeException catch (e) {
        expect(e.message, isNot(contains(_token)));
        expect(e.message, contains('HTTP 500'));
      }
    });

    test('连不上：报"中转请求失败"（不是空结果）', () async {
      final relay = _relay(MockClient((req) async {
        throw http.ClientException('socket closed');
      }));
      await expectLater(
        relay.getText('https://yemancomic.com/'),
        throwsA(
          isA<ComicProbeException>().having(
            (e) => e.message,
            'message',
            contains('中转请求失败'),
          ),
        ),
      );
    });
  });

  group('包装地址', () {
    test('只包 http/https；本中转自己的地址不重复包', () {
      final relay = _relay(MockClient((req) async => http.Response('', 200)));

      expect(relay.canRelay('https://tuer.justpic01pt.com:666/a.jpg'), isTrue);
      expect(relay.canRelay('http://tuer.justpic01pt.com:666/a.jpg'), isTrue);
      expect(relay.canRelay('/relative/a.jpg'), isFalse);
      expect(relay.canRelay('data:image/png;base64,AA=='), isFalse);
      expect(relay.canRelay(''), isFalse);

      final wrapped = relay.wrap('https://tuer.justpic01pt.com:666/a.jpg');
      expect(wrapped, startsWith('$_endpoint?u='));
      expect(
        Uri.parse(wrapped).queryParameters['u'],
        'https://tuer.justpic01pt.com:666/a.jpg',
      );
      // 令牌在请求头里，不在地址里
      expect(wrapped, isNot(contains(_token)));
      // 已经是中转地址 → 不再包一层（否则 u 里套 u）
      expect(relay.canRelay(wrapped), isFalse);
      expect(relay.wrap(wrapped), wrapped);
    });
  });
}
