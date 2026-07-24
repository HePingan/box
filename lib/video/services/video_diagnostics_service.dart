import 'source_health_service.dart';

/// Produces support-safe diagnostics. It intentionally serializes no URLs,
/// headers, cookies, query parameters, or response bodies.
class VideoDiagnosticsService {
  const VideoDiagnosticsService._();

  static String anonymousSnapshot(Iterable<SourceCheckResult> results) {
    return results
        .map(
          (result) => [
            'sourceId=${result.source.id}',
            'status=${result.success ? 'ok' : 'failed'}',
            'stage=${result.stage.name}',
            'durationMs=${result.elapsed.inMilliseconds}',
            'categories=${result.categoryCount}',
            'videos=${result.videoCount}',
          ].join(' '),
        )
        .join('\n');
  }
}
