import 'package:box/video/services/playback_background_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlaybackBackgroundPolicy.shouldKeepPlaying', () {
    test('开关打开 + 正在播 → 后台继续出声', () {
      expect(
        PlaybackBackgroundPolicy.shouldKeepPlaying(
          enabled: true,
          isPlaying: true,
          isPip: false,
        ),
        isTrue,
      );
    });

    test('开关关掉 → 退回老行为（切后台即暂停）', () {
      expect(
        PlaybackBackgroundPolicy.shouldKeepPlaying(
          enabled: false,
          isPlaying: true,
          isPip: false,
        ),
        isFalse,
      );
    });

    test('本来就没在播 → 不用保活', () {
      expect(
        PlaybackBackgroundPolicy.shouldKeepPlaying(
          enabled: true,
          isPlaying: false,
          isPip: false,
        ),
        isFalse,
      );
    });

    test('小窗里即使开关关掉也继续播（画面还在，那就是用户要的）', () {
      expect(
        PlaybackBackgroundPolicy.shouldKeepPlaying(
          enabled: false,
          isPlaying: true,
          isPip: true,
        ),
        isTrue,
      );
      // 但暂停态的小窗不该被强行播起来。
      expect(
        PlaybackBackgroundPolicy.shouldKeepPlaying(
          enabled: true,
          isPlaying: false,
          isPip: true,
        ),
        isFalse,
      );
    });
  });

  group('PlaybackBackgroundPolicy.shouldResumeOnForeground', () {
    test('后台保活过 → 回前台不要 play（它一直在播）', () {
      expect(
        PlaybackBackgroundPolicy.shouldResumeOnForeground(
          keptPlaying: true,
          wasPlayingBeforeBackground: true,
        ),
        isFalse,
      );
    });

    test('没保活 + 切后台前在播 → 回前台恢复', () {
      expect(
        PlaybackBackgroundPolicy.shouldResumeOnForeground(
          keptPlaying: false,
          wasPlayingBeforeBackground: true,
        ),
        isTrue,
      );
    });

    test('切后台前就是暂停 → 回前台不擅自播放', () {
      expect(
        PlaybackBackgroundPolicy.shouldResumeOnForeground(
          keptPlaying: false,
          wasPlayingBeforeBackground: false,
        ),
        isFalse,
      );
    });
  });

  group('PlaybackBackgroundPolicy.shouldRunService', () {
    test('开关打开 + 正在播 → 要挂（而且是在前台就挂）', () {
      expect(
        PlaybackBackgroundPolicy.shouldRunService(
          enabled: true,
          isPlaying: true,
          isPip: false,
        ),
        isTrue,
      );
    });

    test('开关关掉 → 不挂（退回老行为，也就没有常驻通知）', () {
      expect(
        PlaybackBackgroundPolicy.shouldRunService(
          enabled: false,
          isPlaying: true,
          isPip: false,
        ),
        isFalse,
      );
    });

    test('暂停着不挂（没在播就没什么要保活的）', () {
      expect(
        PlaybackBackgroundPolicy.shouldRunService(
          enabled: true,
          isPlaying: false,
          isPip: false,
        ),
        isFalse,
      );
    });

    test('小窗不挂（Activity 在前台可见，系统不会杀）', () {
      expect(
        PlaybackBackgroundPolicy.shouldRunService(
          enabled: true,
          isPlaying: true,
          isPip: true,
        ),
        isFalse,
      );
    });
  });
}
