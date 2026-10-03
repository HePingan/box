import 'package:box/video/services/video_playback_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('默认开：影视 App 里息屏/切后台继续出声是预期行为', () async {
    final settings = VideoPlaybackSettings();
    expect(await settings.backgroundPlaybackEnabled(), isTrue);
  });

  test('关掉之后读回来是关（写进去了）', () async {
    final settings = VideoPlaybackSettings();

    await settings.setBackgroundPlaybackEnabled(false);
    expect(await settings.backgroundPlaybackEnabled(), isFalse);

    await settings.setBackgroundPlaybackEnabled(true);
    expect(await settings.backgroundPlaybackEnabled(), isTrue);
  });

  test('读取时存储坏了 → 退回默认值（开），不能让播放卡住', () async {
    final settings = VideoPlaybackSettings(
      prefs: () => Future<SharedPreferences>.error(StateError('boom')),
    );
    expect(await settings.backgroundPlaybackEnabled(), isTrue);
  });

  test('写入失败不抛（只影响下次启动的默认值）', () async {
    final settings = VideoPlaybackSettings(
      prefs: () => Future<SharedPreferences>.error(StateError('boom')),
    );
    await expectLater(
      settings.setBackgroundPlaybackEnabled(false),
      completes,
    );
  });

  test('键名固定：换名字等于把用户的设置丢掉', () {
    expect(VideoPlaybackSettings.backgroundPlaybackKey, 'video.background_playback');
  });
}
