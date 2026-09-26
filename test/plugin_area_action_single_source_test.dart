// 插件域「区域/动作」标签单一事实源回归测试。
//
// 背景（已修复的真实缺陷）：area/action 的中文标签曾被硬编码复制到多处
//   - home_plugin_core.dart        → HomePluginArea.label（枚举，唯一权威）
//   - plugin_market_page.dart      → _areaLabel() + _actionLabel() 自建 switch
//   - plugin_submit_page.dart      → static const _areas / _actions 自建 map
// 且已产生**用户可见不一致**：video 在 HomePluginArea.label 与市场页是「影视」，
// 在投稿页却是「视频」；toast 是「提示动作」vs「弹出提示」。
//
// 修复方向：enum + label getter 为唯一事实源，其余 UI 一律委托。
// 本测试锁定该结构，防止有人再抄一份副本。

import 'dart:io';

import 'package:box/features/extensions/core/home_plugin_core.dart';
import 'package:flutter_test/flutter_test.dart';

const _corePath = 'lib/features/extensions/core/home_plugin_core.dart';
const _marketPath =
    'lib/features/extensions/market/presentation/plugin_market_page.dart';
const _submitPath =
    'lib/features/extensions/market/presentation/plugin_submit_page.dart';

String _read(String p) => File(p).readAsStringSync();

/// 抽 enum 的 label getter：`case Enum.x: return '中文';`
Map<String, String> _enumLabels(String src, String enumName) {
  final idx = src.indexOf('enum $enumName {');
  if (idx < 0) return {};
  final end = src.indexOf('\n}', idx);
  final seg = src.substring(idx, end > 0 ? end : src.length);
  final re = RegExp(
    enumName + r'\.(\w+):\s*\n?\s*return ' + "'" + r"([^']+)" + "'",
    multiLine: true,
  );
  return {for (final m in re.allMatches(seg)) m.group(1)!: m.group(2)!};
}

/// 抽 enum 成员名集合。
Set<String> _enumMembers(String src, String enumName) {
  final idx = src.indexOf('enum $enumName {');
  if (idx < 0) return {};
  final end = src.indexOf(';', idx);
  final seg = src.substring(idx + 'enum $enumName {'.length, end > 0 ? end : src.length);
  return RegExp(r'\b([a-zA-Z]\w*)\b')
      .allMatches(seg)
      .map((m) => m.group(1)!)
      .toSet();
}

void main() {
  group('插件区域(area)标签必须单一事实源', () {
    test('HomePluginArea.label 是唯一定义处且可解析', () {
      final labels = _enumLabels(_read(_corePath), 'HomePluginArea');
      expect(labels, isNotEmpty, reason: '应能从 HomePluginArea.label 抽出标签');
      expect(labels['video'], isNotNull);
      expect(labels['recommend'], isNotNull);
      // 「影视」是权威值 —— 投稿页曾经写成「视频」。
      expect(labels['video'], '影视');
    });

    test('市场页 _areaLabel 委托单一事实源（不得自建 switch 副本）', () {
      final body = _read(_marketPath);
      expect(
        body.contains('String _areaLabel(String code) => homePluginAreaLabel(code)'),
        isTrue,
        reason: '市场页 _areaLabel 必须委托 homePluginAreaLabel()，不得自建标签副本',
      );
    });

    test('投稿页 _areas 由 HomePluginArea.displayOrder 派生（不得硬编码）', () {
      final body = _read(_submitPath);
      expect(
        body.contains('HomePluginArea.displayOrder') &&
            body.contains('_areas = {'),
        isTrue,
        reason: '投稿页 _areas 必须由 HomePluginArea.displayOrder 派生',
      );
      // 不得再出现硬编码的 video/中文标签对
      expect(
        RegExp("'video':\\s*'").hasMatch(body),
        isFalse,
        reason: '投稿页不得再硬编码区域标签（曾因此把 video 写成「视频」）',
      );
    });
  });

  group('插件动作(action)标签必须单一事实源', () {
    test('市场页 _actionLabel 与投稿页 _actions 均委托事实源', () {
      final market = _read(_marketPath);
      expect(
        market.contains('String _actionLabel(String code) => homePluginActionLabel(code)'),
        isTrue,
        reason: '市场页 _actionLabel 必须委托 homePluginActionLabel()',
      );
      final submit = _read(_submitPath);
      expect(
        submit.contains('HomePluginActionType.displayOrder'),
        isTrue,
        reason: '投稿页 _actions 必须由 HomePluginActionType.displayOrder 派生',
      );
      expect(
        RegExp("'toast':\\s*'").hasMatch(submit),
        isFalse,
        reason: '投稿页不得再硬编码动作标签（曾把 toast 写成「弹出提示」）',
      );
    });

    test('每个已注册 action handler 都必须在 HomePluginActionType 枚举里', () {
      final core = _read(_corePath);
      final regIdx = core.indexOf('class HomePluginActionRegistry');
      expect(regIdx, greaterThan(-1));
      // 只取注册表那一小段（到 _handlers 的闭合 `};`），避免误抓其它 'x': 字面量
      final reg = core.substring(regIdx);
      final mapStart = reg.indexOf('_handlers = {');
      final mapEnd = reg.indexOf('};', mapStart);
      final seg = reg.substring(mapStart, mapEnd);
      final rawLiterals = RegExp("^\\s*'([A-Za-z]\\w*)':", multiLine: true)
          .allMatches(seg)
          .map((m) => m.group(1)!)
          .toSet();
      expect(
        rawLiterals,
        isEmpty,
        reason:
            'action handler 不得以裸字符串注册：$rawLiterals —— '
            '必须写成 HomePluginActionType.x.name，使枚举保持为受支持动作的单一事实源',
      );
    });

    test('navigate 必须在枚举内（曾是已实现却漏登记的 action）', () {
      final members = _enumMembers(_read(_corePath), 'HomePluginActionType');
      expect(
        members.contains('navigate'),
        isTrue,
        reason: 'navigate 已有 handler 实现，必须登记进 HomePluginActionType',
      );
    });
  });

  // FIX-03：区域解析必须只有一条链路。此前三份实现两种回退：
  //   标签路径（homePluginAreaFromCode）→ center，
  //   落库路径（_areaFromName）→ recommend，
  //   市场白名单（_allowedAreaCodes，5 个值）→ recommend。
  // 结果：同一个 center 输入，标签说「工具」而落库进「推荐」。
  group('区域解析：标签路径与落库路径必须一致（FIX-03）', () {
    test('任意 code 两路径解析结果一致', () {
      const inputs = [
        'recommend',
        'music',
        'video',
        'comic',
        'novel',
        'center',
        '',
        'bogus',
        'Center',
      ];
      for (final code in inputs) {
        final label = homePluginAreaLabel(code);
        final cfg = HomeCustomPluginConfig.fromJson(<String, dynamic>{
          'id': 'x',
          'title': 'x',
          'area': code,
        });
        expect(
          homePluginAreaLabel(cfg.area.name),
          label,
          reason: 'code="$code" 标签路径与落库路径不一致',
        );
      }
    });

    test('未知 code 的回退值是 center（与标签路径一致）', () {
      expect(kHomePluginAreaFallback, HomePluginArea.center);
      expect(homePluginAreaFromCode('bogus'), HomePluginArea.center);
    });

    test('市场允许区域 = 枚举全集 - 排除集（新增枚举值自动生效）', () {
      expect(
        marketAllowedAreas,
        HomePluginArea.values.toSet()..remove(HomePluginArea.center),
        reason: '硬编码白名单会在新增区域时静默失效，必须由枚举派生',
      );
      expect(marketAllowedAreas.contains(HomePluginArea.center), isFalse);
    });
  });
}
