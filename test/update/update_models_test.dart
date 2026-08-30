import 'package:box/update/update_models.dart';
import 'package:flutter_test/flutter_test.dart';

UpdateManifest manifest({
  int latestVersionCode = 10,
  int minSupportedVersionCode = 0,
  List<int> blockedVersionCodes = const [],
  bool forceUpdate = false,
}) {
  return UpdateManifest(
    schemaVersion: 1,
    appId: 'box',
    platform: 'android',
    channel: 'release',
    packageName: 'top.hpa888.box',
    latestVersionCode: latestVersionCode,
    latestVersionName: '1.0.$latestVersionCode',
    minSupportedVersionCode: minSupportedVersionCode,
    blockedVersionCodes: blockedVersionCodes,
    forceUpdate: forceUpdate,
    title: null,
    notice: null,
    changelog: const [],
    downloadUrl: 'https://example.com/app.apk',
    backupDownloadUrl: null,
    sha256: null,
    fileSize: null,
    publishedAt: null,
    supportUrl: null,
    signatureAlgorithm: null,
    signature: null,
  );
}

void main() {
  group('UpdateManifest version decisions', () {
    test('does not report new version when remote is same or older', () {
      expect(manifest(latestVersionCode: 10).hasNewVersion(10), isFalse);
      expect(manifest(latestVersionCode: 9).hasNewVersion(10), isFalse);
    });

    test('reports new version when remote version code is newer', () {
      expect(manifest(latestVersionCode: 11).hasNewVersion(10), isTrue);
    });

    test('ignores force-update flag when there is no newer version', () {
      expect(
        manifest(latestVersionCode: 10, forceUpdate: true).needForceUpdate(10),
        isFalse,
      );
      expect(
        manifest(
          latestVersionCode: 9,
          minSupportedVersionCode: 99,
          blockedVersionCodes: const [10],
          forceUpdate: true,
        ).needForceUpdate(10),
        isFalse,
      );
    });

    test('requires force update when newer remote sets force flag', () {
      expect(
        manifest(latestVersionCode: 11, forceUpdate: true).needForceUpdate(10),
        isTrue,
      );
    });

    test('requires force update when current version is below minimum', () {
      expect(
        manifest(
          latestVersionCode: 11,
          minSupportedVersionCode: 10,
        ).needForceUpdate(9),
        isTrue,
      );
    });

    test('requires force update when current version is blocked', () {
      expect(
        manifest(
          latestVersionCode: 11,
          blockedVersionCodes: const [10],
        ).needForceUpdate(10),
        isTrue,
      );
    });
  });
}
