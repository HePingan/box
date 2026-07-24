import 'package:box/video/models/video_source.dart';
import 'package:box/video/services/source_health_service.dart';
import 'package:box/video/services/video_diagnostics_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const source = VideoSource(
    id: 'source-42',
    name: 'Private Source',
    url: 'https://api.example.test/vod?token=api-secret',
    detailUrl: 'https://detail.example.test/detail?cookie=secret-cookie',
  );

  test(
    'health result exposes ordered category list detail and play stages with duration',
    () {
      final result = SourceCheckResult(
        source: source,
        success: false,
        stage: SourceHealthStage.play,
        message: '播放地址不可用',
        checkedAt: DateTime.utc(2026, 7, 22),
        elapsed: const Duration(milliseconds: 123),
        categoryCount: 2,
        videoCount: 3,
      );

      expect(result.stage, SourceHealthStage.play);
      expect(result.elapsed, const Duration(milliseconds: 123));
      expect(SourceHealthStage.ordered, [
        SourceHealthStage.category,
        SourceHealthStage.list,
        SourceHealthStage.detail,
        SourceHealthStage.play,
      ]);
    },
  );

  test(
    'anonymous diagnostic snapshot contains source id status duration and stage only',
    () {
      final result = SourceCheckResult(
        source: source,
        success: false,
        stage: SourceHealthStage.play,
        message: '播放地址不可用 https://stream.example.test/a.m3u8?token=play-secret',
        playableUrl: 'https://stream.example.test/a.m3u8?token=play-secret',
        checkedAt: DateTime.utc(2026, 7, 22),
        elapsed: const Duration(milliseconds: 321),
      );

      final snapshot = VideoDiagnosticsService.anonymousSnapshot([result]);

      expect(snapshot, contains('source-42'));
      expect(snapshot, contains('status=failed'));
      expect(snapshot, contains('stage=play'));
      expect(snapshot, contains('durationMs=321'));
      expect(snapshot, isNot(contains('https://')));
      expect(snapshot, isNot(contains('token=')));
      expect(snapshot, isNot(contains('cookie=')));
      expect(snapshot, isNot(contains('play-secret')));
    },
  );
}
