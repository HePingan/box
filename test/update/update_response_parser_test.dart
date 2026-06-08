import 'package:box/update/update_response_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('update response parser', () {
    test('extracts direct manifest maps', () {
      final result = extractUpdateDataMap({
        'latestVersionCode': 2,
        'downloadUrl': 'https://example.com/app.apk',
      });

      expect(result['latestVersionCode'], 2);
      expect(result['downloadUrl'], 'https://example.com/app.apk');
    });

    test('unwraps envelope data maps', () {
      final result = extractUpdateDataMap({
        'code': 0,
        'message': 'ok',
        'data': {
          'latestVersionCode': '3',
          'downloadUrl': 'https://example.com/app.apk',
        },
      });

      expect(result, {
        'latestVersionCode': '3',
        'downloadUrl': 'https://example.com/app.apk',
      });
    });

    test('decodes json string responses', () {
      final result = extractUpdateDataMap(
        '{"code":0,"data":{"latestVersionName":"1.2.0","downloadUrl":"https://example.com/app.apk"}}',
      );

      expect(result['latestVersionName'], '1.2.0');
    });

    test('throws for unsupported response shapes', () {
      expect(() => extractUpdateDataMap('[1,2,3]'), throwsException);
      expect(() => extractUpdateDataMap('{}'), throwsException);
      expect(() => extractUpdateDataMap(42), throwsException);
    });

    test(
      'keeps numeric and string version fields unchanged for manifest parsing',
      () {
        final numeric = extractUpdateDataMap({
          'latestVersionCode': 12,
          'minSupportedVersionCode': 10,
          'downloadUrl': 'https://example.com/app.apk',
        });
        final string = extractUpdateDataMap({
          'latestVersionCode': '12',
          'minSupportedVersionCode': '10',
          'downloadUrl': 'https://example.com/app.apk',
        });

        expect(numeric['latestVersionCode'], 12);
        expect(numeric['minSupportedVersionCode'], 10);
        expect(string['latestVersionCode'], '12');
        expect(string['minSupportedVersionCode'], '10');
      },
    );

    test('throws when downloadUrl is missing or blank', () {
      expect(
        () => extractUpdateDataMap({'latestVersionCode': 2}),
        throwsException,
      );
      expect(
        () => extractUpdateDataMap({
          'latestVersionCode': 2,
          'downloadUrl': '   ',
        }),
        throwsException,
      );
    });
  });
}
