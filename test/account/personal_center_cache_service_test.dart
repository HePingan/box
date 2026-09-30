import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/account/data/personal_center_cache_service.dart';

void main() {
  // 三个清理口都要注入假实现：不注入的话默认实现会去碰 path_provider 的平台通道
  // （纯 test 里没有插件 → MissingPluginException），用例会红在一个跟被测逻辑无关的地方。
  test('clears network / reader memory / comic image caches', () async {
    var networkCalls = 0;
    var readerCalls = 0;
    var comicCalls = 0;
    final service = PersonalCenterCacheService(
      clearNetworkCache: () async => networkCalls++,
      clearReaderMemoryCache: () => readerCalls++,
      clearComicImageCache: () async {
        comicCalls++;
        return 0;
      },
    );

    await service.clearRegenerableCaches();

    expect(networkCalls, 1);
    expect(readerCalls, 1);
    expect(comicCalls, 1, reason: '漫画图片缓存也要清（以前漏的就是它）');
  });

  test('返回清出的字节数（界面拿它说人话）', () async {
    final service = PersonalCenterCacheService(
      clearNetworkCache: () async {},
      clearReaderMemoryCache: () {},
      clearComicImageCache: () async => 77 * 1024 * 1024,
    );

    expect(await service.clearRegenerableCaches(), 77 * 1024 * 1024);
  });

  test('does not clear reader memory cache when network clear fails', () async {
    var readerCalls = 0;
    var comicCalls = 0;
    final service = PersonalCenterCacheService(
      clearNetworkCache: () async => throw StateError('cache unavailable'),
      clearReaderMemoryCache: () => readerCalls++,
      clearComicImageCache: () async {
        comicCalls++;
        return 0;
      },
    );

    await expectLater(service.clearRegenerableCaches(), throwsStateError);
    expect(readerCalls, 0);
    expect(comicCalls, 0, reason: '前一步失败就不该继续清（半清状态更难解释）');
  });
}
