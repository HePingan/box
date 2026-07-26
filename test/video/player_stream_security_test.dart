import 'package:flutter_test/flutter_test.dart';

import 'package:box/video/widgets/player/player_stream_resolver.dart';

void main() {
  group('player stream URL safety', () {
    test('allows public HTTPS media URLs', () {
      expect(
        isAllowedRemoteMediaUri(
          Uri.parse('https://cdn.example.com/live/a.m3u8'),
        ),
        isTrue,
      );
    });

    test('rejects unsafe schemes and local network targets', () {
      for (final raw in <String>[
        'file:///etc/passwd',
        'http://localhost:8080/private.m3u8',
        'https://127.0.0.1/a.m3u8',
        'https://10.0.0.7/a.m3u8',
        'https://192.168.1.8/a.m3u8',
        'https://172.16.2.5/a.m3u8',
        'https://169.254.169.254/latest/meta-data',
        'https://[::1]/a.m3u8',
      ]) {
        expect(isAllowedRemoteMediaUri(Uri.parse(raw)), isFalse, reason: raw);
      }
    });

    test(
      'removes query parameters and fragments from media URLs used in logs',
      () {
        expect(
          sanitizeMediaUrl(
            'https://cdn.example.com/live/playlist.m3u8?token=secret&expires=1#part',
          ),
          'https://cdn.example.com/live/playlist.m3u8',
        );
        expect(sanitizeMediaUrl('not a URL'), '[invalid-url]');
      },
    );
  });
}
