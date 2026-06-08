import 'package:flutter_test/flutter_test.dart';
import 'package:box/config/app_config.dart';

void main() {
  group('AppConfig defaults', () {
    test('uses stable app identity defaults', () {
      expect(AppConfig.appId, 'box');
      expect(AppConfig.appChannel, 'release');
    });

    test('uses secure update endpoint by default', () {
      final uri = Uri.parse(AppConfig.updateCheckUrl);

      expect(uri.scheme, 'https');
      expect(uri.host, isNotEmpty);
      expect(uri.path, contains('/app-updates/check'));
    });

    test('allows proceeding when update check fails by default', () {
      expect(AppConfig.allowProceedOnCheckFailure, isTrue);
    });
  });
}
