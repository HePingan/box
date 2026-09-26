// P2-5 回归测试：未知 area/action code 的回退必须留日志，不再静默丢弃。
//
// 已修复的真实缺陷：_areaFromName / _actionFromName 遇到未知值悄悄回退
// 到中心回退值 / toast，调用方（fromJson / fromMarketTemplate）无从得知
// 数据里有无法识别的 code，问题被完全掩盖。
//
// 这里通过注入一个未知 actionCode 的模板，断言回退发生时确实打了日志。

import 'package:box/features/extensions/core/home_plugin_core.dart';
import 'package:box/features/extensions/market/domain/plugin_market_manifest.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MarketPluginTemplate tplWith({required String area, required String action}) =>
      MarketPluginTemplate(
        id: 'p2_5_probe',
        title: '未知 code 插件',
        subtitle: '',
        areaCode: area,
        actionCode: action,
        payload: '',
        icon: Icons.extension_outlined,
        color: const Color(0xFF112233),
      );

  group('P2-5 未知 area/action 回退留日志', () {
    test('未知 action code 回退 toast 并打日志', () {
      final logs = <String>[];
      final prev = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = prev);

      final cfg = HomeCustomPluginConfig.fromMarketTemplate(
        tplWith(area: 'recommend', action: 'no_such_action_xyz'),
      );

      expect(cfg.actionType, HomePluginActionType.toast,
          reason: '未知 action 仍须安全回退到 toast（行为不变）');
      expect(
        logs.any((l) => l.contains('no_such_action_xyz')),
        isTrue,
        reason: 'P2-5：回退必须留日志，否则数据里的坏 code 无从发现',
      );
    });

    // FIX-03：回退值从 recommend 统一为 center。此前标签路径
    // （homePluginAreaFromCode）回 center、落库路径（_areaFromName）回 recommend，
    // 同一个输入在两条路径上是两个区域。现在只有一条链路。
    test('未知 area code 回退 center 并打日志', () {
      final logs = <String>[];
      final prev = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = prev);

      final cfg = HomeCustomPluginConfig.fromMarketTemplate(
        tplWith(area: 'no_such_area_xyz', action: 'toast'),
      );

      expect(cfg.area, HomePluginArea.center,
          reason: '未知 area 回退到统一回退值 center（与标签路径一致）');
      expect(
        logs.any((l) => l.contains('no_such_area_xyz')),
        isTrue,
        reason: 'P2-5：回退必须留日志',
      );
    });

    test('已知 code 不应产生回退日志（避免噪音）', () {
      final logs = <String>[];
      final prev = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = prev);

      final cfg = HomeCustomPluginConfig.fromMarketTemplate(
        tplWith(area: 'recommend', action: 'toast'),
      );

      expect(cfg.actionType, HomePluginActionType.toast);
      expect(cfg.area, HomePluginArea.recommend);
      expect(
        logs.where((l) => l.contains('已回落到')),
        isEmpty,
        reason: '合法 code 不该刷日志',
      );
    });
  });
}
