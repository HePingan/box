// 音乐区第一个真插件必须指向真页面（阶段 2 回归锁）。
//
// 背景：music 分区长期是 **0 插件**——内容页四宫格的「音乐」能进占位页，
// 但插件区的音乐分区什么都没有；市场里那两条（专注白噪音 / 睡眠电台）
// 还是 comingSoon。于是「音乐」在两个入口上是两种体验。
//
// 阶段 2 把它接上：music 分区加一条 builtin_music_online，点进去是在线音频
// （贴 URL → 下载 → 复用 remote_storage 播放页）。这条用例锁住接线。
import 'package:box/features/extensions/core/builtin_plugin_catalog.dart';
import 'package:box/features/extensions/core/home_plugin_core.dart';
import 'package:box/features/music/presentation/music_placeholder_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('music 分区不再是空的（阶段 2 之前是 0 插件）', () {
    final musicPlugins = buildDefaultPlugins()
        .where((p) => p.area == HomePluginArea.music)
        .toList();

    expect(
      musicPlugins,
      isNotEmpty,
      reason: '音乐分区 0 插件时，插件区那一栏是空白 —— '
          '用户会以为音乐功能坏了，而内容页四宫格的音乐是能进的',
    );
    expect(
      musicPlugins.any((p) => p.id == 'builtin_music_online'),
      isTrue,
      reason: '在线音频是音乐区第一个真插件',
    );
  });

  testWidgets('「在线音频」打开的是音乐页，而不是一句"开发中"', (tester) async {
    final entry = buildDefaultPlugins().firstWhere(
      (p) => p.id == 'builtin_music_online',
    );
    final onTap = entry.onTap;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => onTap(context),
              child: const Text('进音乐'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('进音乐'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(MusicPlaceholderPage), findsOneWidget);
  });

  test('openMusic 动作已登记进枚举，且有路由（投稿页能选到）', () {
    expect(
      HomePluginActionType.values.contains(HomePluginActionType.openMusic),
      isTrue,
      reason: '动作没进枚举的话，注册表那条 handler 就成了枚举外的孤儿',
    );
    expect(
      HomePluginActionType.displayOrder.contains(HomePluginActionType.openMusic),
      isTrue,
      reason: '不在 displayOrder 里，投稿页下拉就选不到它',
    );

    HomePluginRouteRegistry.registerDefaults();
    expect(
      HomePluginRouteRegistry.lookup('openMusic'),
      isNotNull,
      reason: '动作 handler 靠这个 code 找页面，缺了就是点了没反应',
    );
  });

  test('动作与路由的注册不是"裸字符串"（枚举仍是单一事实源）', () {
    // 与 plugin_area_action_single_source_test 同口径，这里只针对新增的
    // openMusic 做一次就地断言，避免以后有人用 'openMusic' 字面量注册。
    expect(HomePluginActionType.openMusic.name, 'openMusic');
    expect(HomePluginActionType.openMusic.label, '打开音乐');
  });
}
