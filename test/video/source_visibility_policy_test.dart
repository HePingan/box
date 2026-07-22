import 'package:box/video_module.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

VideoSource _source({
  required String id,
  String url = 'https://api.example.test/vod',
  bool enabled = true,
}) {
  return VideoSource(
    id: id,
    name: id,
    url: url,
    detailUrl: url,
    isEnabled: enabled,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    VideoModule.resetForTest();
  });

  test(
    'visibility policy only exposes enabled URL sources without manual or auto hides',
    () async {
      final visible = _source(id: 'visible');
      final disabled = _source(id: 'disabled', enabled: false);
      final noUrl = _source(id: 'no-url', url: '');
      final manualHidden = _source(id: 'manual-hidden');
      final autoHidden = _source(id: 'auto-hidden');

      await VideoModule.setSourceManualHidden(manualHidden, true);
      await VideoModule.setSourceAutoHidden(autoHidden, true);

      expect(VideoModule.isSourceVisible(disabled), isFalse);
      expect(VideoModule.isSourceVisible(noUrl), isFalse);
      expect(
        VideoModule.visibleSourcesOf([
          visible,
          disabled,
          noUrl,
          manualHidden,
          autoHidden,
        ]),
        [visible],
      );
    },
  );

  test(
    'admin-facing source collection includes hidden sources but still rejects disabled and URL-less sources',
    () async {
      final visible = _source(id: 'visible');
      final hidden = _source(id: 'hidden');
      final disabled = _source(id: 'disabled', enabled: false);
      final noUrl = _source(id: 'no-url', url: '');
      await VideoModule.setSourceAutoHidden(hidden, true);

      expect(
        VideoModule.visibleSourcesOf([
          visible,
          hidden,
          disabled,
          noUrl,
        ], includeHidden: true),
        [visible, hidden],
      );
    },
  );
}
