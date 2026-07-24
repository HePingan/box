import 'package:box/video/models/video_category.dart';
import 'package:box/video/models/video_source.dart';
import 'package:box/video/services/source_health_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const source = VideoSource(
    id: 'source-unsafe-error',
    name: 'Source',
    url: 'https://api.example.test/vod?token=source-secret',
    detailUrl: 'https://api.example.test/detail',
  );

  test(
    'health failures do not expose endpoint or raw exception details',
    () async {
      final service = _FailingHealthService();

      final result = await service.checkSource(source);

      expect(result.success, isFalse);
      expect(result.stage, SourceHealthStage.exception);
      expect(result.message, '健康检查请求失败，请稍后重试');
      expect(result.message, isNot(contains('source-secret')));
      expect(result.message, isNot(contains('backend-detail')));
    },
  );
}

class _FailingHealthService extends SourceHealthService {
  @override
  Future<List<VideoCategory>> fetchCategoriesForHealthCheck(
    VideoSource source,
  ) async {
    throw StateError('backend-detail ${source.url}');
  }
}
