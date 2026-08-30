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

    test('验签失败默认不放行（fail closed）', () {
      // 多人使用场景下，验签失败还照装等于谁都能给用户推包。
      // 原来默认 true + catch(_) 静默，正是验签 bug 长期存活的根因。
      expect(AppConfig.allowProceedOnCheckFailure, isFalse);
    });
  });
}
