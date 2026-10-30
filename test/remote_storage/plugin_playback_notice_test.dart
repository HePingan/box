import 'dart:io';

import 'package:box/features/extensions/plugins/remote_storage/domain/plugin_playback_notice.dart';
import 'package:box/video/widgets/player/playback_notification_channel.dart';
import 'package:flutter_test/flutter_test.dart';

/// ⑥B 后台播放：插件播放器（远程存储视频 + 音乐区白噪音/电台）的通知文案与
/// 命令映射，以及「保活真的接上了」的源码契约。
///
/// 背景：影视播放器早就接了这套保活，插件播放器一直没接 —— 白噪音/睡眠电台
/// 播到锁屏就被系统冻住断声，而「整夜黑屏播」正是它唯一的使用场景。
void main() {
  group('PluginPlaybackNotice.title', () {
    test('普通条目就用文件名', () {
      expect(
        PluginPlaybackNotice.title(
          entryName: '白色噪音.mp3',
          looping: false,
        ),
        '白色噪音.mp3',
      );
    });

    test('循环播放时标出「循环」（否则用户看到静止标题会以为卡住）', () {
      expect(
        PluginPlaybackNotice.title(entryName: '专注白噪音', looping: true),
        '专注白噪音 · 循环',
      );
    });

    test('名字为空时不显示一条空白通知', () {
      expect(
        PluginPlaybackNotice.title(entryName: '   ', looping: false),
        '远程存储',
      );
    });
  });

  group('PluginPlaybackNotice.text', () {
    test('暂停态统一写「已暂停」', () {
      expect(
        PluginPlaybackNotice.text(playing: false, isAudio: true),
        '已暂停',
      );
      expect(
        PluginPlaybackNotice.text(playing: false, isAudio: false),
        '已暂停',
      );
    });

    test('音频与视频的播放中文案分开（音频要说清能在通知栏操作）', () {
      expect(
        PluginPlaybackNotice.text(playing: true, isAudio: true),
        contains('通知栏'),
      );
      expect(
        PluginPlaybackNotice.text(playing: true, isAudio: false),
        '正在后台播放',
      );
    });
  });

  group('PluginPlaybackNotice.seekDeltaFor', () {
    test('上一首/下一首映射成 ∓15 秒', () {
      expect(
        PluginPlaybackNotice.seekDeltaFor(
          PlaybackNotificationChannel.commandPrevious,
        ),
        const Duration(seconds: -15),
      );
      expect(
        PluginPlaybackNotice.seekDeltaFor(PlaybackNotificationChannel.commandNext),
        const Duration(seconds: 15),
      );
    });

    test('命令字面量与平台通道常量一致（改一边而另一边不动会静默失效）', () {
      // 本文件用字面量是为了不依赖平台通道；这条断言把两边钉在一起。
      expect(
        PluginPlaybackNotice.seekDeltaFor('previous'),
        PluginPlaybackNotice.seekDeltaFor(
          PlaybackNotificationChannel.commandPrevious,
        ),
      );
      expect(
        PluginPlaybackNotice.seekDeltaFor('next'),
        PluginPlaybackNotice.seekDeltaFor(
          PlaybackNotificationChannel.commandNext,
        ),
      );
    });

    test('认不出的命令返回 null（不瞎跳进度）', () {
      expect(
        PluginPlaybackNotice.seekDeltaFor(
          PlaybackNotificationChannel.commandToggle,
        ),
        isNull,
      );
      expect(PluginPlaybackNotice.seekDeltaFor('whatever'), isNull);
    });
  });

  group('接线契约：插件播放器真的挂了保活', () {
    final source = File(
      'lib/features/extensions/plugins/remote_storage/presentation/'
      'remote_storage_player_page.dart',
    ).readAsStringSync();

    test('订阅通知命令并在 dispose 里取消', () {
      expect(source, contains('PlaybackNotificationChannel.instance'));
      expect(source, contains('_playbackNotification.commands.listen'));
      expect(source, contains('_playbackCommandSub?.cancel()'));
    });

    test('开播即 startForeground、退出即 stop（不能等切后台）', () {
      expect(source, contains('_maybeStartPlaybackNotification()'));
      expect(source, contains('_playbackNotification.start('));
      expect(source, contains('_stopPlaybackNotification()'));
      expect(source, contains('PlaybackBackgroundPolicy.shouldRunService'));
    });

    test('通知文案走 PluginPlaybackNotice，标题带曲名与循环标记', () {
      expect(source, contains('PluginPlaybackNotice.title('));
      expect(source, contains('entryName: widget.entry.name'));
      expect(source, contains('looping: widget.looping'));
      expect(source, contains('PluginPlaybackNotice.text('));
    });

    test('音频/视频分型：靠 remoteEntryKind 判定', () {
      expect(source, contains('RemoteEntryKind.audio'));
      expect(source, contains('_isAudio'));
    });

    test('通知按钮：切换播放、±15 秒、音频焦点被抢先让路', () {
      expect(source, contains('PlaybackNotificationChannel.commandToggle'));
      expect(source, contains('PlaybackNotificationChannel.commandPrevious'));
      expect(source, contains('PlaybackNotificationChannel.commandNext'));
      expect(source, contains('PlaybackNotificationChannel.commandAudioFocusLost'));
      expect(source, contains('PluginPlaybackNotice.seekDeltaFor(command)'));
      expect(source, contains('controller.seekTo(clamped)'));
    });

    test('进度跳转要夹在 [0, duration] 内（否则 seekTo 会被播放器忽略）', () {
      expect(source, contains('Duration.zero'));
      expect(source, contains('target > max ? max : target'));
    });

    test('tick 监听既负责起服务也负责同步状态，且避免每帧写通知', () {
      expect(source, contains('controller.addListener(_onPlaybackTick)'));
      expect(source, contains('_controller?.removeListener(_onPlaybackTick)'));
      expect(source, contains('if (_lastNotificationPlaying == now) return;'));
    });
  });
}
