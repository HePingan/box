import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 接线契约：动作 → 路由 → 页面 → 市场条目。任何一环断了都是「点了没反应」。
void main() {
  final core = File('lib/features/extensions/core/home_plugin_core.dart')
      .readAsStringSync();
  final pages = File('lib/features/extensions/core/builtin_plugin_pages.dart')
      .readAsStringSync();
  final market =
      File('lib/features/extensions/market/domain/plugin_market_manifest.dart')
          .readAsStringSync();

  test('动作枚举 + 中文标签 + 展示顺序都有 openWallpaperGallery', () {
    expect(core, contains('openWallpaperGallery;'));
    expect(core, contains("return '打开壁纸图库'"));
    expect(core, contains('HomePluginActionType.openWallpaperGallery,\n  ];'));
  });

  test('动作处理器存在且走注册表', () {
    expect(core, contains('HomePluginActionType.openWallpaperGallery.name'));
    final start = core.indexOf('openWallpaperGallery.name');
    final block = core.substring(start, start + 400);
    expect(block, contains("lookup('openWallpaperGallery')"));
    // 页面由注册表构造，处理器里不该直接 new（否则注册表形同虚设）
    expect(block, isNot(contains('WallpaperGalleryPage')));
  });

  test('注册表把动作接到图库页', () {
    expect(pages, contains("'openWallpaperGallery'"));
    expect(pages, contains('const WallpaperGalleryPage()'));
    expect(pages, contains('wallpaper_gallery_page.dart'));
  });

  test('市场条目指向真动作、不再是占位，权限如实只有网络', () {
    final start = market.indexOf("id: 'market_comic_wallpaper'");
    expect(start, greaterThan(0));
    // 切到下一条条目为止：固定窗口会圈进隔壁的 comingSoon
    final next = market.indexOf('MarketPluginTemplate(', start + 10);
    final block = market.substring(start, next > start ? next : start + 400);
    expect(block, contains("actionCode: 'openWallpaperGallery'"));
    expect(block, contains("permissions: const ['network']"));
    expect(block, isNot(contains('comingSoon: true')));
  });

  test('壁纸清单地址与自托管目录一致（改域名时两边一起改）', () {
    final api =
        File('lib/features/extensions/plugins/wallpaper/data/wallpaper_api.dart')
            .readAsStringSync();
    expect(
      api,
      contains(
        'https://box.hpa888.top/updates/box/media/wallpapers/manifest.json',
      ),
    );
  });
}
