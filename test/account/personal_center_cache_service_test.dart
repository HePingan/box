import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/account/data/personal_center_cache_service.dart';

void main() {
  test('clears network and reader memory caches', () async {
    var networkCalls = 0;
    var readerCalls = 0;
    final service = PersonalCenterCacheService(
      clearNetworkCache: () async => networkCalls++,
      clearReaderMemoryCache: () => readerCalls++,
    );

    await service.clearRegenerableCaches();

    expect(networkCalls, 1);
    expect(readerCalls, 1);
  });

  test('does not clear reader memory cache when network clear fails', () async {
    var readerCalls = 0;
    final service = PersonalCenterCacheService(
      clearNetworkCache: () async => throw StateError('cache unavailable'),
      clearReaderMemoryCache: () => readerCalls++,
    );

    await expectLater(service.clearRegenerableCaches(), throwsStateError);
    expect(readerCalls, 0);
  });
}
