import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/account/domain/account_models.dart';

void main() {
  test('normalizes legacy account server URLs to HTTPS domain', () {
    expect(
      BoxAccountDefaults.normalizeServerUrl('http://47.109.97.1:8799'),
      'https://background.hpa888.top',
    );
    expect(
      BoxAccountDefaults.normalizeServerUrl(' http://47.109.97.1 '),
      'https://background.hpa888.top',
    );
  });

  test(
    'keeps custom account server URL and falls back to default when empty',
    () {
      expect(
        BoxAccountDefaults.normalizeServerUrl('https://custom.example.com'),
        'https://custom.example.com',
      );
      expect(
        BoxAccountDefaults.normalizeServerUrl('  '),
        'https://background.hpa888.top',
      );
    },
  );
}
