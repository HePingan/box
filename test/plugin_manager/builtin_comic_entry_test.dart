// 漫画区唯一入口必须指向真页面（回归锁）。
//
// 背景：这个入口原先自造了一个 inline 占位页，写着「漫画功能将在后续版本上线」，
// 而漫画库（ComicLibraryPage + 阅读器）早已实现、也从内容仓库可达 —— 用户点
// 漫画区唯一入口，看到的却是一句假话。这条用例锁住：入口进的是真页面。
import 'package:box/features/comic/presentation/comic_library_page.dart';
import 'package:box/features/extensions/core/builtin_plugin_catalog.dart';
import 'package:box/features/extensions/core/home_plugin_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('「漫画收藏」打开的是漫画库页面，不是那句「将在后续版本上线」', (tester) async {
    final entry = buildDefaultPlugins().firstWhere(
      (p) => p.id == 'builtin_comic_shelf',
    );
    // onTap 在类型上就是非空的：入口必须有去向（没有的话这行代码就编译不过）。
    final onTap = entry.onTap;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => onTap(context),
              child: const Text('进漫画'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('进漫画'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(ComicLibraryPage), findsOneWidget);
    expect(
      find.textContaining('将在后续版本上线'),
      findsNothing,
      reason: '这句假话不该再出现 —— 漫画库是真的做好了',
    );
  });

  test('漫画库路由两个 code 都注册上了（市场条目将来可直接跳）', () {
    HomePluginRouteRegistry.registerDefaults();
    expect(HomePluginRouteRegistry.lookup('openComicLibrary'), isNotNull);
    expect(HomePluginRouteRegistry.lookup('comic_library'), isNotNull);
  });
}
