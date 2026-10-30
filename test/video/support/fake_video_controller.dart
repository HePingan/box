import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// 上游 video_player 自带的测试替身（`test/video_player_test.dart` 里的 FakeController），
/// 只读 `value`，不需要任何平台通道。拿它渲染我们自己的控件正好。
class FakeVideoController extends ValueNotifier<VideoPlayerValue>
    implements VideoPlayerController {
  FakeVideoController([VideoPlayerValue? value])
    : super(value ?? const VideoPlayerValue(duration: Duration.zero));

  @override
  Future<void> dispose() async => super.dispose();

  @override
  int playerId = VideoPlayerController.kUninitializedPlayerId;

  @override
  String get dataSource => '';

  @override
  Map<String, String> get httpHeaders => <String, String>{};

  @override
  DataSourceType get dataSourceType => DataSourceType.file;

  @override
  String get package => '';

  @override
  Future<Duration> get position async => value.position;

  @override
  VideoViewType get viewType => VideoViewType.textureView;

  @override
  Future<void> seekTo(Duration moment) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setPlaybackSpeed(double speed) async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> setLooping(bool looping) async {}

  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(bool prevents) async {}

  @override
  VideoFormat? get formatHint => null;

  @override
  Future<ClosedCaptionFile> get closedCaptionFile async => _EmptyCc();

  @override
  VideoPlayerOptions? get videoPlayerOptions => null;

  @override
  void setCaptionOffset(Duration delay) {}

  @override
  Future<void> setClosedCaptionFile(Future<ClosedCaptionFile>? f) async {}

  @override
  Future<List<VideoTrack>> getVideoTracks() async => <VideoTrack>[];

  @override
  Future<void> selectVideoTrack(VideoTrack? track) async {}

  @override
  bool isVideoTrackSupportAvailable() => false;

  @override
  Future<List<VideoAudioTrack>> getAudioTracks() async => <VideoAudioTrack>[];

  @override
  Future<void> selectAudioTrack(String trackId) async {}

  @override
  bool isAudioTrackSupportAvailable() => false;
}

class _EmptyCc extends ClosedCaptionFile {
  _EmptyCc();
  @override
  List<Caption> get captions => const <Caption>[];
}
