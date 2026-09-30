// 直连取数器（`ComicDirectFetcher`）的测试。
//
// 重点是那条**真坑**：站点认客户端特征 —— 手机 UA 给全量 HTML，桌面 UA 给
// HTTP 307 空响应（实测，当初就是被这个误判成"站点在手机那条网上被拦"）。
// 所以这里盯住"请求真的带了手机 UA""报错要能指出这一点""地址不包中转"。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:box/features/comic/domain/comic_fetcher.dart';
import 'package:box/features/comic/domain/comic_source_engine.dart'
    show ComicProbeException;

void main() {
  group('直连取数器（ComicDirectFetcher）', () {
    test('getText：请求真的带手机 UA（不带就被站点 307 掉）', () async {
      final seen = <String, String>{};
      final fetcher = ComicDirectFetcher(
        client: MockClient((req) async {
          seen.addAll(req.headers);
          return http.Response('<html>ok</html>', 200);
        }),
      );

      final body = await fetcher.getText(
        'https://yemancomic.com/search?searchkey=x',
      );

      expect(body, contains('ok'));
      expect(seen['User-Agent'], kComicMobileUserAgent);
      expect(seen['User-Agent'], contains('Android'));
      // 图片下载也拿这份头（图片缓存用它），所以 headers 要一致。
      expect(fetcher.headers['User-Agent'], kComicMobileUserAgent);
    });

    test('postForm：表单按表单送（取图接口只认表单），同样带手机 UA', () async {
      Map<String, String>? form;
      String? ua;
      final fetcher = ComicDirectFetcher(
        client: MockClient((req) async {
          form = req.bodyFields;
          ua = req.headers['User-Agent'];
          return http.Response(jsonEncode({'data': {'pic': []}}), 200);
        }),
      );

      final body = await fetcher.postForm(
        'https://yemancomic.com/api/comic/read/pics',
        {'id': '772668', 'aid': '7530', 'offset': '0'},
      );

      expect(jsonDecode(body), isA<Map<String, dynamic>>());
      expect(form, {'id': '772668', 'aid': '7530', 'offset': '0'});
      expect(ua, contains('Android'));
    });

    test('wrap：直连不包地址（图片地址原样进图片缓存）', () {
      final fetcher = ComicDirectFetcher(
        client: MockClient((req) async => http.Response('', 200)),
      );
      const pic = 'https://tuer.justpic01pt.com:666/picbed/a.jpg';

      expect(fetcher.wrap(pic), pic);
      expect(fetcher.wrap(pic), isNot(contains('comicrelay')));
    });

    test('307（站点把桌面 UA 跳走）：报错要说"要带手机 UA"，不是含糊的失败', () async {
      final fetcher = ComicDirectFetcher(
        client: MockClient((req) async => http.Response('', 307)),
      );

      await expectLater(
        fetcher.getText('https://yemancomic.com/search?searchkey=x'),
        throwsA(
          isA<ComicProbeException>().having(
            (e) => e.message,
            'message',
            contains('手机 UA'),
          ),
        ),
      );
    });

    test('响应没带 charset 也按 UTF-8 解（否则中文书名乱码）', () async {
      final fetcher = ComicDirectFetcher(
        client: MockClient(
          (req) async => http.Response.bytes(utf8.encode('海贼王'), 200),
        ),
      );

      expect(await fetcher.getText('https://yemancomic.com/book/7530/'), '海贼王');
    });

    test('丢连接（站点偶发）：报"连不上站点"，不是一堆栈噪音', () async {
      final fetcher = ComicDirectFetcher(
        client: MockClient((req) async => throw const SocketException('连接被重置')),
      );

      await expectLater(
        fetcher.getText('https://yemancomic.com/book/7530/'),
        throwsA(
          isA<ComicProbeException>().having(
            (e) => e.message,
            'message',
            contains('连不上站点'),
          ),
        ),
      );
    });
  });

  // 取图的请求头（封面 / 章节图共用一套）。两条要么出图、要么出**为什么**的规矩：
  //   * 图床/站点地址：只给手机 UA（不带 UA 的请求会被丢掉）；
  //   * 设备令牌**只发给自己的中转** —— 发给第三方图床就是泄露。
  group('取图请求头', () {
    const relay = 'https://box.hpa888.top/comicrelay/fetch';
    const cdn = 'https://tuer.justpic01pt.com:666/picbed/CPMH/haizeiwang/a.jpg';

    test('直连头：手机 UA（图床也认客户端特征）', () {
      expect(comicDirectHeaders()['User-Agent'], kComicMobileUserAgent);
    });

    test('图床地址**不带**令牌；中转地址才带令牌', () {
      final forCdn = comicImageHeadersFor(
        cdn,
        relayEndpoint: relay,
        relayToken: 'tok-175',
      );
      expect(forCdn.containsKey('X-Box-Token'), isFalse);
      expect(forCdn['User-Agent'], contains('Android'));

      final forRelay = comicImageHeadersFor(
        '$relay?u=https%3A%2F%2Ftuer.justpic01pt.com%2Fx.jpg',
        relayEndpoint: relay,
        relayToken: 'tok-175',
      );
      expect(forRelay['X-Box-Token'], 'tok-175');
    });

    test('像但不是我方中转的地址（别的域名 / 别的路径）也不给令牌', () {
      for (final u in <String>[
        'https://evil.example.com/comicrelay/fetch?u=x', // 同路径、不同域名
        'https://box.hpa888.top/updates/box/android/release/v.json', // 同域名、不同路径
      ]) {
        expect(
          comicImageHeadersFor(u, relayEndpoint: relay, relayToken: 'tok-175')
              .containsKey('X-Box-Token'),
          isFalse,
          reason: '$u 不该拿到令牌',
        );
      }
    });

    test('没令牌就只给手机 UA（不抛）', () {
      final h = comicImageHeadersFor(cdn, relayEndpoint: relay, relayToken: '');
      expect(h.containsKey('X-Box-Token'), isFalse);
      expect(h['User-Agent'], kComicMobileUserAgent);
    });
  });
}
