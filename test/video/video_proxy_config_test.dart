import 'package:box/video-Pro/config/video_proxy_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoProxyConfig', () {
    const config = VideoProxyConfig(
      proxyPrefix: 'https://proxy.example.com/?url=',
    );

    test('normalizes root VOD source to provide endpoint', () {
      expect(
        config.normalizeProvideVodEndpoint('https://vod.example.com'),
        'https://vod.example.com/api.php/provide/vod',
      );
      expect(
        config.normalizeProvideVodEndpoint(
          'https://vod.example.com/api.php/provide/vod?ac=list',
        ),
        'https://vod.example.com/api.php/provide/vod?ac=list',
      );
      expect(
        config.normalizeProvideVodEndpoint('https://vod.example.com/custom'),
        'https://vod.example.com/custom',
      );
    });

    test('wraps normalized base url when proxy is enabled', () {
      expect(
        config.buildVodBaseUrl('https://vod.example.com'),
        'https://proxy.example.com/?url=https%3A%2F%2Fvod.example.com%2Fapi.php%2Fprovide%2Fvod',
      );
    });

    test('keeps direct normalized url when proxy is disabled', () {
      final direct = config.copyWith(enabled: false);

      expect(
        direct.buildVodBaseUrl('https://vod.example.com'),
        'https://vod.example.com/api.php/provide/vod',
      );
    });

    test('does not double wrap existing proxy urls', () {
      const proxied =
          'https://proxy.example.com/?url=https%3A%2F%2Fvod.example.com';

      expect(config.wrapWithProxy(proxied), proxied);
      expect(config.isProxyUrl(proxied), isTrue);
    });

    test('adds query to nested target url inside proxy', () {
      final url = config.withQuery(
        'https://proxy.example.com/?url=https%3A%2F%2Fvod.example.com%2Fapi.php%2Fprovide%2Fvod',
        {'ac': 'detail', 'wd': '三体'},
      );

      expect(
        url,
        'https://proxy.example.com/?url=https%3A%2F%2Fvod.example.com%2Fapi.php%2Fprovide%2Fvod%3Fac%3Ddetail%26wd%3D%25E4%25B8%2589%25E4%25BD%2593',
      );
    });

    test('unwraps nested proxy target url', () {
      expect(
        config.unwrapTargetUrl(
          'https://proxy.example.com/?url=https%3A%2F%2Fvod.example.com%2Fapi.php%2Fprovide%2Fvod',
        ),
        'https://vod.example.com/api.php/provide/vod',
      );
    });
  });
}
