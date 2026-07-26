import 'dart:async';

import 'package:box/video/widgets/player/custom_video_controls.dart';
import 'package:box/video/widgets/video_play_container.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LatestSeekCommandQueue', () {
    test(
      'coalesces rapid seek requests to the final target and resumes playback',
      () async {
        final seeks = <Duration>[];
        var playCalls = 0;
        final queue = LatestSeekCommandQueue(
          seekTo: (target) async => seeks.add(target),
          resume: () async => playCalls++,
        );

        final first = queue.submit(
          const Duration(seconds: 10),
          resumePlayback: true,
        );
        final second = queue.submit(
          const Duration(seconds: 20),
          resumePlayback: true,
        );
        final third = queue.submit(
          const Duration(seconds: 30),
          resumePlayback: true,
        );
        await Future.wait([first, second, third]);

        expect(seeks, [const Duration(seconds: 30)]);
        expect(playCalls, 1);
      },
    );

    test(
      'resumes only after a newer in-flight seek reaches its final target',
      () async {
        final seeks = <Duration>[];
        final firstSeek = Completer<void>();
        var playCalls = 0;
        final queue = LatestSeekCommandQueue(
          seekTo: (target) async {
            seeks.add(target);
            if (target == const Duration(seconds: 10)) {
              await firstSeek.future;
            }
          },
          resume: () async => playCalls++,
        );

        final first = queue.submit(
          const Duration(seconds: 10),
          resumePlayback: true,
        );
        await Future<void>.delayed(Duration.zero);
        final finalSeek = queue.submit(
          const Duration(seconds: 30),
          resumePlayback: true,
        );
        firstSeek.complete();
        await Future.wait([first, finalSeek]);

        expect(seeks, [
          const Duration(seconds: 10),
          const Duration(seconds: 30),
        ]);
        expect(playCalls, 1);
      },
    );

    test(
      'does not resume playback after a seek started while paused',
      () async {
        var playCalls = 0;
        final queue = LatestSeekCommandQueue(
          seekTo: (_) async {},
          resume: () async => playCalls++,
        );

        await queue.submit(const Duration(seconds: 30), resumePlayback: false);

        expect(playCalls, 0);
      },
    );
  });

  group('FullscreenToggleGate', () {
    test(
      'ignores repeated requests until the actual fullscreen listener changes',
      () {
        var calls = 0;
        final gate = FullscreenToggleGate(() => calls++);

        gate.request();
        gate.request();
        expect(calls, 1);
        expect(gate.isLocked, isTrue);

        gate.onFullScreenChanged(false);
        gate.request();
        expect(calls, 1);

        gate.onFullScreenChanged(true);
        expect(gate.isLocked, isFalse);
        gate.request();
        expect(calls, 2);
      },
    );
    test(
      'unlocks after timeout when Chewie never reports fullscreen state',
      () async {
        var calls = 0;
        final gate = FullscreenToggleGate(
          () => calls++,
          unlockTimeout: const Duration(milliseconds: 1),
        );

        gate.request();
        expect(gate.isLocked, isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(gate.isLocked, isFalse);
        gate.request();
        expect(calls, 2);
      },
    );

    test(
      'reset unlocks a pending request during disposal or lifecycle recovery',
      () {
        final gate = FullscreenToggleGate(() {});

        gate.request();
        expect(gate.isLocked, isTrue);
        gate.reset();

        expect(gate.isLocked, isFalse);
      },
    );
  });
}
