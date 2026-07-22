import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:box/video-Pro/services/request_policy.dart';

void main() {
  group('VideoGetRequestPolicy', () {
    test(
      'retries transient GET failures with injected exponential delays',
      () async {
        var attempts = 0;
        final delays = <Duration>[];
        final policy = VideoGetRequestPolicy(
          maxAttempts: 3,
          baseDelay: const Duration(milliseconds: 10),
          wait: (delay) async => delays.add(delay),
        );

        final value = await policy.execute<String>(() async {
          attempts++;
          if (attempts < 3) throw const SocketException('offline');
          return 'ok';
        });

        expect(value, 'ok');
        expect(attempts, 3);
        expect(delays, const [
          Duration(milliseconds: 10),
          Duration(milliseconds: 20),
        ]);
      },
    );

    test('does not retry client HTTP failures', () async {
      var attempts = 0;
      final policy = VideoGetRequestPolicy(maxAttempts: 3, wait: (_) async {});

      await expectLater(
        () => policy.execute<void>(() async {
          attempts++;
          throw const VideoHttpException(404);
        }),
        throwsA(isA<VideoHttpException>()),
      );

      expect(attempts, 1);
    });

    test('maps transport failures to a generic user-safe message', () {
      expect(
        VideoRequestFailure.from(
          const SocketException('private details'),
        ).userMessage,
        '网络连接失败，请稍后重试',
      );
      expect(
        VideoRequestFailure.from(const VideoHttpException(503)).userMessage,
        '服务暂时不可用，请稍后重试',
      );
      expect(
        VideoRequestFailure.from(const VideoHttpException(403)).userMessage,
        '服务拒绝访问，请检查片源配置',
      );
    });
  });
}
