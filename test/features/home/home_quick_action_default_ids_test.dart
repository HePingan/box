// 默认快捷入口 id 必须真实存在于内置插件表。
//
// 这是个容易静默失效的地方：defaultIds 里写错一个字，首页会把它过滤掉，
// 结果新装用户看到的快捷入口少一个甚至全空，而且不报任何错。
//
// 两个坑（都实测过）：
//  1. bootstrap() 会碰 path_provider，纯测试环境没平台实现会挂死 300s+；
//     所以走 builtInPluginsForTesting()。
//  2. _buildDefaultPlugins() 并不纯——它会调 QuizPluginEntry.initAutoSearch，
//     那里 setMethodCallHandler 需要 binding 已初始化；所以必须用
//     testWidgets（自带 binding），普通 test() 会断言失败。
import 'package:box/features/extensions/core/home_plugin_core.dart';
import 'package:box/features/home/data/home_quick_action_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('defaultIds 全部能在内置插件表里找到', (tester) async {
    final builtIns = HomePluginHost.instance.builtInPluginsForTesting();
    final knownIds = builtIns.map((p) => p.id).toSet();

    expect(
      knownIds,
      isNotEmpty,
      reason: '内置插件表为空，本测试失去意义',
    );

    for (final id in HomeQuickActionPrefs.defaultIds) {
      expect(
        knownIds.contains(id),
        isTrue,
        reason:
            '默认快捷入口 "$id" 在内置插件表里不存在，首页会静默少一个入口。'
            '可用 id：${knownIds.toList()..sort()}',
      );
    }
  });

  testWidgets('默认 id 数量不超过槽位上限', (tester) async {
    expect(
      HomeQuickActionPrefs.defaultIds.length,
      lessThanOrEqualTo(HomeQuickActionPrefs.maxSlots),
    );
  });
}
